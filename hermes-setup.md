# Secure Hermes Agent Setup with Ollama (Ubuntu Sandbox)

This comprehensive guide walks you through initially hardening your Ubuntu server, creating a non-root sudo user with cryptographic SSH keys, and deploying the **Nous Research Hermes AI Agent** locally with **Ollama**. It leverages **96 GB of VRAM**, secures the agent inside a **Docker sandbox**, runs under a **restricted non-root process**, and completely **isolates the container from your local home network (LAN)**.

---

## Part 1: Server Hardening & Base Security

### 1. Updating the OS
Keep your system secure by updating the package lists and upgrading all installed packages to their latest versions.
```bash
sudo apt update && sudo apt upgrade -y
```

### 2. Installing Recommended Packages
Install essential utilities for security, networking, and system monitoring.
```bash
PACKAGES="ufw curl wget git ca-certificates gnupg fail2ban htop unattended-upgrades vim gpg perl"
sudo apt install -y $PACKAGES
```

### 3. Enabling Automatic Security Updates
Configure the system to automatically install security updates to protect against newly discovered vulnerabilities.
```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

### 4. Creating a Non-Root Admin Sudo User
Running commands as the default `root` user is unsafe. Create a dedicated system administration account for yourself.
```bash
# 1. Create your personal admin user (replace 'adminuser' with your desired username)
sudo adduser adminuser

# 2. Grant administrative privileges via the sudo group
sudo usermod -aG sudo adminuser
```

### 5. Generating and Installing SSH Cryptographic Keys
Cryptographic keys provide vastly superior security over standard text passwords. 

#### On Your Local Desktop Machine (Your Client PC):
Generate a secure Ed25519 key pair and copy the public signature to your Ubuntu server:
```bash
# 1. Generate the key pair
ssh-keygen -t ed25519 -b 4096 -C "your_email@example.com"

# 2. Push the public key signature to your new admin user on the server
ssh-copy-id adminuser@your_server_ip
```

### 6. Configuring UFW Firewall
Set up an uncomplicated firewall to block unauthorized network traffic while maintaining access to essential services.
```bash
# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow OpenSSH traffic
sudo ufw allow OpenSSH

# Enable the firewall without prompting for confirmation
sudo ufw --force enable
```

### 7. Configuring and Securing SSH
Hardening SSH access is critical to preventing unauthorized remote control of your server.

#### Backup Current SSHD Configuration
Always create a backup copy of the working configuration before making modifications.
```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
```

#### Apply Security Configurations
Update your SSH daemon configuration file with the following security standards:
*   `PermitRootLogin prohibit-password`: Disallows logging in as `root` using a password.
*   `PasswordAuthentication yes`: Maintained password allowance for non-root users (can be flipped to `no` later once keys are tested).
*   `PubkeyAuthentication yes`: Explicitly enables the use of secure SSH keys.

Run the following commands to securely update the file:
```bash
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
```

#### Restart SSH Service
Apply the new configuration rules by restarting the SSH service.
```bash
sudo systemctl restart ssh
```

---

## Part 2: Installing the Container Environment

### 8. Install the NVIDIA Container Toolkit
Bridge your host GPU drivers to Docker so your containers can utilize your VRAM pool. Run this block from your new admin account:

#### Install AMD ROCm Drivers and Set Permissions

Install the AMD repository installer, compute stacks (OpenCL, HIP, [ROCm](https://rocm.docs.amd.com/en/latest/install/rocm.html?fam=ryzen&w=compute&gpu=amd-ryzen-ai-max-395&os=ubuntu&ubuntu-ver=26.04.1&i=pkgman&gfx=gfx1151) ), and assign necessary video render permissions. Detailed installation steps and package repositories can be accessed via {Link: AMD Radeon Software https://radeon.com}.

```bash

# Download and install GPG key
sudo mkdir --parents --mode=0755 /etc/apt/keyrings

# ROCm release signing key
wget https://stable.repo.amd.com/rocm/gpg/packages.gpg -O - | \
    gpg --dearmor | sudo tee /etc/apt/keyrings/amdrocm.gpg > /dev/null

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amd-container-toolkit/apt/ $(. /etc/os-release && echo $VERSION_CODENAME) main" | sudo tee /etc/apt/sources.list.d/amd-container-toolkit.list

sudo tee /etc/apt/sources.list.d/amdrocm-stable.sources << EOF
X-Repo-Id: amdrocm-stable
Types: deb
URIs: https://stable.repo.amd.com/rocm/core/packages/ubuntu2604/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/amdrocm.gpg
Enabled: yes
EOF

sudo apt update

# Download and install the AMD repository installer package
sudo apt install libatomic1 libquadmath0 jq
sudo apt install amdrocm-core-sdk10.1-gfx1151
sudo apt-get update
sudo apt update

# 2. Update package lists and Install the full ROCm stack along with OpenCL and HIP runtimes
# sudo amdgpu-install --usecase=rocm,opencl,hip

# Add the current user to the necessary hardware access groups
sudo usermod -aG video $USER
sudo usermod -aG render $USER

