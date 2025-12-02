🛡️ Wazuh-BlueStack Deployment

Deployment of a comprehensive security monitoring environment.
This project integrates Wazuh SIEM with a Nginx WAF (Web Application Firewall) to protect and monitor vulnerable target applications (DVWA and Juice Shop). Ideal for Red Team/Blue Team simulations and security analysis.

🏗️ System Architecture

The environment is fully containerized using Docker and segmented into two internal networks:

🔴 capstone-dmz-network: Hosts the vulnerable apps and the WAF.

🔵 capstone-siem-network: Hosts the Wazuh cluster components.

🧩 Core Components

🦅 Wazuh Cluster:

Manager (wazuh.master): The central brain and analysis engine.

Indexers (wazuh1.indexer, wazuh2.indexer): High-availability data storage and indexing.

Dashboard (wazuh.dashboard): Visualization Web UI (Port 444).

🛡️ WAF & Proxy:

Nginx-Love: Custom Nginx WAF submodule acting as a Reverse Proxy & Shield.

🎯 Targets (Vulnerable Apps):

🥤 Juice Shop: OWASP Juice Shop (Modern web app vulnerabilities).

🐞 DVWA: Damn Vulnerable Web App (Classic PHP vulnerabilities).

🕵️ Agent:

Wazuh Agent: Deployed deep in the DMZ to monitor applications and forward logs.

🚀 Deployment Guide

1. Prerequisites

🐳 Docker & Docker Compose

🔧 Git

2. Clone and Initialize

Clone the repository (specifically the wazuh-stack branch) and initialize the WAF submodule.

# Clone the specific branch
git clone -b wazuh-stack [https://github.com/CyberSecN00bers/Capstone_Blue_Stack.git](https://github.com/CyberSecN00bers/Capstone_Blue_Stack.git)

# Enter directory
cd Capstone_Blue_Stack

# Initialize the nginx-love submodule
git submodule update --init --recursive


3. Environment Configuration

Set up your secrets and configuration by copying the example file.

cp .env.example .env


[!IMPORTANT]
You can customize passwords and ports in .env. However, if you change INDEXER_PASSWORD, you must also update the hash in config/wazuh_indexer/internal_users.yml (see Configuration section).

4. 🔐 Generate SSL Certificates

The Wazuh cluster requires strict SSL communication. Run the auto-generator:

docker compose -f generate-indexer-certs.yml run --rm generator


✅ This will populate ./config/wazuh_indexer_ssl_certs with the required .pem and .key files.

5. 🔥 Start the Stack

Ignition! Deploy the containers.

Foreground (Debug mode):

docker compose up


Background (Production mode):

docker compose up -d


[!NOTE]
Patience Required: The environment takes about 1 minute to fully initialize. The Wazuh Indexer needs time to generate indexes and patterns on the very first run.

6. 💻 Configure Host Machine

To access the apps via friendly domain names, update your local hosts file.

Windows: C:\Windows\System32\drivers\etc\hosts

Linux/Mac: /etc/hosts

Add the following lines (replace 172.16.254.100 with your Docker Host IP, or 127.0.0.1 if running locally):

172.16.254.100 juiceshop.local
172.16.254.100 dvwa.local


⚙️ Configuration Details

👤 Internal Users & Passwords

Wazuh and OpenSearch users are managed in: config/wazuh_indexer/internal_users.yml

🔒 Hashing: Passwords here are Bcrypt hashed.

🔄 Syncing: The INDEXER_PASSWORD in your .env is the plain text version. The internal_users.yml holds the hash.

📝 Updating: If you change the password in .env, you must generate a new Bcrypt hash (cost/rounds ~10) and update the hash: field for the admin user in the YAML file.

📜 SSL Certificates

Certificates are located in: ./config/wazuh_indexer_ssl_certs
If providing your own, ensure filenames match exactly:

root-ca.pem, root-ca.key

wazuh.master.pem, wazuh.master-key.pem

wazuh1.indexer.pem, wazuh1.indexer-key.pem

wazuh.dashboard.pem, wazuh.dashboard-key.pem

admin.pem, admin-key.pem

🌐 Access Information

Service

URL / Port

Default Credentials

🦅 Wazuh Dashboard

https://<IP>:444

User: admin



Pass: SecretPassword (or see .env)

🛡️ Nginx WAF Admin

http://localhost:8080

Defined in app

🔌 Backend API

http://localhost:3001

-

🥤 Juice Shop

http://juiceshop.local

(Register new user)

🐞 DVWA

http://dvwa.local

User: admin



Pass: password

🛠️ Troubleshooting

❌ Services died? Check logs: docker compose logs -f <service_name>

🐢 Backend slow start? The backend waits for Postgres. Ensure postgres-nginx-love is healthy.

🚫 Permission Denied? If you see errors regarding ./logs, ensure your host directory has write permissions. The included entrypoint scripts usually handle this automatically.
