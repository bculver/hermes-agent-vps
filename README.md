# Secure Hermes Agent Setup with Ollama (Ubuntu Sandbox)

This comprehensive guide walks you through initially hardening your Ubuntu server, creating a non-root sudo user with cryptographic SSH keys, and deploying the **Nous Research Hermes AI Agent** locally with **Ollama**. It leverages **110 GB of VRAM**, secures the agent inside a **Docker sandbox**, runs under a **restricted non-root process**, and completely **isolates the container from your local home network (LAN)**.

---

## Quick Summary & Deployment Checklist

### Part 1: Server Hardening & Base Security

- Operating System Updates: Updates local software indices and applies outstanding system patches (apt update && apt upgrade).
- Essential Packages Installation: Deploys underlying dependencies for system safety, tooling, and threat protection (ufw, curl, fail2ban, etc.).
- Unattended Upgrades: Configures automatic validation and deployment of Ubuntu security repositories.
- Privileged User Provisioning: Creates an alternative administrator profile to move system maintenance workflows away from native root.
- Cryptographic Key Pairing: Generates a secure asymmetric Ed25519 key pair on a client machine and provisions it to the remote server.
- UFW Perimeter Rules: Implements global ingress denials while preserving explicit lanes for incoming remote encrypted connections.
- SSH Daemon Configuration: Modifies system variables to forbid administrative passwords while verifying public cryptographic handshakes.
- SSH Lifecycle Maintenance: Power-cycles the remote session manager to apply configuration updates safely.

### Part 2: Container Runtime Engineering

- NVIDIA Container Toolkit Hook: Pins official repository sources and installs structural drivers allowing Docker wrappers to access GPU hardware layers.
- Docker Daemon Environment Flush: Power-cycles the hypervisor layer to finalize direct system communication bridges with host hardware.

### Part 3: Isolated Sandbox & Deployment Execution

- Unprivileged Workspace Account: Deploys a distinct, resource-capped host operator (hermesuser) with custom IDs.
- Filesystem Context Workspace: Declares safe sandbox directory paths on the host layer to catch agent-generated assets.
- Container Blueprint Compilation: Drafts an orchestration layout setting up independent execution blocks, hardware passthroughs, and local storage mappings.
- Network Isolation Subnet Construction: Spins up a custom Virtual Bridge Interface to restrict container groups within a defined tracking lane.
- Host Firewall Matrix Interception: Injects kernel-level iptables constraints to intercept and discard traffic routed toward internal LAN spaces.
- Large Language Model Quantized Cache: Provisions the high-capacity model weights straight into local backend volume blocks.
- Agent Interaction Configuration: Steps through structural pipeline setup parameters to link frontend drivers to local network models.
- Context Optimization Escalation: Configures memory arrays to utilize a 64K token execution lane.
- Network Isolation Validation: Pings internal home structures and external addresses from inside the container to test firewall policies.
- Hermes UI Invocation: Opens the core sandboxed dashboard environment.


Critical Execution Requirements

1. Prerequisite: Before running this script, ensure you have already generated your SSH keys on your local client machine and successfully transferred them to your server via ssh-copy-id.
2. Interactive Prompts: Step 5 (dpkg-reconfigure) and Step 15 (hermes config setup) require interactive menu selections. The script will pause at these points for your input.

Step by Step [hermes-setup](./hermes-setup.md) instructions or run [hermes-setup.sh](./hermes-setup.sh)

---

## Verify and Run Hermes

Confirm your firewall rules are active by testing your network connectivity from inside the container:
Test Local Network Access (Should fail/timeout instantly)
```bash
docker exec -it hermes-sandbox-env ping -c 3 192.168.1.1
```
Test External WAN Access (Should pass perfectly)

```bash
docker exec -it hermes-sandbox-env ping -c 3 google.com
```
If everything works as expected, start your secure interface:
bash docker exec -it hermes-sandbox-env hermes --tui 

Drop into your isolated sandbox container to run the initialization scripts. Because we forced the user: 2026:2026 parameter earlier, all created hidden files will cleanly inhabit your ./workspace directory.


1. Execute onboarding wizard

  ```bash
  docker exec -it hermes-sandbox-env hermes config setup
  ```
  Select the following responses in the setup guide:
  - Model Provider: Ollama local or Custom Endpoint
  - API Endpoint: http://ollama:11434
  - Model Name: qwen2.5:72b
  - Terminal Backend: local
  Next, adjust the agent's context window settings to ensure it can successfully handle complex multi-step reasoning thoughts:
  bash docker exec -it hermes-sandbox-env hermes config set model.context_length 65536 

2. Verify Security Controls
  Before fully deploying the agent, you must verify that the firewall and isolation parameters are actively working. This ensures the environment is sealed tight before invoking the agent.
  
  Run Network Validation Tests
  
  Execute these diagnostic network requests directly inside the running container namespace:
  1. Test Local Network Isolation (Expected: Fail or Timeout instantly)
  This confirms the agent cannot touch or probe other devices on your home router
  ```bash
  docker exec -it hermes-sandbox-env ping -c 3 192.168.1.1
  ```
  2. Test External Internet Access (Expected: Pass cleanly with 0% packet loss)
  This confirms the agent can still hit WAN to pull package dependencies or write data
  ```bash
  docker exec -it hermes-sandbox-env ping -c 3 google.com
  ```

3. Launch the Agent

  If both tests return their expected behaviors, you are cleared to safely invoke the agent workspace via its Text User Interface (TUI):
  ```bash
  bash docker exec -it hermes-sandbox-env hermes --tui 
  ```
