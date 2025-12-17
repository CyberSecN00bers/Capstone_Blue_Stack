#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Configuration
# ==============================

API_BASE="${API_BASE:-http://localhost:3001/api}"

ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

NEW_ADMIN_PASSWORD="${NEW_ADMIN_PASSWORD:-ChangeMe!123}"
TOTP_CODE="${TOTP_CODE:-}"

PROXY_CONTAINER="${PROXY_CONTAINER:-blueteam_stack-nginx-1}"
JUICESHOP_CONTAINER="${JUICESHOP_CONTAINER:-juice-shop}"
DVWA_CONTAINER="${DVWA_CONTAINER:-dvwa}"

AUTO_CONNECT_NETWORK="${AUTO_CONNECT_NETWORK:-true}"

log() { echo "[*] $*" >&2; }
die() { echo "[!] $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

container_running() {
  local c="$1"
  docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null | grep -qi '^true$'
}

container_networks() {
  local c="$1"
  docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' "$c" 2>/dev/null || true
}

find_common_network() {
  local a="$1" b="$2" net
  while IFS= read -r net; do
    [[ -z "$net" ]] && continue
    docker inspect -f "{{if index .NetworkSettings.Networks \"$net\"}}yes{{end}}" "$b" 2>/dev/null | grep -q '^yes$' && {
      echo "$net"; return 0;
    }
  done < <(container_networks "$a")
  return 1
}

container_ip_on_network() {
  local c="$1" net="$2"
  docker inspect -f "{{(index .NetworkSettings.Networks \"$net\").IPAddress}}" "$c" 2>/dev/null || true
}

resolve_upstream_ip() {
  local proxy="$1" target="$2"

  container_running "$proxy" || die "Proxy container not running or not found: $proxy"
  container_running "$target" || die "Target container not running or not found: $target"

  local common_net
  common_net="$(find_common_network "$proxy" "$target" || true)"

  if [[ -z "$common_net" && "$AUTO_CONNECT_NETWORK" == "true" ]]; then
    local target_net
    target_net="$(container_networks "$target" | head -n 1 || true)"
    if [[ -n "$target_net" ]]; then
      log "No common network between '$proxy' and '$target'. Connecting proxy to '$target_net'..."
      docker network connect "$target_net" "$proxy" >/dev/null 2>&1 || true
      common_net="$(find_common_network "$proxy" "$target" || true)"
    fi
  fi

  [[ -n "$common_net" ]] || die "No common Docker network between '$proxy' and '$target' (and auto-connect failed)."

  local ip
  ip="$(container_ip_on_network "$target" "$common_net")"
  [[ -n "$ip" ]] || die "Could not resolve IP of '$target' on network '$common_net'."

  log "Resolved '$target' IP on '$common_net' => $ip"
  echo "$ip"
}

build_domain_payload() {
  local domain_name="$1" upstream_ip="$2" upstream_port="$3"

  jq -n \
    --arg name "$domain_name" \
    --arg host "$upstream_ip" \
    --argjson port "$upstream_port" \
    '{
      name: $name,
      status: "active",
      modsecEnabled: true,
      upstreams: [
        {
          host: $host,
          port: $port,
          protocol: "http",
          sslVerify: false,
          weight: 1,
          maxFails: 3,
          failTimeout: 30
        }
      ],
      loadBalancer: {
        algorithm: "round_robin",
        healthCheckEnabled: true,
        healthCheckInterval: 30,
        healthCheckTimeout: 5,
        healthCheckPath: "/"
      },
      realIpConfig: {
        realIpEnabled: false,
        realIpCloudflare: false,
        realIpCustomCidrs: []
      },
      advancedConfig: {
        hstsEnabled: false,
        http2Enabled: true,
        grpcEnabled: false,
        clientMaxBodySize: 100,
        customLocations: []
      }
    }'
}

change_password_first_login() {
  local user_id="$1" temp_token="$2" new_password="$3"

  log "Changing admin password via FIRST-LOGIN endpoint..."
  local body resp
  body=$(jq -n --arg u "$user_id" --arg t "$temp_token" --arg n "$new_password" '{userId: $u, tempToken: $t, newPassword: $n}')

  resp="$(curl -sS -X POST "$API_BASE/auth/first-login/change-password" \
    -H "Content-Type: application/json" \
    -d "$body" || true)"

  echo "$resp" | jq . >/dev/null 2>&1 || {
    log "First-login password change response is not valid JSON:"
    echo "$resp"
    return 1
  }

  log "First-login password change API called successfully."
  return 0
}

