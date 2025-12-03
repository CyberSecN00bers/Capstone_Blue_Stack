# 🚀 Wazuh Docker – Multi-Node Deployment

This repository deploys **Wazuh in a multi-node architecture** using Docker Compose:

- 🧠 **2 Wazuh Managers**
- 📊 **3 Wazuh Indexers**
- 🖥️ **1 Wazuh Dashboard**
- 🌐 **Nginx reverse proxy (submodule included)**

> 🔐 **Dashboard URL:** `https://HOST_IP:444`

---

## 📦 Requirements

Before starting, make sure you have:

- ✅ Docker >= 20.x  
- ✅ Docker Compose Plugin  
- ✅ Git  

---

## 🏗 Architecture

```
 Browser
   │
   ▼
https://HOST_IP:444
   │
   ▼
Wazuh Dashboard
   │
   ├── Wazuh Manager (x2)
   │
   └── Wazuh Indexer (x3)
```

---

## ⚙️ Installation

### 1️⃣ Clone the repository
```bash
git clone <REPO_URL>
cd <REPO_NAME>
```

---

### 2️⃣ Create the environment file
```bash
cp .env.example .env
```

---

### 3️⃣ Initialize nginx submodule
```bash
git submodule update --init --recursive
```

---

### 4️⃣ Generate certificates for Wazuh Indexer cluster
```bash
docker compose -f generate-indexer-certs.yml run --rm generator
```

---

## 🔧 Environment Configuration

Open the `.env` file and configure these **two required variables**:

---

### ✅ Option 1: Automatically detect host IP (Recommended)

Run the following command:

```bash
HOST_IP=$(hostname -I | awk '{print $1}')

sed -i "s|CORS_ORIGIN=.*|CORS_ORIGIN=\"http://localhost:8080,http://localhost:5173,http://$HOST_IP:8080\"|g" .env
sed -i "s|VITE_API_URL=.*|VITE_API_URL=http://$HOST_IP:3001/api|g" .env
```

---

### ✅ Option 2: Manual configuration

Replace `YOUR_PUBLIC_IP` with your server’s IP address:

```env
CORS_ORIGIN="http://localhost:8080,http://localhost:5173,http://YOUR_PUBLIC_IP:8080"
VITE_API_URL=http://YOUR_PUBLIC_IP:3001/api
```

---

## ▶️ Start the Stack

### Run in foreground
```bash
docker compose up
```

### Run in background
```bash
docker compose up -d
```

⏱ First launch may take about **1 minute** while Wazuh initializes indexes.

---

## 🌐 Access

Open your browser:

```
https://HOST_IP:444
```

---

## ✅ Verify Installation

Check running containers:

```bash
docker ps
```

View dashboard logs:

```bash
docker logs wazuh.dashboard --tail=50
```

---

## 🧹 Clean Up

To stop and remove everything:

```bash
docker compose down -v
```

---

## 📝 Notes

- If your host IP changes, update `.env` and restart:
  ```bash
  docker compose down
  docker compose up -d
  ```
- If the dashboard is unreachable:
  ```bash
  docker logs wazuh.dashboard
  docker logs wazuh.master
  ```

---

## ⭐ Credits

Wazuh · Docker · OpenSearch · Nginx

---

Happy SecOps! 🔥
