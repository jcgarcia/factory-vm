# Factory VM - ARM64 CI/CD Build Environment

**Production-ready ARM64 virtual machine with Jenkins, Docker, Kubernetes, and complete DevOps toolchain.**

## 🚀 Quick Start

### Prerequisites

The installer needs QEMU to run the ARM64 virtual machine:

**Ubuntu/Debian**:
```bash
sudo apt-get update
sudo apt-get install -y qemu-system-arm qemu-efi-aarch64 qemu-utils
```

**RHEL/Rocky/AlmaLinux**:
```bash
sudo dnf install -y qemu-system-aarch64 qemu-efi-aarch64 qemu-img
```

**Arch Linux**:
```bash
sudo pacman -S qemu-system-aarch64 edk2-armvirt
```

### One-Liner Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh | bash
```

This will:
- Clone the repository (or update if already exists)
- Run the automated installation

Or manually:

```bash
git clone https://github.com/jcgarcia/factory-vm.git
cd factory-vm
./setup-factory-vm.sh --auto
```

Installation takes ~15-20 minutes and sets up everything automatically:
- ✅ Alpine Linux ARM64
- ✅ Jenkins with Java 21 (admin/admin123)
- ✅ Docker, Kubernetes, Terraform, AWS CLI
- ✅ SSL/HTTPS (no warnings after setup)
- ✅ Jenkins CLI on host (jenkins-factory command)
- ✅ Foreman user for automation
- ✅ All tools auto-configured

### Access Jenkins

After installation completes, check `~/vms/factory/jenkins-credentials.txt` for your auto-generated password.

**Web UI**:
```bash
# Open in browser (will be HTTPS with no warnings)
https://factory.local

# Login credentials are in:
cat ~/vms/factory/jenkins-credentials.txt
```

**CLI** (from host machine):
```bash
# Reload your shell
source ~/.bashrc

# Test connection
jenkins-factory who-am-i

# List jobs
jenkins-factory list-jobs

# Trigger a build
jenkins-factory build my-job
```

**SSH**:
```bash
ssh factory
```

## 📋 What's Included

### Jenkins CI/CD
- **Version**: Latest LTS with Java 21 (support until 2029)
- **Architecture**: Agent-based (built-in node disabled)
- **Agent**: factory-agent-1 (2 executors, ARM64, Docker, K8s)
- **Plugins**: 25+ essential plugins pre-installed
- **SSL**: HTTPS with trusted certificates
- **User**: `foreman` (admin role, auto-generated password saved to `~/vms/factory/jenkins-credentials.txt`)

### Container & Orchestration
- Docker (latest stable)
- Kubernetes (kubectl - latest stable)
- Helm (latest stable)

### Infrastructure as Code
- Terraform (latest stable)
- Jenkins Configuration as Code (JCasC)

### Cloud Tools
- AWS CLI v2 (latest)
- jcscripts (awslogin)

> **Note**: All tool versions are automatically detected and installed during setup. The installer always fetches the latest stable versions available at installation time.
# Should output: aarch64
```

### 4. Build ARM64 Images

```bash
# From project root - build all components
./build-vm/build-arm-images.sh all

# Or build specific component
./build-vm/build-arm-images.sh backend
./build-vm/build-arm-images.sh frontend
```

## Scripts

### `setup-build-vm.sh`

Creates and configures the build VM.### Development Tools
- Git, Node.js, Python, OpenJDK
- Build tools: gcc, g++, make, cmake

## 📖 Documentation

Comprehensive guides are available:

- **[JENKINS-CONFIGURATION.md](./JENKINS-CONFIGURATION.md)** - Complete Jenkins setup guide
  - Architecture overview
  - Plugin details
  - Best practices
  - Troubleshooting
  
- **[JENKINS-CLI.md](./JENKINS-CLI.md)** - Jenkins CLI usage guide
  - Command reference
  - Examples and patterns
  - Automation recipes
  - Security best practices
  
- **[CHANGELOG.md](./CHANGELOG.md)** - Version history and changes

- **[JENKINS-CLI-IMPLEMENTATION.md](./JENKINS-CLI-IMPLEMENTATION.md)** - Technical implementation details

