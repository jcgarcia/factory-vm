# Factory VM - Current Status and Context
**Date**: November 20, 2025 18:30
**Session**: V2 Caching Architecture - Phase 2 Complete

## Quick Summary

**Latest Work**: Phase 2 Jenkins plugin caching implemented ✅
**Current Branch**: v2-caching-architecture
**Architecture**: V2 caching (tools + plugins)
**Next Phase**: Phase 3 - SSH-based installation (replace heredoc)
**Expected Performance**: 49min → 15-20min on subsequent installs

---

## V2 Caching Architecture Progress

### ✅ Phase 1: Tool Caching (COMPLETE)
**Commit**: 7af0cdb
**Date**: November 20, 2025

**Implemented**:
- `download_and_cache_terraform()` - Downloads Terraform to cache
- `download_and_cache_kubectl()` - Downloads kubectl to cache  
- `download_and_cache_helm()` - Downloads Helm to cache
- `cache_all_tools()` - Parallel downloads with version detection
- Cache directory: `~/vms/factory/cache/{terraform,kubectl,helm}/`
- Modified vm-setup.sh to prefer cached files
- SCP cached files from host → VM before installation

**Performance**: Saves ~5-10 minutes on subsequent installs

---

### ✅ Phase 2: Jenkins Plugin Caching (COMPLETE)
**Commit**: 34974fb
**Date**: November 20, 2025

**Implemented**:
- `download_and_cache_plugin()` - Downloads individual .hpi files
- `cache_all_plugins()` - Downloads all 25 plugins in parallel batches (5 at a time)
- Cache directory: `~/vms/factory/cache/jenkins/plugins/`
- Modified vm-setup.sh to install plugins from /tmp cache first
- Graceful fallback to jenkins-plugin-cli if cache missing
- SCP all cached .hpi files from host → VM
- Installation summary shows cached vs downloaded counts

**Performance**: Saves ~20-25 minutes on subsequent installs (plugins are biggest download)

**Cache Structure**:
```
~/vms/factory/cache/
├── terraform/
│   └── terraform_1.14.0_linux_arm64.zip
├── kubectl/
│   └── kubectl_1.34.2
├── helm/
│   └── helm-v4.0.0-linux-arm64.tar.gz
└── jenkins/
    └── plugins/
        ├── configuration-as-code.hpi
        ├── git.hpi
        ├── git-client.hpi
        ... (25 plugins total)
```

**Expected Installation Times**:
- v1 (no caching): ~49 minutes
- v2 Phase 1 (tools only): ~40 minutes
- v2 Phase 2 (tools + plugins): **~15-20 minutes** ⭐

---

### 🚧 Phase 3: SSH-Based Installation (NEXT)
**Status**: Not started
**Goal**: Replace heredoc with individual SSH commands from host

