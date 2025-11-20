# Factory VM - Branches and Versions

## Branch Strategy

This repository uses multiple branches to maintain different versions of the factory-vm installer with varying features and performance characteristics.

## Available Branches

### `main` (Default)
**Status:** Stable, production-ready  
**Last Updated:** November 20, 2025  
**Installation Time:** ~49 minutes on TCG emulation  

**Features:**
- ✅ One-liner installer (`curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh | bash`)
- ✅ Auto-detected versions (Alpine, Terraform, kubectl, Helm)
- ✅ Heredoc-based installation (vm-setup.sh runs inside VM)
- ✅ One-by-one plugin installation with progress tracking
- ✅ Docker pull with progress visibility
- ✅ `-tt` flag for reduced output buffering
- ✅ Version detection with `-L` flag (follows redirects)

**Architecture:**
- Downloads happen **inside the VM**
- Installation script generated as heredoc
- SCP vm-setup.sh to VM, execute via SSH

**Use This Branch When:**
- You want the most stable, tested version
- First-time installation
- Production deployments

---

### `v1-stable-heredoc`
**Status:** Archived stable version  
**Last Updated:** November 20, 2025  
**Installation Time:** ~49 minutes on TCG emulation  

**Features:**
- Identical to `main` (snapshot before v2 development)
- All v1 features and fixes
- Proven working installation (completed successfully)

**Purpose:**
- Preserve the working v1 architecture before major v2 changes
- Fallback branch if v2 has issues
- Reference for comparing architectures

**Use This Branch When:**
- You need to reference the original working implementation
- Comparing v1 vs v2 architectures
- Rolling back from v2 if needed

---

### `v2-caching-architecture` ⭐ NEW
**Status:** Development/Testing  
**Last Updated:** November 20, 2025  
**Installation Time:** 
- First install: ~49 minutes (downloads and caches)
- Subsequent installs: **~10-15 minutes** (uses cache, 3x faster!)

**Features:**
- ✅ All v1 features PLUS:
- ✅ **Smart caching** - Download once, use many times
- ✅ **Parallel downloads** - Terraform, kubectl, Helm downloaded simultaneously
- ✅ **Offline capable** - Can install without internet after first download
- ✅ **Bandwidth savings** - No re-downloads on subsequent installations
- ✅ **Graceful fallback** - Downloads if cache missing

**Architecture:**
- Downloads happen **on the host** (before VM starts)
- Files cached in `~/vms/factory/cache/`
- Cached files SCP'd to VM
- VM installs from `/tmp` (no downloads needed)

**Cache Structure:**
```
~/vms/factory/cache/
├── terraform/
│   └── terraform_1.14.0_linux_arm64.zip
├── kubectl/
│   └── kubectl_1.34.2
└── helm/
    └── helm-v4.0.0-linux-arm64.tar.gz
```

**Installation Flow:**
1. Detect latest versions (Terraform, kubectl, Helm)
2. Check cache - download only if missing (parallel)
3. SCP cached files from host → VM
4. Install from /tmp (fast, no network dependency)

**Use This Branch When:**
- Testing new caching functionality
- You plan to install VMs multiple times
- You have limited internet bandwidth
- You want faster subsequent installations

**To Test This Branch:**
```bash
# On the remote server
cd ~
rm -rf factory-vm  # Remove any existing clone
git clone -b v2-caching-architecture https://github.com/jcgarcia/factory-vm.git
cd factory-vm
./setup-factory-vm.sh --auto
```

---

## Version Comparison

| Feature | `main` / `v1-stable-heredoc` | `v2-caching-architecture` |
|---------|------------------------------|---------------------------|
| **Installation Time (1st)** | ~49 min | ~49 min |
| **Installation Time (2nd+)** | ~49 min | **~10-15 min** |
| **Downloads** | Inside VM | On host (cached) |
| **Bandwidth Usage (2nd+)** | Same as 1st | **Minimal** |
| **Offline Installation** | ❌ No | ✅ Yes (after 1st) |
| **Cache Directory** | N/A | `~/vms/factory/cache/` |
| **Parallel Downloads** | ❌ No | ✅ Yes |
| **Output Buffering** | Minimal (`-tt`) | Minimal (`-tt`) |
| **Stability** | ✅ Proven | 🧪 Testing |