# Returns token on stdout; returns non-zero on failure (does NOT exit)
login() {
  local username="$1" password="$2"
  log "Logging in as user: $username"

  local login_body resp require_change token
  if [[ -n "$TOTP_CODE" ]]; then
    login_body=$(jq -n --arg u "$username" --arg p "$password" --arg t "$TOTP_CODE" '{username:$u,password:$p,totpCode:$t}')
  else
    login_body=$(jq -n --arg u "$username" --arg p "$password" '{username:$u,password:$p}')
  fi

  resp="$(curl -sS -X POST "$API_BASE/auth/login" \
    -H "Content-Type: application/json" \
    -d "$login_body" || true)"

  require_change="$(echo "$resp" | jq -r '.data.requirePasswordChange // "false"' 2>/dev/null || echo "false")"

  if [[ "$require_change" == "true" ]]; then
    log "Server requires first-time password change (requirePasswordChange = true)."

    local user_id temp_token
    user_id="$(echo "$resp" | jq -r '.data.userId // empty')"
    temp_token="$(echo "$resp" | jq -r '.data.tempToken // empty')"

    if [[ -z "$user_id" || -z "$temp_token" || "$user_id" == "null" || "$temp_token" == "null" ]]; then
      log "ERROR: requirePasswordChange=true but userId/tempToken are missing."
      log "Raw response:"
      echo "$resp"
      return 1
    fi

    change_password_first_login "$user_id" "$temp_token" "$NEW_ADMIN_PASSWORD" || return 1

    log "Re-logging in with NEW_ADMIN_PASSWORD after first-login password change..."
    login_body=$(jq -n --arg u "$username" --arg p "$NEW_ADMIN_PASSWORD" '{username:$u,password:$p}')

    resp="$(curl -sS -X POST "$API_BASE/auth/login" \
      -H "Content-Type: application/json" \
      -d "$login_body" || true)"
  fi

  token="$(echo "$resp" | jq -r '.data.accessToken // .accessToken // empty' 2>/dev/null || echo "")"
  if [[ -z "$token" || "$token" == "null" ]]; then
    log "ERROR: Cannot extract access token from login response."
    log "Raw response:"
    echo "$resp"
    return 1
  fi

  echo "$token"
  return 0
}

login_with_fallback() {
  local token=""
  if token="$(login "$ADMIN_USERNAME" "$ADMIN_PASSWORD")"; then
    echo "$token"; return 0
  fi

  log "Login failed with ADMIN_PASSWORD. Trying NEW_ADMIN_PASSWORD..."
  if token="$(login "$ADMIN_USERNAME" "$NEW_ADMIN_PASSWORD")"; then
    echo "$token"; return 0
  fi

  die "Login failed with both ADMIN_PASSWORD and NEW_ADMIN_PASSWORD."
}

create_domain() {
  local token="$1" payload="$2"
  local name resp

  name=$(echo "$payload" | jq -r '.name // "unknown"' 2>/dev/null || echo "unknown")
  log "Creating domain '$name' via /domains ..."

  resp="$(curl -sS -X POST "$API_BASE/domains" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$payload" || true)"

  echo "$resp" | jq . >/dev/null 2>&1 || {
    log "Create domain response is not valid JSON:"
    echo "$resp"
    return 1
  }

  log "Domain '$name' created. Response:"
  echo "$resp" | jq .
}

main() {
  require_cmd curl
  require_cmd jq
  require_cmd docker

  # Require passwords from environment (no hardcoded defaults)
  [[ -n "${ADMIN_PASSWORD:-}" ]] || die "ADMIN_PASSWORD is required (export ADMIN_PASSWORD=... or set it in .env)"
  if [[ -z "${NEW_ADMIN_PASSWORD:-}" ]]; then
    # If you do not need first-login password change, reuse ADMIN_PASSWORD
    NEW_ADMIN_PASSWORD="$ADMIN_PASSWORD"
  fi

  log "=== Step 0: Resolve upstream IPs (from container names) ==="
  local juice_ip dvwa_ip
  juice_ip="$(resolve_upstream_ip "$PROXY_CONTAINER" "$JUICESHOP_CONTAINER")"
  dvwa_ip="$(resolve_upstream_ip "$PROXY_CONTAINER" "$DVWA_CONTAINER")"

  local DOMAIN_JUICESHOP_PAYLOAD DOMAIN_DVWA_PAYLOAD
  DOMAIN_JUICESHOP_PAYLOAD="$(build_domain_payload "juiceshop.local" "$juice_ip" 3000)"
  DOMAIN_DVWA_PAYLOAD="$(build_domain_payload "dvwa.local" "$dvwa_ip" 80)"

  log "=== Step 1: Login & (if required) change admin password ==="
  local token
  token="$(login_with_fallback)"
  log "Access token acquired."

  log "=== Step 2: Create juiceshop.local ==="
  create_domain "$token" "$DOMAIN_JUICESHOP_PAYLOAD"

  log "=== Step 3: Create dvwa.local ==="
  create_domain "$token" "$DOMAIN_DVWA_PAYLOAD"

  log "Bootstrap completed."
}

main "$@"