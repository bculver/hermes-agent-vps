#!/usr/bin/env bash

# ==============================================================================
# SECURE HERMES AGENT & OLLAMA ENVIROMENT AUTO-DEPLOYMENT FOR UBUNTU 
# ==============================================================================
# Focuses: Hardening, Dedicated Users, Core Isolation, 110GB VRAM Acceleration.
# Run as: sudo ./deploy_hermes.sh
# ==============================================================================

set -euo pipefail

# --- Configuration Variables ---
ADMIN_USER="adminuser"                     # Your personal sudo administration account
SANDBOX_USER="hermesuser"                  # The completely restricted sandboxed user
SANDBOX_UID="2026"                         # Explicit UID/GID mapping for runtime isolation
SUBNET_RANGE="172.28.0.0/16"               # Custom internal Docker bridge subnet
PROJECT_DIR="/home/${SANDBOX_USER}/hermes-sandbox"

# --- Formatting Helpers ---
INFO='\033[0;34m[INFO]\033[0m'
SUCCESS='\033[0;32m[SUCCESS]\033[0m'
WARN='\033[0;33m[WARN]\033[0m'

echo -e "${INFO} Starting deployment process on Ubuntu..."

# ==============================================================================
# PART 1: SERVER HARDENING & BASE SECURITY
# ==============================================================================

echo -e "${INFO} Step 1: Upgrading operating system packages..."
apt-get update && apt-get upgrade -y

echo -e "${INFO} Step 2: Installing core dependencies and utilities..."
PACKAGES="ufw curl wget git ca-certificates gnupg fail2ban htop docker.io docker-compose-v2"
apt-get install -y $PACKAGES

echo -e "${INFO} Step 3: Enabling unattended security updates..."
apt-get install -y unattended-upgrades
echo -e "${WARN} Launching interactive configuration for auto-upgrades. Please select 'Yes'."
dpkg-reconfigure --priority=low unattended-upgrades

echo -e "${INFO} Step 4: Creating non-root admin sudo user (${ADMIN_USER})..."
if id "$ADMIN_USER" &>/dev/null; then
    echo -e "${WARN} User ${ADMIN_USER} already exists. Skipping creation."
else
    # Create the user and prompt for password interactively
    adduser --gecos "" "${ADMIN_USER}"
    usermod -aG sudo "${ADMIN_USER}"
fi

echo -e "${INFO} Step 5: Configuring Uncomplicated Firewall (UFW)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw --force enable

echo -e "${INFO} Step 6: Hardening SSH Daemon configuration..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh

# ==============================================================================
# PART 2: CONTAINER RUNTIME ENGINEERING
# ==============================================================================

echo -e "${INFO} Step 7: Configuring NVIDIA Container Toolkit repository..."
curl -fsSL https://github.io | sudo gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://github.io | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/lists/nvidia-container-toolkit.list

echo -e "${INFO} Step 8: Installing NVIDIA Container Toolkit..."
apt-get update
apt-get install -y nvidia-container-toolkit

echo -e "${INFO} Step 9: Registering toolkit runtime and resetting Docker..."
nvidia-container-toolkit runtimes configure --runtime=docker
systemctl restart docker

# ==============================================================================
# PART 3: ISOLATED SANDBOX & DEPLOYMENT EXECUTION
# ==============================================================================

echo -e "${INFO} Step 10: Establishing restricted sandbox system account..."
if id "$SANDBOX_USER" &>/dev/null; then
    echo -e "${WARN} User ${SANDBOX_USER} already exists. Skipping user creation."
else
    groupadd -g "$SANDBOX_UID" "$SANDBOX_USER"
    useradd -u "$SANDBOX_UID" -g "$SANDBOX_USER" -m -s /bin/bash "$SANDBOX_USER"
    usermod -aG docker "$SANDBOX_USER"
fi

echo -e "${INFO} Step 11: Crafting filesystem context workspace..."
mkdir -p "${PROJECT_DIR}/workspace"
chown -R "${SANDBOX_UID}:${SANDBOX_UID}" "${PROJECT_DIR}"