## 🔧 VM Management

### Start VM

```bash
~/vms/factory/start-factory.sh
```

### Stop VM

```bash
~/vms/factory/stop-factory.sh
```

### Check Status

```bash
~/vms/factory/status-factory.sh
```

### SSH Access

```bash
# Simple alias
ssh factory

# Or full command
ssh -p 2222 foreman@localhost
```

## 💻 Using Jenkins CLI

The `jenkins-factory` command provides full Jenkins CLI access from your host machine.

### Quick Examples

```bash
# Verify you're connected
jenkins-factory who-am-i

# Get Jenkins version
jenkins-factory version

# List all jobs
jenkins-factory list-jobs

# Create a job from XML
jenkins-factory create-job my-app < job-config.xml

# Trigger a build
jenkins-factory build my-app

# Trigger with parameters
jenkins-factory build my-app -p ENV=production -p VERSION=1.0.0

# Watch console output
jenkins-factory console my-app -f

# List installed plugins
jenkins-factory list-plugins

# Install a plugin
jenkins-factory install-plugin docker-workflow

# Restart Jenkins safely
jenkins-factory safe-restart

# Execute Groovy script
jenkins-factory groovy = < my-script.groovy
```

### Advanced Usage

See [JENKINS-CLI.md](./JENKINS-CLI.md) for:
- Complete command reference
- Pipeline job creation
- Credential management
- Node/agent administration
- Automation patterns
- CI/CD integration examples

## 🏗️ Architecture

### VM Configuration
- **OS**: Alpine Linux 3.19 ARM64
- **Hostname**: factory.local
- **User**: foreman (with sudo)
- **RAM**: 8GB
- **CPUs**: 6 cores
- **System Disk**: 50GB
- **Data Disk**: 200GB
- **SSH Port**: 2222 → 22
- **HTTPS Port**: 443 → 443

### Jenkins Architecture
- **Controller**: Jenkins LTS with Java 21
- **Built-in Node**: DISABLED (best practice)
- **Agents**: factory-agent-1 (2 executors)
  - Runs in Docker container
  - Docker-in-Docker enabled
  - Labels: arm64, docker, kubernetes

### Network
```
Host Machine                    Factory VM
-----------                     ----------
localhost:443 ─────────────────> Caddy :443
                                   │
                                   └──> Jenkins :8080

localhost:2222 ─────────────────> SSH :22
```

## 🔒 Security

### Users and Credentials

**Jenkins Web UI & CLI**:
- Username: `foreman`
- Password: Auto-generated during installation
- API Token: Auto-generated
- Token Location: `~/.jenkins-factory-token`
- Credentials saved to: `~/vms/factory/jenkins-credentials.txt`

**VM SSH**:
- Username: `foreman`
- Authentication: SSH key (`~/.ssh/factory-foreman`)

### SSL/HTTPS
- Caddy Local CA (trusted certificate)
- Valid until 2035
- No browser warnings after initial setup
- Certificate auto-installed in:
  - System trust store
  - Chrome/Chromium/Brave
  - Firefox (all profiles)

## 🚦 Troubleshooting

### Jenkins Not Accessible

```bash
# Check if VM is running
ssh factory 'docker ps | grep jenkins'

# Check Jenkins logs
ssh factory 'docker logs jenkins | tail -50'

# Restart Jenkins
ssh factory 'sudo rc-service jenkins restart'
```

### Jenkins CLI Issues

```bash
# Refresh API token
rm ~/.jenkins-factory-token
~/vms/factory/setup-jenkins-cli.sh

# Test connection
jenkins-factory who-am-i

# Check if Jenkins is ready
curl -I https://factory.local/
```

### Certificate Warnings

```bash
# Re-install certificates (close browsers first)
# Certificates are installed automatically during setup
# If you still see warnings, restart your browser

# Manual certificate installation if needed
# The certificate is automatically copied from the VM
```

### VM Won't Start

```bash
# Check if already running
ps aux | grep qemu | grep factory

# Check for port conflicts
sudo lsof -i :443
sudo lsof -i :2222

# Kill existing instance
pkill -9 -f qemu-system-aarch64

# Start fresh
~/vms/factory/start-factory.sh
```