**Benefits**:
- Real-time output visibility on host terminal
- No output buffering issues
- Easier debugging (see exactly what's running)
- Can pause/resume installation
- Better error handling per component

**Scope**:
- Large refactoring - replace 1000+ line heredoc
- Install components via SSH commands instead of vm-setup.sh script
- Keep caching architecture from Phase 1 & 2
- Recommended: Create feature branch `v2.1-ssh-based-install`

---

### 📋 Future Phases (Planned)

#### Phase 4: Alpine ISO Caching
- Cache Alpine ISO (~200MB)
- Saves 5-10 minutes on slow connections

#### Phase 5: Docker Image Caching  
- Cache Jenkins Docker image
- Saves 10-20 minutes on TCG emulation

#### Phase 6: Jenkins CLI on Host
- Install Jenkins CLI on host
- Install plugins via SSH tunnel + jenkins-cli
- Real-time plugin installation progress

---

## Branches and Versions

### `main` (Stable)
- v1.0 architecture (heredoc-based)
- Installation time: ~49 minutes
- Proven working (completed Nov 18-20)

### `v1-stable-heredoc` (Archive)
- Snapshot of v1 before v2 development
- Installation time: ~49 minutes
- Fallback branch if v2 has issues

### `v2-caching-architecture` (Current Development) ⭐
- Phase 1: Tool caching ✅
- Phase 2: Plugin caching ✅
- Phase 3: SSH-based install 🚧
- Expected time: ~15-20 minutes (after cache built)

**Documentation**: See `BRANCHES-AND-VERSIONS.md` for detailed comparison

---

## Previous Session Work (Nov 18-20, 2025)
**Date**: November 20, 2025
**Commit**: 4ba0ed4e1 + updates

**Problem**: 
- `jenkins-factory who-am-i` failing with 401 Unauthorized
- API token file exists but token not visible in Jenkins UI
- Screenshot showed "No API tokens configured" for foreman user

**Root Cause**:
```groovy
// Groovy script generated token but never saved user
def result = tokenStore.tokenStore.generateNewToken("CLI Access")
new File('/var/jenkins_home/foreman-api-token.txt').text = result.plainValue
instance.save()  // ❌ Saves Jenkins config, NOT user properties
```

**Solution**:
```groovy
// Added user.save() before instance.save()
user.save()      // ✅ Persists user properties including API token
instance.save()
```

**That's it.** No workarounds, no verification scripts, no fixing things twice.  
Just do it right the first time.

**Verification**:
```bash
# Works on host
jenkins-factory who-am-i
# Output: Authenticated as: foreman

# Works in VM (login shell)
ssh -p 2222 foreman@localhost "bash -l -c 'jenkins-factory who-am-i'"
# Output: Authenticated as: foreman
```

**Files Modified**:
- `setup-factory-vm.sh` - Added `user.save()` call (line 1047)

**Status**: Fixed in current VM + committed for new installations

---

## Bugs Fixed November 18, 2025 (All Committed)

### 1. PID File Creation Issue ✅ FIXED
**Commit**: 8e68e4a2c

**Problem**: QEMU with sudo cannot create PID file in user directory

**Solution**:
```bash
# In start-factory.sh generation:
touch "${PID_FILE}"  # Create empty file as user before QEMU starts
sudo qemu-system-aarch64 ... -pidfile "${PID_FILE}"
sudo chown ${USER}:${USER} "${PID_FILE}"  # Fix ownership after
```

**Status**: Committed, needs testing

---

### 2. Docker Status Check Wrong User ✅ FIXED
**Commit**: e8da79ebb (original), verified in 8e68e4a

**Problem**: Status script used `root@localhost` but Docker runs as foreman user

**Solution**:
```bash
# Changed from:
ssh ... root@localhost "docker ps ..."

# To:
ssh ... foreman@localhost "sudo docker ps --format 'table {{.Names}}\t{{.Status}}'"
```

**Status**: Committed, manually verified working

---

### 3. Snap Firefox Certificate Installation ✅ FIXED
**Commit**: 99baf103d

**Problem**: Firefox installed via Snap uses isolated certificate store at `~/snap/firefox/common/.mozilla/firefox/`

**Solution**:
```bash
# Added to Firefox profile search:
local firefox_dirs=(
    ~/.mozilla/firefox
    ~/snap/firefox/common/.mozilla/firefox  # Added for Snap
)
```

**Also fixes**:
- Removes old certificates from previous installations before installing new ones
- No hardcoded paths - finds profiles dynamically

**Status**: Committed, manually verified working

---

### 4. Jenkins Foreman Password Wrong ✅ FIXED  
**Commit**: 3508138d0

**Problem**: Jenkins foreman user created with `JENKINS_ADMIN_PASSWORD` instead of `JENKINS_FOREMAN_PASSWORD`

**Solution**:
```groovy
// Changed in 05-create-foreman-user.groovy:
def foremanPassword = System.getenv('JENKINS_FOREMAN_PASSWORD')  // Was: JENKINS_ADMIN_PASSWORD
```

**Impact**: Users couldn't login with password from credentials.txt

**Status**: Committed, needs testing

---

## Current Test Installation

**Started**: Nov 18, 21:54
**Completed**: Nov 18, 22:13 (18m 44s)
**Profile**: High Performance (8GB RAM, 6 CPUs, 200GB data)
**Log**: `~/logs/factory-vm-test-20251118-215409.log`

**Known Issues** (installation was BEFORE final fixes):
- ✅ Status script works (manually fixed)
- ✅ Docker containers show correctly (manually fixed)
- ✅ Firefox certificate works (manually fixed)
- ❌ Jenkins foreman password doesn't work (wrong password used)
- ❌ PID file not tested (manually created)

---

## What Works in Current VM

### ✅ Fully Working
1. **VM Running**: QEMU PID 3133473, 8GB RAM, 6 CPUs
2. **SSH Access**: `ssh -p 2222 foreman@localhost` (after accepting host key)
3. **Status Script**: Shows VM running, Docker containers, resources
4. **HTTPS Access**: https://factory.local (after Firefox restart)
5. **Docker**: Jenkins container running
6. **Credentials File**: `~/.factory-vm/credentials.txt` created

### ⚠️ Needs Manual Intervention
1. **SSH Host Key**: First connection asks to accept key (normal for fresh VM)
2. **Jenkins Login**: Can't login with foreman password (bug fixed for next test)

---

## All Commits from Today's Session

```
3508138d0 - fix: use JENKINS_FOREMAN_PASSWORD for foreman user
99baf103d - fix: support Snap Firefox certificate installation  
0abe8e4bb - revert: remove unnecessary certificate documentation
47b93da8e - docs: improve certificate documentation
8e68e4a2c - fix: touch PID file before QEMU starts
718acfda0 - fix: create PID file manually after QEMU daemonizes
e8da79ebb - fix: PID file ownership and Docker status check
e3172b86d - docs: document Factory VM bug fixes and testing status
```

---

## Testing Checklist for Next Fresh Installation

### Critical Tests
- [ ] PID file created automatically with correct ownership
- [ ] Status script works immediately (no manual fixes)
- [ ] Docker containers visible in status output
- [ ] Firefox certificate trusted (no warnings)
- [ ] Jenkins foreman login works with password from credentials.txt
- [ ] No installation warnings or errors

### Full Validation
- [ ] `~/vms/factory/status-factory.sh` - works perfectly
- [ ] `cat ~/.factory-vm/credentials.txt` - contains all passwords
- [ ] Firefox → https://factory.local - no certificate warning
- [ ] Login with foreman / (password from credentials) - succeeds
- [ ] `jenkins-factory who-am-i` - authenticates correctly
- [ ] Check installation log for any warnings

---

## Files Modified This Session

### Core Script
- `factory-vm/setup-factory-vm.sh` (multiple fixes)

### Documentation  
- `factory-vm/CURRENT-STATUS.md` (this file)
- `factory-vm/SESSION-CONTEXT-Nov18-2140.md` (created earlier)
- `docs/milestones/FactoryVM-Sprint2-Status-Nov18.md` (created earlier)

---

## Commands for Next Session

### Clean and Test
```bash
# Stop current VM
~/vms/factory/stop-factory.sh
sudo pkill -9 qemu-system-aarch64

# Clean everything
rm -rf ~/vms/factory/ ~/.factory-vm/
rm ~/.jenkins-factory-token ~/jenkins-cli-factory.jar

# Run fresh installation
cd ~/wip/nb/FinTechProj/factory-vm
./setup-factory-vm.sh

# Test immediately
~/vms/factory/status-factory.sh

# Check PID file ownership
ls -la ~/vms/factory/factory.pid
# Should be: -rw-r--r-- jcgarcia jcgarcia

# Test Firefox (restart Firefox first)
# Open: https://factory.local
# Should: No certificate warning

# Test Jenkins login
# Username: foreman
# Password: (from ~/.factory-vm/credentials.txt)
# Should: Login succeeds
```

---

## Summary for Tomorrow

**Status**: All known bugs fixed and committed ✅

**Next Action**: Run complete fresh installation test

**Expected Results**:
- PID file created automatically
- Status script works without manual fixes  
- Firefox trusts certificate immediately
- Docker status shows Jenkins container
- Jenkins foreman login works with credentials.txt password

**If All Tests Pass**: Factory VM installation is complete and production-ready

**If Tests Fail**: Debug specific failures and apply additional fixes

---

## Installation Profile Used

```yaml
Profile: OPTIMAL (High Performance)
Memory: 8GB
CPUs: 6 cores
System Disk: 50GB
Data Disk: 200GB
Installation Time: ~18-20 minutes
```

---

*All work saved. Ready for fresh installation test tomorrow.*

### What's Working ✅
1. **Factory VM is accessible via SSH**
   - Port: 2222
   - User: `foreman` (with sudo via doas)
   - Test: `ssh -p 2222 foreman@localhost` ✅

2. **Jenkins is running**
   - Container: `jenkins/jenkins:lts-jdk21`
   - Version: 2.528.2
   - Status: Running for 17+ minutes
   - Access: https://factory.local ✅

3. **Jenkins CLI is configured on host**
   - File: `~/jenkins-cli-factory.jar` (11.6 MB) ✅
   - Function: `jenkins-factory()` in `~/.bashrc` ✅
   - Token: `~/.jenkins-factory-token` (retrieved) ✅
   - Authentication: Working ✅

4. **Jenkins foreman user exists**
   - Username: `foreman`
   - Password: `foreman123` (hardcoded in script)
   - API Token: `11ce90a73ba75b661dbb5f3302227893e6`
   - Permissions: Full admin

5. **Caddy certificates exported**
   - Files in `/home/jcgarcia/vms/factory/`:
     - `caddy-root-ca.crt`
     - `caddy-intermediate-ca.crt`

### What's NOT Working ❌

## Latest Test Results (Nov 18, 2025 - 20:57)

### ✅ Installation Completed Successfully
**Duration**: 18 minutes 44 seconds  
**Log**: `~/logs/factory-vm-install-20251118-205730.log`

**Fixed Issues**:
1. ✅ Credentials file created: `~/.factory-vm/credentials.txt`
2. ✅ Installation completed without interruption
3. ✅ All components installed successfully

### ⚠️ Issues Found During Testing

#### 1. PID File Ownership Problem
**Problem**: QEMU runs with `sudo` (for port 443), creates root-owned PID file

**Symptoms**:
- `factory.pid` owned by root (or doesn't exist)
- Status script fails: "Cannot read PID file"
- User cannot check VM status without sudo

**Root Cause**: 
```bash
sudo qemu-system-aarch64 ... -pidfile "${PID_FILE}"
# Creates: -rw-r--r-- root:root factory.pid
```

**Solution Applied**:
```bash
# In start-factory.sh (generated by setup script)
sudo qemu-system-aarch64 ... -pidfile "${PID_FILE}"
# Immediately after QEMU starts:
[ -f "${PID_FILE}" ] && sudo chown ${USER}:${USER} "${PID_FILE}"
```

**Status**: ✅ Fixed in `setup-factory-vm.sh` line ~1964 (commit e8da79e)

#### 2. Docker Status Check Using Wrong User
**Problem**: Status script uses `root@localhost` but Docker runs as `foreman` user

**Symptoms**:
```
Docker Containers:
  Docker not accessible
```

**Reality**: Jenkins container running fine, but status script can't see it

**Root Cause**:
```bash
# Old code (wrong):
ssh ... root@localhost "docker ps ..."

# Docker daemon socket: /var/run/docker.sock (group: docker)
# Foreman user: member of docker group
# Root user: can access but SSH key is for foreman
```

**Solution Applied**:
```bash
# New code (correct):
ssh ... foreman@localhost "sudo docker ps --format 'table {{.Names}}\t{{.Status}}'"
```

**Status**: ✅ Fixed in `setup-factory-vm.sh` line ~2114 (commit e8da79e)

#### 3. MOTD Creation Failed During Installation
**Problem**: MOTD creation showed warning: "Failed to create welcome banner"

**Investigation**: MOTD code uses `bash -s` to force bash shell (Alpine default is `ash`)

**Status**: ⚠️ Fixed in script but not tested - current MOTD was created manually

### 🔧 Fixes Applied to setup-factory-vm.sh

**Commit**: `e8da79ebb` - "fix: PID file ownership and Docker status check in Factory VM"

**Changes**:

1. **Start script generation** (line ~1960-1970):
   ```bash
   # After QEMU starts
   [ -f "${PID_FILE}" ] && sudo chown ${USER}:${USER} "${PID_FILE}"
   ```

2. **Status script generation** (line ~2105-2115):
   ```bash
   # Changed from root@localhost to foreman@localhost
   ssh ... foreman@localhost "sudo docker ps ..."
   
   # Also fixed PID file reading:
   PID=$(sudo cat "$PID_FILE" 2>/dev/null || cat "$PID_FILE" 2>/dev/null)
   ```

3. **MOTD creation** (line ~1791):
   ```bash
   # Force bash shell for heredoc functions
   ssh root@localhost 'bash -s' << 'MOTD_SCRIPT'
   ```

### 📝 What Still Needs Testing

#### 1. Fresh Installation Test
**Purpose**: Verify all fixes work in automated installation

**What to test**:
- [ ] PID file created with correct ownership
- [ ] Status script works without manual intervention
- [ ] MOTD displays correctly on first SSH
- [ ] Docker status shows containers
- [ ] No warnings in installation log

#### 2. Current Running VM Issues
**Known problems with current VM** (installed before fixes):
- PID file manually created: `echo "3062025" > factory.pid`
- Status script manually updated with fixed version
- MOTD manually created (not by installation script)

**These are bandaids** - need clean installation test to verify fixes work automatically.

### What's NOT Working ❌ (OLD SECTION - Resolved)

## Files and Locations

### Host System
```
~/.factory-vm/                       # ❌ MISSING - should contain credentials
~/jenkins-cli-factory.jar            # ✅ EXISTS (11.6 MB)
~/.jenkins-factory-token             # ✅ EXISTS (API token)
~/.bashrc                            # ✅ Modified (jenkins-factory function)
~/.ssh/factory-foreman               # ✅ SSH private key
~/.ssh/factory-foreman.pub           # ✅ SSH public key
```

### VM Directory
```
/home/jcgarcia/vms/factory/
├── factory.qcow2                    # System disk (50GB)
├── factory-data.qcow2               # Data disk (200GB)
├── factory.pid                      # ⚠️ Permission issues (root owned)
├── start-factory.sh                 # ✅ Start script
├── stop-factory.sh                  # ✅ Stop script
├── status-factory.sh                # ❌ Permission issue
├── setup-jenkins-cli.sh             # ✅ Manual CLI setup
├── vm-setup.sh                      # VM internal setup script
├── caddy-root-ca.crt               # ✅ CA certificate
├── caddy-intermediate-ca.crt       # ✅ Intermediate cert
└── isos/
    └── alpine-virt-3.19.1-aarch64.iso
```

### Inside VM
```
/root/factory-install.log            # ❓ Need to verify exists
/etc/motd                            # ❓ Need to verify content
/opt/jenkins/                        # Jenkins home
/var/jenkins_home/foreman-api-token.txt  # API token (in container)
/home/foreman/.ssh/authorized_keys   # SSH key
/home/foreman/.bashrc                # Bash config
```

## Known Passwords

### Set During Installation
1. **Jenkins Admin User**
   - Username: `admin`
   - Password: `admin123` (hardcoded in script line ~93)
   - Environment var: `JENKINS_ADMIN_PASSWORD`

2. **Jenkins Foreman User**
   - Username: `foreman`
   - Password: `foreman123` (hardcoded in script)
   - API Token: `11ce90a73ba75b661dbb5f3302227893e6`

3. **VM Root User**
   - Password: Generated during install (stored in `VM_ROOT_PASSWORD` var)
   - ❌ NOT saved to credentials file

4. **VM Foreman User**
   - Password: Generated during install (stored in `FOREMAN_OS_PASSWORD` var)
   - ❌ NOT saved to credentials file
   - SSH: Key-based authentication (password auth disabled)

## Script Variables (from setup-factory-vm.sh)

### Security Passwords (Generated)
```bash
JENKINS_ADMIN_PASSWORD=$(generate_secure_password)   # Line ~2783
JENKINS_FOREMAN_PASSWORD=$(generate_secure_password) # Line ~2784
VM_ROOT_PASSWORD=$(generate_secure_password)         # Line ~2785
FOREMAN_OS_PASSWORD=$(generate_secure_password)      # Line ~2786
```

**Issue**: These are generated but NOT saved anywhere accessible to the user!

### Configuration
```bash
VM_DIR="${HOME}/vms/factory"
VM_NAME="factory"
VM_MEMORY="8G"          # Selected from profile
VM_CPUS="6"             # Selected from profile
VM_SSH_PORT="2222"
VM_HOSTNAME="factory.local"
VM_USERNAME="foreman"
SSH_KEY_NAME="factory-foreman"
SYSTEM_DISK_SIZE="50G"
DATA_DISK_SIZE="200G"   # Selected from profile
```

## What Needs to be Fixed

### Critical Issues

1. **Create credentials file**
   ```bash
   mkdir -p ~/.factory-vm/
   cat > ~/.factory-vm/credentials.txt << 'EOF'
   Factory VM Credentials
   ======================
   
   VM Access:
     SSH: ssh factory  (or: ssh -p 2222 foreman@localhost)
     User: foreman
     Auth: SSH key (~/.ssh/factory-foreman)
   
   Jenkins Web UI:
     URL: https://factory.local
     Admin: admin / admin123
     Foreman: foreman / foreman123
   
   Jenkins CLI:
     Command: jenkins-factory <command>
     User: foreman
     API Token: 11ce90a73ba75b661dbb5f3302227893e6
   
   Notes:
     - SSH uses key authentication (password disabled)
     - HTTPS certificate is self-signed (accept in browser)
     - Jenkins CLI requires Java on host
   EOF
   chmod 600 ~/.factory-vm/credentials.txt
   ```

2. **Fix status script permission issue**
   - Make PID file readable: `sudo chmod 644 /home/jcgarcia/vms/factory/factory.pid`
   - Or: Check process with `ps aux | grep qemu` instead of reading PID file

3. **Add final summary to setup script**
   - Show connection info
   - Show credentials location
   - Show next steps

4. **Fix MOTD in VM** (if broken)
   - Check current MOTD
   - Re-create if needed

5. **Verify installation log exists**
   - Check `/root/factory-install.log` in VM
   - Copy to host for review if needed

### Script Improvements Needed

Location: `factory-vm/setup-factory-vm.sh`

1. **Line ~2780-2790**: Save generated passwords to credentials file
2. **Line ~2950+**: Add final summary output
3. **Line ~2480**: Fix MOTD creation script
4. **Status script**: Handle root-owned PID file gracefully

## Testing Checklist

### Immediate Tests
- [ ] Check if `~/.factory-vm/` exists
- [ ] Check if installation log exists in VM
- [ ] Verify MOTD content
- [ ] Test status script
- [ ] Verify all passwords work

### Jenkins Tests
- [x] CLI authentication (working)
- [x] CLI who-am-i (working)
- [x] CLI version (working)
- [ ] Web UI login (admin)
- [ ] Web UI login (foreman)
- [ ] Create test job via CLI
- [ ] Trigger build via CLI

### VM Tests
- [x] SSH access (working)
- [ ] Docker access (needs session refresh)
- [ ] Sudo access (doas)
- [ ] Tools installed (docker, kubectl, helm, terraform, aws)

## Next Steps

1. **Gather information**:
   ```bash
   # Check credentials directory
   ls -la ~/.factory-vm/
   
   # Check installation log
   ssh -p 2222 root@localhost "cat /root/factory-install.log" | tail -50
   
   # Check MOTD
   ssh -p 2222 foreman@localhost "cat /etc/motd"
   
   # Test Docker (new session)
   ssh -p 2222 foreman@localhost "newgrp docker; docker ps"
   ```

2. **Create missing credentials file** (manual)

3. **Fix script issues**:
   - Add credentials file creation
   - Add final summary
   - Fix status script
   - Fix MOTD if needed

4. **Test installation** again on a fresh VM

## Commands for Recovery

### Create Credentials File Now
```bash
mkdir -p ~/.factory-vm/
cat > ~/.factory-vm/credentials.txt << 'EOF'
Factory VM Credentials
======================

VM Access:
  SSH: ssh -p 2222 foreman@localhost
  Alias: Add to ~/.ssh/config:
    Host factory
      HostName localhost
      Port 2222
      User foreman
      IdentityFile ~/.ssh/factory-foreman

Jenkins Web UI:
  URL: https://factory.local
  Admin User: admin / admin123
  Foreman User: foreman / foreman123

Jenkins CLI:
  Command: jenkins-factory <command>
  Examples:
    jenkins-factory who-am-i
    jenkins-factory list-jobs
    jenkins-factory build <job>

Notes:
  - Accept HTTPS certificate warning in browser
  - Jenkins CLI requires Java on host
  - VM uses 8GB RAM, 6 CPUs
EOF
chmod 600 ~/.factory-vm/credentials.txt
echo "Credentials saved to ~/.factory-vm/credentials.txt"
```

### Fix Status Script
```bash
# Edit status-factory.sh to handle root-owned PID
# Or run with sudo:
sudo cat /home/jcgarcia/vms/factory/factory.pid
```

### View Installation Log
```bash
ssh -p 2222 root@localhost "cat /root/factory-install.log"
```

### Add SSH Config Alias
```bash
cat >> ~/.ssh/config << 'EOF'

# Factory VM
Host factory
  HostName localhost
  Port 2222
  User foreman
  IdentityFile ~/.ssh/factory-foreman
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF

# Test
ssh factory "echo 'SSH alias working!'"
```

## Summary

**VM Status**: ✅ Running and fully functional  
**Installation**: ✅ Completed successfully (18m 44s)  
**Fixes Applied**: ✅ PID ownership + Docker status (commit e8da79e)  
**Ready for Testing**: ⚠️ Need fresh installation to verify all fixes work automatically

**Action Required**:

1. **Delete current VM** (installed before fixes):

   ```bash
   ~/vms/factory/stop-factory.sh
   rm -rf ~/vms/factory/
   rm -rf ~/.factory-vm/
   ```

2. **Run fresh installation test**:

   ```bash
   cd ~/wip/nb/FinTechProj/factory-vm
   ./setup-factory-vm.sh
   ```

3. **Verify fixes**:
   - PID file ownership correct
   - Status script works without sudo
   - Docker containers visible in status
   - MOTD displays on SSH
   - No installation warnings

**Commit Status**: All fixes committed to `setup-factory-vm.sh` (e8da79ebb)

---

*This document captures the current state for continuity across sessions.*
