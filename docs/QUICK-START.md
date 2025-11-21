# ARM64 Build VM - Quick Reference

## What Is This?

A virtual machine (VM) running on your computer that builds ARM64 Docker images, reducing AWS costs by 30-40%.

## Why ARM64?

**AWS Graviton instances are cheaper:**
- t4g.medium (ARM): $35/month
- t3.medium (x86): $60/month
- **Savings: $25/month per instance**

## Quick Commands

### Setup (One-time, ~1 hour)

```bash
# 1. Create the VM
./build-vm/setup-build-vm.sh

# 2. Install Alpine Linux
cd ~/vms && ./start-alpine-vm.sh
# Follow prompts, use defaults

# 3. Configure Docker
ssh alpine-arm
sudo apk add docker docker-compose git nodejs npm
sudo rc-update add docker boot
sudo service docker start
sudo addgroup alpine docker
```

### Daily Use (~5 minutes)

```bash
# 1. Start VM (if not running)
cd ~/vms && ./start-alpine-vm.sh

# 2. Build images
./build-vm/build-arm-images.sh all

# 3. Push to AWS
source scripts/config/deployment.conf
ECR="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
docker tag fintech-backend:latest-arm64 ${ECR}/fintech-backend:latest-arm64
docker push ${ECR}/fintech-backend:latest-arm64

# 4. Deploy
./scripts/deploy-application.sh

# 5. Stop VM (optional)
./build-vm/stop-build-vm.sh
```

## Status Check

```bash
# Quick check
./build-vm/check-build-vm.sh --quick

# Full health check
./build-vm/check-build-vm.sh

# Just show status
./build-vm/check-build-vm.sh --status
```

## VM Location

All VM files are in `~/vms/`:
- `alpine-arm64.qcow2` - System disk (10GB)
- `alpine-data.qcow2` - Data disk (50GB)
- `start-alpine-vm.sh` - Starts the VM
- `docs/README.md` - VM documentation

## Troubleshooting

### VM won't start
```bash
# Install QEMU
sudo apt-get install qemu-system-arm qemu-efi-aarch64

# Check if already running
pgrep -f qemu
```

### Can't connect via SSH
```bash
# Test connection
ssh -p 2222 alpine@localhost

# Check SSH config
cat ~/.ssh/config | grep alpine-arm
```

### Slow performance
```bash
# Enable hardware acceleration
sudo usermod -aG kvm $USER
# Logout and login again
```

### Out of disk space
```bash
# Clean Docker
ssh alpine-arm "docker system prune -af"

# Expand disk
qemu-img resize ~/vms/alpine-data.qcow2 +20G
```

## Cost Savings

### Current Infrastructure (x86)
- 2x EKS nodes (t3.medium): $120/month
- 1x RDS (db.t3.medium): $80/month
- Other: $75/month
- **Total: $275/month**

### With ARM64
- 2x EKS nodes (t4g.medium): $70/month
- 1x RDS (db.t4g.medium): $60/month
- Other: $75/month
- **Total: $205/month**

### Savings
- **Monthly:** $70
- **Annual:** $840
- **3-year:** $2,520

## Documentation

- **Quick Start:** `build-vm/README.md`
- **Complete Guide:** `docs/ARM64-BUILD-GUIDE.md`
- **Integration:** `docs/ARM64-INTEGRATION.md`
- **Main Guide:** `START-HERE.md`

## Architecture

```
┌──────────────────────┐
│  Your Computer       │
│                      │
│  ┌────────────────┐  │
│  │ Alpine ARM VM  │  │──┐
│  │ Build images   │  │  │
│  └────────────────┘  │  │
└──────────────────────┘  │
                          │
                          ▼
                    ┌──────────┐
                    │ AWS ECR  │
                    │  Images  │
                    └──────────┘
                          │
                          ▼
                    ┌──────────┐
                    │ AWS EKS  │
                    │ Graviton │
                    │  -30%    │
                    └──────────┘
```

## Is This Required?

**No, it's optional** but highly recommended for production:

- Development: Use x86 (simpler)
- Production: Use ARM64 (cheaper)
- Testing: Either works

You can start with x86 and migrate to ARM64 later.

## Support

Run into issues?

1. Check `build-vm/README.md`
2. Check `docs/ARM64-BUILD-GUIDE.md`
3. Run: `./build-vm/check-build-vm.sh`
4. Look at VM console: `cd ~/vms && ./start-alpine-vm.sh`

## Next Steps

After setup:

1. **Update Terraform** to create ARM64 node groups:
   - Edit `terraform/eks/node-groups.tf`
   - Add `instance_types = ["t4g.medium"]`
   - Add `ami_type = "AL2_ARM_64"`

2. **Update Kubernetes** to use ARM64:
   - Add `nodeSelector: kubernetes.io/arch: arm64`
   - Use ARM64 image tags

3. **Monitor costs** in AWS Cost Explorer
   - Compare before/after
   - Should see 30-40% reduction

## Key Points

✅ **Optional** - Not required for deployment  
✅ **One-time setup** - ~1 hour initial configuration  
✅ **Daily use** - ~5 minutes per build  
✅ **Big savings** - $840/year reduction  
✅ **Better performance** - Native builds, faster than emulation  
✅ **Future-proof** - ARM64 is the future of cloud computing  

---

**Bottom Line:** Spend 1 hour now, save $840/year forever.