### Agent Not Connecting

```bash
# Check agent status in Jenkins UI
# Navigate to: Manage Jenkins → Manage Nodes → factory-agent-1

# Restart Jenkins to reconnect agent
ssh factory 'sudo rc-service jenkins restart'

# Check Docker is running
ssh factory 'docker ps'
```

## 📊 Performance

### Build Times (Approximate)
- **Initial Installation**: 15-20 minutes
- **VM Boot**: 30-60 seconds
- **Jenkins Start**: 2-3 minutes
- **Docker Build** (simple): 1-5 minutes

### Resource Usage
- **Disk**: ~15GB after installation
- **RAM**: ~2-4GB during normal operation
- **CPU**: Varies with build activity

## 🔄 Common Workflows

### Create a Pipeline Job

```bash
# Create pipeline XML
cat > my-pipeline.xml << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>ARM64 Build Pipeline</description>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition">
    <script>
pipeline {
    agent { label 'arm64' }
    stages {
        stage('Build') {
            steps {
                sh 'docker build -t myapp:arm64 .'
            }
        }
        stage('Test') {
            steps {
                sh 'docker run myapp:arm64 npm test'
            }
        }
        stage('Push') {
            steps {
                sh 'docker push myapp:arm64'
            }
        }
    }
}
    </script>
    <sandbox>true</sandbox>
  </definition>
</flow-definition>
EOF

# Create the job
jenkins-factory create-job my-arm64-pipeline < my-pipeline.xml

# Trigger build
jenkins-factory build my-arm64-pipeline -s -v
```

### Build Docker Image on Factory

```bash
# Copy project to Factory
scp -r ./myapp factory:/home/foreman/

# SSH and build
ssh factory
cd myapp
docker build -t myapp:arm64 .
docker images

# Or build remotely
ssh factory 'cd myapp && docker build -t myapp:arm64 .'
```

### Deploy to AWS ECR

```bash
# On host, login to AWS
awslogin

# SSH forwards credentials automatically
ssh factory

# Tag and push
docker tag myapp:arm64 123456789.dkr.ecr.us-east-1.amazonaws.com/myapp:arm64
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/myapp:arm64
```

## 🎯 Why ARM64?

Building ARM64 images provides significant benefits:

- **💰 Cost Savings**: 30-40% cheaper on AWS Graviton instances
- **⚡ Performance**: Better performance per dollar
- **🌱 Energy**: Lower power consumption
- **🔮 Future**: Industry trend toward ARM architecture

## 🆘 Support

### Log Locations

**Installation Log**:
```bash
ssh factory 'cat /root/factory-install.log'
```

**Jenkins Logs**:
```bash
ssh factory 'docker logs jenkins'
ssh factory 'docker logs -f jenkins'  # Follow
```

**VM Status**:
```bash
~/vms/factory/status-factory.sh
```

### Re-run Installation

If something fails during installation:

```bash
# Complete reinstall (destroys data)
pkill -9 -f qemu-system-aarch64
rm -rf ~/vms/factory
cd factory-vm
./setup-factory-vm.sh --auto
```

### Manual Component Installation

Optional components can be installed if needed:

```bash
# Android SDK
~/vms/factory/install-android-sdk.sh

# Ansible
~/vms/factory/install-ansible.sh
```

## 📝 Files and Directories

```
factory-vm/
├── setup-factory-vm.sh           # Main installation script
├── alpine-install.exp             # Alpine automated install
├── start-factory.sh               # VM start script template
├── stop-factory.sh                # VM stop script template
├── status-factory.sh              # VM status check template
├── README.md                      # This file
├── JENKINS-CONFIGURATION.md       # Jenkins setup guide
├── JENKINS-CLI.md                 # CLI usage guide
├── JENKINS-CLI-IMPLEMENTATION.md  # Technical details
└── CHANGELOG.md                   # Version history

~/vms/factory/
├── alpine-arm64.qcow2            # System disk (50GB)
├── alpine-data.qcow2             # Data disk (200GB)
├── start-factory.sh              # Start VM script
├── stop-factory.sh               # Stop VM script
├── status-factory.sh             # Status check script
├── setup-jenkins-cli.sh          # Jenkins CLI setup
├── install-android-sdk.sh        # Optional: Android SDK
└── install-ansible.sh            # Optional: Ansible

~/.ssh/
└── factory-foreman               # SSH private key

~/.jenkins-factory-token          # Jenkins CLI API token
~/jenkins-cli-factory.jar         # Jenkins CLI executable
```