echo -e "${INFO} Step 12: Generating Docker Compose layout..."
cat << 'EOF' > "${PROJECT_DIR}/docker-compose.yml"
version: '3.8'

services:
  ollama:
    image: ollama/ollama:latest
    container_name: hermes-ollama-backend
    volumes:
      - ollama_storage:/root/.ollama
    ports:
      - "11434:11434"
    networks:
      - hermes-isolated-net
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    restart: unless-stopped

  hermes-agent:
    image: nousresearch/hermes-agent:latest
    container_name: hermes-sandbox-env
    user: "2026:2026"
    depends_on:
      - ollama
    networks:
      - hermes-isolated-net
    environment:
      - OLLAMA_HOST=http://ollama:11434
      - AGENT_MODEL=qwen2.5:72b
      - HOME=/workspace
    volumes:
      - ./workspace:/workspace
    stdin_open: true 
    tty: true
    restart: unless-stopped

networks:
  hermes-isolated-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16

volumes:
  ollama_storage:
EOF

chown "${SANDBOX_UID}:${SANDBOX_UID}" "${PROJECT_DIR}/docker-compose.yml"

echo -e "${INFO} Step 13: Enforcing Network Isolation Perimeter (LAN Traffic Interception)..."
# Block container subnet from accessing standard local networking topologies
iptables -I FORWARD -s "$SUBNET_RANGE" -d 192.168.0.0/16 -j REJECT
iptables -I FORWARD -s "$SUBNET_RANGE" -d 10.0.0.0/8 -j REJECT
iptables -I FORWARD -s "$SUBNET_RANGE" -d 172.16.0.0/12 -j REJECT

# Make firewall rules persistent across system reboots
echo iptables-persistent iptables-persistent/tosaveboolean boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/tosavev6boolean boolean true | debconf-set-selections
apt-get install -y iptables-persistent
netfilter-persistent save

echo -e "${INFO} Step 14: Booting the Docker containers via unprivileged user domain..."
sudo -u "$SANDBOX_USER" bash -c "cd ${PROJECT_DIR} && docker compose up -d"

echo -e "${INFO} Step 15: Fetching high-capacity 72B parameter model weights..."
docker exec -it hermes-ollama-backend ollama run qwen2.5:72b /exit

echo -e "${INFO} Step 16: Launching interactive configuration wizard for Hermes CLI..."
echo -e "${WARN} Please map to Provider: 'Ollama local', Endpoint: 'http://ollama:11434', Model: 'qwen2.5:72b'"
docker exec -it hermes-sandbox-env hermes config setup

echo -e "${INFO} Step 17: Adjusting Context Window ceilings to 64K..."
docker exec -it hermes-sandbox-env hermes config set model.context_length 65536

# ==============================================================================
# SECURITY VERIFICATION RUNTIME CHECK
# ==============================================================================
echo -e "\n=== RUNTIME SECURITY VERIFICATION ==="
echo -e "${INFO} Testing Network Isolation..."

# Test if local network routing fails as expected
if docker exec -it hermes-sandbox-env ping -c 1 -W 2 192.168.1.1 &>/dev/null; then
    echo -e "[\033[0;31mFAIL\033[0m] Container can reach your local LAN! Check your iptables config."
else
    echo -e "[${SUCCESS}] Sandbox network isolation verified. Container cannot map local LAN targets."
fi

# Test if public web fetching still operates
if docker exec -it hermes-sandbox-env ping -c 1 -W 2 google.com &>/dev/null; then
    echo -e "[${SUCCESS}] External WAN connection verified. Container can safely download operational dependencies."
else
    echo -e "[\033[0;31mFAIL\033[0m] Container has no Internet access. DNS or outbound routing is broken."
fi

echo -e "\n=============================================================================="
echo -e "${SUCCESS} DEPLOYMENT MASTER RUN COMPLETE!"
echo -e "=============================================================================="
echo -e "To access your secure Hermes TUI dashboard, run the following command:"
echo -e "\033[1;36mdocker exec -it hermes-sandbox-env hermes --tui\033[0m"
echo -e "=============================================================================="