---

## Roadmap

### v2.1 (Planned)
- **Jenkins plugin caching** - Cache .jpi files on host
- **SSH-based installation** - Replace heredoc with individual SSH commands
- **Real-time output from host** - See plugin installation progress on host terminal
- **Jenkins CLI on host** - Install plugins from host via SSH tunnel

### v2.2 (Future)
- **Cache management** - Clean old versions, show cache stats
- **Version tracking** - `versions.json` to track cached versions
- **Parallel component installation** - Install independent components simultaneously
- **Resume capability** - Resume failed installations from last successful step

---

## Migration Guide

### From `main` to `v2-caching-architecture`

**First Installation (builds cache):**
1. Clean up any existing installation:
   ```bash
   ssh <server> "rm -rf ~/vms/factory ~/factory-vm"
   ```

2. Clone the v2 branch:
   ```bash
   ssh <server> "git clone -b v2-caching-architecture https://github.com/jcgarcia/factory-vm.git"
   ```

3. Run installation (will download and cache):
   ```bash
   ssh <server> "cd factory-vm && ./setup-factory-vm.sh --auto"
   ```
   
   **Expected:** ~49 minutes, creates cache directory

**Subsequent Installations (uses cache):**
1. Clean up VM (keep cache!):
   ```bash
   ssh <server> "rm -rf ~/vms/factory/factory.qcow2 ~/vms/factory/factory-data.qcow2"
   ```

2. Run installation again:
   ```bash
   ssh <server> "cd ~/factory-vm && git pull && ./setup-factory-vm.sh --auto"
   ```
   
   **Expected:** ~10-15 minutes (no downloads, uses cache)

### Rollback to `v1-stable-heredoc`

If v2 has issues:
```bash
ssh <server> "cd ~/factory-vm && git checkout v1-stable-heredoc && ./setup-factory-vm.sh --auto"
```

---

## Testing Status

### v1-stable-heredoc
- ✅ **Tested:** November 20, 2025
- ✅ **Result:** Successful installation in 49 minutes
- ✅ **Platform:** x86_64 → ARM64 (TCG emulation)
- ✅ **Environment:** Ubuntu host, Alpine 3.22.2 VM
- ✅ **All components:** Working (Base, Docker, Caddy, K8s, Terraform, Jenkins, Plugins)

### v2-caching-architecture
- ⏳ **Status:** Ready for testing
- 🧪 **Testing Needed:** First installation + cache validation
- 🧪 **Testing Needed:** Second installation using cache
- 🧪 **Testing Needed:** Cache hit/miss scenarios
- 🧪 **Testing Needed:** Offline installation validation

---

## Choosing the Right Branch

**Use `main` or `v1-stable-heredoc` if:**
- ✅ You need a proven, stable installation
- ✅ You're installing for the first time only
- ✅ You don't plan to reinstall frequently
- ✅ You want the safest option

**Use `v2-caching-architecture` if:**
- ✅ You plan to install multiple VMs
- ✅ You have bandwidth constraints
- ✅ You want faster subsequent installations
- ✅ You want offline installation capability
- ✅ You're willing to test new features

---

## Contributing

When developing new features:
1. Branch from `main` or `v2-caching-architecture`
2. Create a feature branch: `feature/your-feature-name`
3. Test thoroughly
4. Submit PR to the appropriate base branch

## Support

For issues specific to a branch:
- **v1 issues:** Tag with `v1` label
- **v2 issues:** Tag with `v2` label
- **General issues:** No version tag needed

## Version History

- **v1.0** (Nov 20, 2025) - Initial stable release with heredoc architecture
- **v2.0** (Nov 20, 2025) - Caching architecture implementation

---

## Quick Reference Commands

```bash
# Clone main branch (default)
git clone https://github.com/jcgarcia/factory-vm.git

# Clone specific branch
git clone -b v2-caching-architecture https://github.com/jcgarcia/factory-vm.git

# Switch branches (in existing clone)
git checkout main
git checkout v1-stable-heredoc
git checkout v2-caching-architecture

# One-liner installer (uses main branch)
curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh | bash

# One-liner for specific branch
curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/v2-caching-architecture/install.sh | bash
```