## 🔮 Roadmap

Planned improvements:

- [ ] Multiple agent support
- [ ] Backup/restore automation
- [ ] Monitoring and alerting
- [ ] HA Jenkins configuration
- [ ] Additional cloud provider support
- [ ] Auto-scaling agents

## 📜 License

MIT License - See LICENSE file for details

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly
4. Submit a pull request

## 📞 Contact

For issues or questions:
- Check documentation in this directory
- Review logs: `ssh factory 'docker logs jenkins'`
- Consult [JENKINS-CLI.md](./JENKINS-CLI.md) for CLI issues
- See [JENKINS-CONFIGURATION.md](./JENKINS-CONFIGURATION.md) for setup questions

---

**Factory VM** - Professional ARM64 CI/CD environment for modern DevOps workflows.

Version 1.1.0 - Last updated: 2025-11-17

```

## Building Images

### Build Process Flow

1. **Sync project** to VM (excludes node_modules, .git, etc.)
2. **Build images** inside VM (native ARM64)
3. **Save images** to compressed tar files
4. **Transfer** to host machine
5. **Load** into host Docker (optional)
6. **Tag and push** to ECR

### Build Workflow

```bash
# 1. Build ARM64 images
./build-vm/build-arm-images.sh all

# 2. Tag for ECR (get account ID from deployment.conf)
source scripts/config/deployment.conf
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION:-us-east-1}.amazonaws.com"

docker tag fintech-backend:latest-arm64 ${ECR_REGISTRY}/fintech-backend:latest-arm64
docker tag fintech-frontend:latest-arm64 ${ECR_REGISTRY}/fintech-frontend:latest-arm64

# 3. Authenticate to ECR
aws ecr get-login-password --region ${AWS_REGION:-us-east-1} | \
    docker login --username AWS --password-stdin ${ECR_REGISTRY}

# 4. Push images
docker push ${ECR_REGISTRY}/fintech-backend:latest-arm64
docker push ${ECR_REGISTRY}/fintech-frontend:latest-arm64

# 5. Create multi-arch manifests (optional - for supporting both x86 and ARM)
docker manifest create ${ECR_REGISTRY}/fintech-backend:latest \
    ${ECR_REGISTRY}/fintech-backend:latest-amd64 \
    ${ECR_REGISTRY}/fintech-backend:latest-arm64

docker manifest push ${ECR_REGISTRY}/fintech-backend:latest
```

## Integration with Deployment

### Update deployment scripts to use ARM64 images

The `deploy-application.sh` script should be updated to:

1. Check if ARM64 images are available
2. Tag for multi-architecture support
3. Deploy to ARM64 node groups in EKS

### EKS Node Groups

Create ARM64 node groups in your EKS cluster:

```bash
# In terraform/eks/main.tf
resource "aws_eks_node_group" "arm64" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "fintech-arm64"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  
  instance_types = ["t4g.medium"]  # Graviton instances
  ami_type       = "AL2_ARM_64"
  
  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 1
  }
}
```

### Kubernetes Deployments

Update your Kubernetes deployments to use ARM64 images:

```yaml
# Example: backend-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fintech-backend
spec:
  template:
    spec:
      # Node selector for ARM64 nodes
      nodeSelector:
        kubernetes.io/arch: arm64
      containers:
      - name: backend
        image: ${ECR_REGISTRY}/fintech-backend:latest-arm64
        # ... rest of config
```

## Troubleshooting

### VM won't start

**Check QEMU installation:**
```bash
qemu-system-aarch64 --version
```

**Install on Ubuntu/Debian:**
```bash
sudo apt-get install qemu-system-arm qemu-efi-aarch64
```

**Install on macOS:**
```bash
brew install qemu
```

### Slow performance

**Enable KVM acceleration:**
```bash
# Check if KVM is available
ls -la /dev/kvm