# udev rules are a flexible, system-wide approach for managing device permissions, eliminating the need for user group management while allowing granular GPU access. To enable them and grant GPU access to all users, run the following command:
sudo tee /etc/udev/rules.d/70-amdgpu.rules << EOF
KERNEL=="kfd", GROUP="render", MODE="0666"
SUBSYSTEM=="drm", KERNEL=="renderD*", GROUP="render", MODE="0666"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

# Add ROCm to the environment PATH
echo 'export PATH=$PATH:/opt/rocm/bin' >> ~/.bashrc
source ~/.bashrc

sudo apt install amd-container-toolkit
sudo amd-ctk runtime configure

# 3. Restart the Docker daemon to apply runtime changes
sudo systemctl restart docker
```

Verify your installation
Use the following ROCm tools to verify that ROCm is correctly installed and that your AMD devices are visible to the system.

Use rocminfo to list detected AMD GPUs and confirm that the ROCm runtimes and drivers are correctly installed and loaded.

```bash
rocminfo

docker run --runtime=amd -e AMD_VISIBLE_DEVICES=all rocm/dev-ubuntu-24.04 amd-smi monitor

```

Use the AMD SMI CLI amd-smi to validate system information.

```bash
amd-smi version
```

---

## Part 3: Isolated Sandbox & Deployment

### 9. Create a Restricted Container Host User
Create a dedicated user account on your Ubuntu system that has no administrative privileges. This stops container-escape vulnerabilities from compromising your host machine.

```bash
# 1. Create a system group and user named 'hermesuser' (UID/GID 2026)
sudo groupadd -g 2026 hermesuser
sudo useradd -u 2026 -g hermesuser -m -s /bin/bash hermesuser

# 2. Add 'hermesuser' to the docker group so it can manage the containers
sudo usermod -aG docker hermesuser
```

### 10. Switch User & Build the Project Directory
Log into your newly created unprivileged account and establish your safe project environment.

```bash
# 1. Log into the restricted account
sudo su - hermesuser

# 2. Create the workspace folder (where the agent can read/write files)
mkdir -p ~/hermes-sandbox/workspace
cd ~/hermes-sandbox
```

### 11. Create the Hardened Docker Compose Stack
Create a configuration file that enforces the non-root execution policy (`user: "2026:2026"`) and moves both services into a custom network.

https://rocm.docs.amd.com/en/latest/install/docker-containers.html

# install docker for --gpus option
# sudo apt-get install docker.io


docker run -it --rm \
    --device /dev/kfd \
    --device /dev/dri \
    --security-opt seccomp=unconfined \
    <image>



1. Open a new file:
   ```bash
   nano docker-compose.yml
   ```
2. Paste the following configuration:
   ```yaml
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
   ```
3. Save and close (`Ctrl+O`, `Enter`, `Ctrl+X`).

### 12. Implement Host Firewall Rules (LAN Block)
By default, Docker will route traffic from your isolated container subnet straight to your private home network. Use `iptables` to shut this down completely. 

Exit your restricted user profile temporarily to apply these root-level rules:

```bash
# 1. Exit back to your primary admin user
exit

# 2. Reject traffic from the Hermes subnet destined for private IP spaces
sudo iptables -I FORWARD -s 172.28.0.0/16 -d 192.168.0.0/16 -j REJECT
sudo iptables -I FORWARD -s 172.28.0.0/16 -d 10.0.0.0/8 -j REJECT
sudo iptables -I FORWARD -s 172.28.0.0/16 -d 172.16.0.0/12 -j REJECT

# 3. Save rules so they survive system reboots
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save
```

### 13. Launch Your Environment
Log back into your secure environment and build the stack.

```bash
# 1. Switch back to hermesuser
sudo su - hermesuser
cd ~/hermes-sandbox

# 2. Fire up the containers
docker compose up -d
```

### 14. Cache Your Heavyweight LLM
Maximize your 110 GB VRAM pipeline by running a state-of-the-art 72B parameter model. Instruct Ollama to download and optimize it natively:

```bash
docker exec -it hermes-ollama-backend ollama run qwen2.5:72b
```
*(Once the download completes and displays a chat prompt, type `/exit` to return to your normal terminal).*

### 15. Initialize & Configure Hermes CLI
Drop into your isolated sandbox container to run the initialization scripts. Because we forced the `user: 2026:2026` parameter earlier, all created hidden files will cleanly inhabit your `./workspace` directory.

```bash
# 1. Execute onboarding wizard
docker exec -it hermes-sandbox-env hermes config setup
```
Select the following responses in the setup guide:
* **Model Provider:** `Ollama local` or `Custom Endpoint`
* **API Endpoint:** `http://ollama:11434`
* **Model Name:** `qwen2.5:72b`
* **Terminal Backend:** `local`

Next, adjust the agent's context window settings to ensure it can successfully handle complex multi-step reasoning thoughts:
```bash
docker exec -it hermes-sandbox-env hermes config set model.context_length 65536
```
