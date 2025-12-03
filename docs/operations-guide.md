# Factory VM Operations Guide

Complete guide for operating Factory VM - your ARM64 build environment with Jenkins CI/CD.

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Installation](#installation)
3. [VM Management](#vm-management)
4. [SSH Access](#ssh-access)
5. [Jenkins Operations](#jenkins-operations)
6. [Docker Agent Builds](#docker-agent-builds)
7. [Credentials](#credentials)
8. [Troubleshooting](#troubleshooting)
9. [Maintenance](#maintenance)

---

## Quick Reference

```bash
# VM Control
factorystart                    # Start the VM
factorystop                     # Stop the VM
factorystatus                   # Check VM status
factorysecrets                  # Show credentials

# SSH Access
ssh factory                     # Connect to VM as foreman

# Jenkins CLI
jenkins-factory version         # Jenkins version
jenkins-factory who-am-i        # Current user
jenkins-factory list-jobs       # List all jobs
jenkins-factory build <job> -s  # Build and wait for result

# Web UI
https://factory.local           # Jenkins web interface
```

---

## Installation

### Fresh Install

```bash
curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh | bash
```

**Installation time:** ~13-17 minutes (depending on cache state)

### Clean Reinstall (preserves cache)

```bash
# Stop VM and clean up (keeps cached downloads)
bash ~/GitProjects/FactoryVM/tools/clean-for-test.sh

# Wait 60 seconds if you just published changes
sleep 60

# Reinstall
curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh | bash
```

### Full Clean Install (no cache)

```bash
# Remove everything including cache
rm -rf ~/vms/factory ~/factory-vm ~/.factory-vm-data-backup.qcow2

# Reinstall from scratch
curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh | bash
```

---

## VM Management

### Starting the VM

```bash
factorystart
# Or: ~/vms/factory/start-factory.sh
```

**Output:**
```
Starting Factory VM...
✓ Factory VM started
  PID: 12345
  SSH: ssh factory (port 2222)
  Jenkins: https://factory.local (port 443)
```

### Stopping the VM

```bash
factorystop
# Or: ~/vms/factory/stop-factory.sh
```

### Checking Status

```bash
factorystatus
# Or: ~/vms/factory/status-factory.sh
```

**Output:**
```
Factory VM Status
=================

✓ VM is running
  PID: 12345

SSH (port 2222): ✓ accessible
HTTPS (port 443): ✓ forwarded
  Jenkins: responding

Services:
  SSH:     ssh factory
  Jenkins: https://factory.local
```

### Restarting the VM

```bash
factorystop && sleep 5 && factorystart
```

---

## SSH Access

### Connect to VM

```bash
ssh factory
```

This connects as `foreman` user with sudo privileges.

### Run Commands Remotely

```bash
# Single command
ssh factory "hostname"

# Multiple commands
ssh factory "uname -a && df -h"

# Interactive sudo
ssh factory "sudo docker ps"
```

### File Transfer

```bash
# Copy file to VM
scp myfile.txt factory:~/

# Copy file from VM
scp factory:~/somefile.txt ./

# Copy directory
scp -r myfolder factory:~/
```

### SSH Config (auto-created)

Location: `~/.ssh/config`

```
Host factory
    HostName localhost
    Port 2222
    User foreman
    IdentityFile ~/.ssh/factory-foreman
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

---

## Jenkins Operations

### Web Interface

**URL:** https://factory.local

**Login:** 
- User: `foreman`
- Password: Run `factorysecrets` to see

### Jenkins CLI

The `jenkins-factory` command provides CLI access:

```bash
# Basic info
jenkins-factory version         # Show Jenkins version
jenkins-factory who-am-i        # Show authenticated user

# Job management
jenkins-factory list-jobs                    # List all jobs
jenkins-factory get-job <name>               # Get job XML config
jenkins-factory create-job <name> < job.xml  # Create job from XML
jenkins-factory delete-job <name>            # Delete a job

# Building
jenkins-factory build <job>                  # Trigger build
jenkins-factory build <job> -s               # Build and wait
jenkins-factory build <job> -s -v            # Build, wait, show output

# Build info
jenkins-factory console <job> <build>        # Show build output
jenkins-factory set-build-result <result>    # Set build result

# Plugins
jenkins-factory list-plugins                 # List installed plugins
jenkins-factory install-plugin <name>        # Install plugin

# System
jenkins-factory restart                      # Restart Jenkins
jenkins-factory safe-restart                 # Restart when idle
jenkins-factory quiet-down                   # Prepare for shutdown
jenkins-factory cancel-quiet-down            # Cancel quiet-down
```

### Create a Freestyle Job

```bash
cat << 'EOF' | jenkins-factory create-job my-test-job
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>My test job</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <scm class="hudson.scm.NullSCM"/>
  <assignedNode>docker-agent</assignedNode>
  <canRoam>false</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>echo "Hello World!"
hostname
date</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
EOF
```

### Run a Build

```bash
# Fire and forget
jenkins-factory build my-test-job

# Wait for completion
jenkins-factory build my-test-job -s

# Wait and show output
jenkins-factory build my-test-job -s -v
```

### View Build Output

```bash
# View specific build
jenkins-factory console my-test-job 1

# View last build (via API)
curl -s -u "foreman:$(cat ~/.jenkins-factory-token)" \
  "http://localhost:8080/job/my-test-job/lastBuild/consoleText"
```

---

## Docker Agent Builds

### How It Works

1. Job requests agent with label `docker-agent`
2. Jenkins provisions Docker container from `jenkins/inbound-agent`
3. Container connects back to Jenkins via JNLP
4. Build runs inside container
5. Container is automatically removed after build

### Agent Labels

Available labels: `docker-agent`, `linux`, `arm64`

Use in job config:
- Freestyle: "Restrict where this project can be run" → `docker-agent`
- Pipeline: `agent { label 'docker-agent' }`

### Pipeline Example

```groovy
pipeline {
    agent {
        label 'docker-agent'
    }
    stages {
        stage('Build') {
            steps {
                sh 'echo "Running on Docker agent"'
                sh 'hostname'
                sh 'uname -a'
            }
        }
        stage('Test') {
            steps {
                sh 'echo "Running tests..."'
            }
        }
    }
}
```

### Create Pipeline Job

```bash
cat << 'EOF' | jenkins-factory create-job my-pipeline
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition>
  <description>My Pipeline Job</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition">
    <script>
pipeline {
    agent { label 'docker-agent' }
    stages {
        stage('Hello') {
            steps {
                sh 'echo Hello from Pipeline!'
                sh 'hostname'
            }
        }
    }
}
    </script>
    <sandbox>true</sandbox>
  </definition>
</flow-definition>
EOF

# Run it
jenkins-factory build my-pipeline -s -v
```

### View Running Agents

**Via UI:** Manage Jenkins → Nodes

**Via CLI:**
```bash
curl -s -u "foreman:$(cat ~/.jenkins-factory-token)" \
  "http://localhost:8080/computer/api/json?pretty=true" | jq '.computer[].displayName'
```

---

## Credentials

### View All Credentials

```bash
factorysecrets
```

**Output:**
```
Factory VM Credentials
Generated: [timestamp]

VM Access:
  SSH: ssh factory
  User: foreman
  Password: [generated]

Jenkins:
  URL: https://factory.local
  User: foreman
  Password: [generated]
```

### Credential Files

| File | Contents |
|------|----------|
| `~/vms/factory/credentials.txt` | All credentials |
| `~/.jenkins-factory-token` | Jenkins API token |
| `~/.ssh/factory-foreman` | SSH private key |
| `~/.ssh/factory-foreman.pub` | SSH public key |

### Jenkins API Token

The CLI uses an API token for authentication:

```bash
cat ~/.jenkins-factory-token
```

---

## Troubleshooting

### VM Won't Start

```bash
# Check if already running
ps aux | grep qemu | grep factory

# Check for port conflicts
ss -tlnp | grep -E '2222|443'

# Force stop and restart
factorystop
sleep 5
factorystart
```

### SSH Connection Refused

```bash
# Check if VM is running
factorystatus

# Check SSH port
nc -zv localhost 2222

# Remove old host key
ssh-keygen -R "[localhost]:2222"

# Try connecting with verbose output
ssh -v factory
```

### Jenkins Not Responding

```bash
# Check container status
ssh factory "sudo docker ps | grep jenkins"

# View Jenkins logs
ssh factory "sudo docker logs jenkins --tail 50"

# Restart Jenkins container
ssh factory "sudo docker restart jenkins"
```

### Docker Agent Won't Start

```bash
# Check Docker socket permissions
ssh factory "ls -la /var/run/docker.sock"
# Should be: srw-rw-rw-

# Fix if needed
ssh factory "sudo chmod 666 /var/run/docker.sock"

# Check Jenkins can access Docker
ssh factory "sudo docker exec jenkins curl -s --unix-socket /var/run/docker.sock http://localhost/version"

# Check Docker Cloud configuration
# Go to: Manage Jenkins → Clouds → docker → Configure
```

### Build Stuck "Waiting for executor"

```bash
# Check if Docker Cloud exists
# Manage Jenkins → Clouds → should show "docker"

# Check agent image is available
ssh factory "sudo docker images | grep inbound-agent"

# Pre-pull the image
ssh factory "sudo docker pull jenkins/inbound-agent:latest"
```

### Certificate Warnings in Browser

```bash
# Reinstall certificates
ssh factory "cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt" > /tmp/caddy-root.crt
sudo cp /tmp/caddy-root.crt /usr/local/share/ca-certificates/caddy-factory.crt
sudo update-ca-certificates

# For browsers, restart them after certificate installation
```

---

## Maintenance

### Update Jenkins Plugins

**Via UI:** Manage Jenkins → Plugins → Updates

**Via CLI:**
```bash
jenkins-factory install-plugin <plugin-name>
jenkins-factory safe-restart
```

### Backup Jenkins Data

```bash
# Backup jobs and config
ssh factory "sudo tar czf /tmp/jenkins-backup.tar.gz -C /opt/jenkins jobs config.xml"
scp factory:/tmp/jenkins-backup.tar.gz ./jenkins-backup-$(date +%Y%m%d).tar.gz
```

### Clean Docker Resources

```bash
# Remove unused containers
ssh factory "sudo docker container prune -f"

# Remove unused images
ssh factory "sudo docker image prune -f"

# Full cleanup
ssh factory "sudo docker system prune -f"
```

### View Disk Usage

```bash
ssh factory "df -h"
ssh factory "sudo du -sh /opt/jenkins"
ssh factory "sudo docker system df"
```

### Restart Services

```bash
# Restart Jenkins
ssh factory "sudo docker restart jenkins"

# Restart Caddy
ssh factory "sudo rc-service caddy restart"

# Restart Docker
ssh factory "sudo rc-service docker restart"
```

---

## Installed Tools

Factory VM comes with these tools pre-installed:

| Tool | Version | Purpose |
|------|---------|---------|
| Docker | 25.x | Container runtime |
| Jenkins | 2.528.x | CI/CD server |
| kubectl | 1.34.x | Kubernetes CLI |
| Helm | 4.x | Kubernetes package manager |
| Terraform | 1.14.x | Infrastructure as code |
| AWS CLI | 2.x | AWS management |
| Git | 2.43.x | Version control |
| Node.js | 20.x | JavaScript runtime |
| Python | 3.11.x | Python runtime |
| Java | 21 | JDK for builds |

---

## Architecture Notes

- **Host:** x86_64 Linux
- **VM:** ARM64 Alpine Linux (via QEMU TCG emulation)
- **Performance:** ~10-20x slower than native ARM64 due to emulation
- **Jenkins:** Runs in Docker container inside the VM
- **Build agents:** Docker containers inside the VM (nested)
- **Networking:** Port forwarding (2222→SSH, 443→HTTPS)