# Add user to kvm group
sudo usermod -aG kvm $USER

# Logout and login again
```

### Cannot connect via SSH

**Check VM is running:**
```bash
pgrep -f qemu-system-aarch64
```

**Check SSH port:**
```bash
netstat -ln | grep 2222
```

**Check SSH config:**
```bash
cat ~/.ssh/config | grep -A5 alpine-arm
```

### Docker not working in VM

**Install Docker:**
```bash
ssh alpine-arm
sudo apk add docker docker-compose
sudo rc-update add docker boot
sudo service docker start
sudo addgroup alpine docker
```

**Logout and login again:**
```bash
exit
ssh alpine-arm
docker ps  # Should work now
```

### Build fails with "no space left on device"

**Expand data disk:**
```bash
# On host
qemu-img resize ~/vms/alpine-data.qcow2 +20G

# Inside VM
ssh alpine-arm
sudo growpart /dev/vdb 1
sudo resize2fs /dev/vdb1
df -h  # Check new size
```

**Clean Docker cache:**
```bash
ssh alpine-arm
docker system prune -af
docker volume prune -f
```

### rsync transfer fails

**Install rsync on host:**
```bash
# Ubuntu/Debian
sudo apt-get install rsync

# macOS
brew install rsync
```

**Check SSH access:**
```bash
ssh alpine-arm "echo OK"
```

## Performance Optimization

### VM Resources

Edit `~/vms/start-alpine-vm.sh` to adjust resources:

```bash
VM_MEMORY="4G"    # Increase for larger builds
VM_CPUS="4"       # Use more CPU cores
```

### Build Cache

Keep the data disk to preserve Docker build cache:

```bash
# Never delete alpine-data.qcow2
# It contains your Docker build cache
```

### Parallel Builds

Build components in parallel (if you have resources):

```bash
# Terminal 1
./build-vm/build-arm-images.sh backend &

# Terminal 2
./build-vm/build-arm-images.sh frontend &

# Wait for both
wait
```

## Maintenance

### Update Alpine packages

```bash
ssh alpine-arm
sudo apk update
sudo apk upgrade
```

### Update Docker

```bash
ssh alpine-arm
sudo apk upgrade docker docker-compose
sudo service docker restart
```

### Backup VM

```bash
# Backup system disk
cp ~/vms/alpine-arm64.qcow2 ~/vms/backups/alpine-arm64-$(date +%Y%m%d).qcow2

# Backup data disk
cp ~/vms/alpine-data.qcow2 ~/vms/backups/alpine-data-$(date +%Y%m%d).qcow2
```

### Reset VM

```bash
# Recreate from scratch
./build-vm/setup-build-vm.sh --recreate

# Then reinstall Alpine (see Quick Start above)
```

## Cost Comparison

### x86_64 (current)

- EKS Node Group: 2x t3.medium
- Cost: ~$60/month per instance = $120/month

### ARM64 (Graviton)

- EKS Node Group: 2x t4g.medium
- Cost: ~$35/month per instance = $70/month
- **Savings: $50/month (42%)**

### Total Infrastructure Savings

Current: $275/month
With ARM64: ~$225/month
**Annual savings: ~$600/year**

## Additional Resources

- [Alpine Linux Documentation](https://docs.alpinelinux.org/)
- [QEMU Documentation](https://www.qemu.org/docs/master/)
- [Docker Multi-platform builds](https://docs.docker.com/build/building/multi-platform/)
- [AWS Graviton](https://aws.amazon.com/ec2/graviton/)
- [EKS ARM64 support](https://docs.aws.amazon.com/eks/latest/userguide/arm-support.html)

## Support

Issues? Questions?

1. Check this README
2. Check `~/vms/docs/README.md`
3. Check VM health: `./build-vm/check-build-vm.sh`
4. Check VM logs: `cd ~/vms && ./start-alpine-vm.sh` (look for errors)
5. Open an issue in the project repository
