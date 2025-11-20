# Fresh Installation Test Plan

**Date:** November 20, 2025  
**Purpose:** Validate all 5 bug fixes work together in automated installation  
**Status:** Ready to Execute

---

## Prerequisites

### Current State
- Current VM is running with manual fixes applied
- All 5 bugs have been fixed in the code
- Fixes committed: 4ba0ed4e1, 394c86ee7

### Before Starting
1. **Backup current VM** (optional - if you want to keep it):
   ```bash
   mkdir -p ~/vms/backup
   mv ~/vms/factory ~/vms/backup/factory-$(date +%Y%m%d-%H%M%S)
   ```

2. **Stop current VM** (if running):
   ```bash
   ~/vms/factory/stop-factory.sh
   # Or: sudo pkill -f "qemu-system-aarch64.*factory"
   ```

---

## Test Procedure

### Step 1: Complete Cleanup

Remove all Factory VM artifacts to ensure clean installation:

```bash
# Remove VM directory
rm -rf ~/vms/factory/

# Remove credentials
rm -rf ~/.factory-vm/

# Remove cached tokens
rm -f ~/.jenkins-factory-token

# Remove bashrc function (we'll re-add it)
# The installation will add it again

# Verify cleanup
ls -la ~/vms/factory 2>/dev/null && echo "ERROR: VM still exists" || echo "✓ Cleanup complete"
```

### Step 2: Run Fresh Installation

```bash
cd ~/wip/nb/FinTechProj/factory-vm

# Start installation with logging
./setup-factory-vm.sh 2>&1 | tee ~/logs/factory-vm-fresh-$(date +%Y%m%d-%H%M%S).log
```

**Expected Duration:** 18-25 minutes

**Monitor for:**
- No error messages during installation
- All components install successfully
- Jenkins initialization completes
- API token verification succeeds

### Step 3: Source Bash Configuration

After installation completes:

```bash
source ~/.bashrc
```

This loads the `jenkins-factory` function into your current shell.

---

## Verification Checklist

### ✅ Bug #1: PID File Creation

**Test:**
```bash
ls -la ~/vms/factory/factory.pid
```

**Expected Result:**
- File exists
- Owner: `jcgarcia:jcgarcia` (your user, not root)
- Readable by you

**Success Criteria:**
```
-rw-r--r-- 1 jcgarcia jcgarcia 7 Nov 20 XX:XX /home/jcgarcia/vms/factory/factory.pid
```

---

### ✅ Bug #2: Docker Status Check

**Test:**
```bash
~/vms/factory/status-factory.sh
```

**Expected Result:**
- Shows "Docker Containers" section
- Lists Jenkins container as "Up X minutes"
- No "not accessible" error

**Success Criteria:**
```
Docker Containers:
CONTAINER       STATUS
jenkins         Up 5 minutes
```

---

### ✅ Bug #3: Firefox Certificate

**Test:**
```bash
# Check certificate was installed
certutil -d sql:~/.mozilla/firefox/*.default -L | grep -i caddy

# If using Snap Firefox
certutil -d sql:~/snap/firefox/common/.mozilla/firefox/*.default -L | grep -i caddy
```

**Expected Result:**
- Shows Caddy CA certificates
- Both root and intermediate CAs listed

**Manual Verification:**
1. Open Firefox
2. Navigate to `https://factory.local`
3. Should load without certificate warning

**Success Criteria:**
- No "Warning: Potential Security Risk" page
- Lock icon shows secure connection

---

### ✅ Bug #4: Jenkins Foreman Password

**Test:**
```bash
# Get password from credentials file
FOREMAN_PASS=$(grep -A2 "Jenkins Web Console" ~/.factory-vm/credentials.txt | grep "Password:" | awk '{print $2}')
echo "Testing password: $FOREMAN_PASS"

# Test web authentication
curl -k -u "foreman:$FOREMAN_PASS" https://factory.local/whoAmI/api/json 2>&1 | grep -q "authenticated" && echo "✓ Password works" || echo "✗ Password failed"
```

**Manual Verification:**
1. Open `https://factory.local`
2. Click "Sign in"
3. Username: `foreman`
4. Password: (from credentials.txt)
5. Should login successfully

**Success Criteria:**
- Login succeeds
- Dashboard loads
- Shows "foreman" in top right corner

---

### ✅ Bug #5: Jenkins API Token

**Test on Host:**
```bash
jenkins-factory who-am-i
```

**Expected Result:**
```
Authenticated as: foreman
Authorities:
  authenticated
```

**Test in VM:**
```bash
ssh -p 2222 foreman@localhost "bash -l -c 'jenkins-factory who-am-i'"
```

**Expected Result:**
```
Authenticated as: foreman
Authorities:
  authenticated
```

**UI Verification:**
1. Login to Jenkins as foreman
2. Navigate to: `https://factory.local/user/foreman/security/`
3. Check "API Token" section
4. Should show: Token named "CLI Access"

**Success Criteria:**
- CLI command succeeds on host
- CLI command succeeds in VM
- Token visible in Jenkins UI

---

## Additional Tests

### General Functionality

**1. VM is Running:**
```bash
~/vms/factory/status-factory.sh
```
Should show:
- VM running with PID
- Resource usage (CPU, memory)
- Docker containers

**2. SSH Access Works:**
```bash
# As foreman (normal user)
ssh -p 2222 foreman@localhost "uname -a"

# As root (admin)
ssh -p 2222 root@localhost "docker ps"
```

**3. Jenkins is Accessible:**
```bash
curl -k https://factory.local 2>&1 | grep -q "Jenkins" && echo "✓ Jenkins responding" || echo "✗ Jenkins not accessible"
```

**4. No Errors in Installation Log:**
```bash
grep -i "error\|fail\|warn" ~/logs/factory-vm-fresh-*.log | grep -v "WARNING: JENKINS_FOREMAN_PASSWORD not set" || echo "✓ No unexpected errors"
```

---

## Success Criteria Summary

For the test to be considered successful, ALL of the following must pass:

1. ✅ Installation completes without errors
2. ✅ PID file owned by user (not root)
3. ✅ Status script shows Docker containers
4. ✅ Firefox trusts certificate (no warning)
5. ✅ Jenkins web login works with credentials.txt password
6. ✅ jenkins-factory CLI works on host
7. ✅ jenkins-factory CLI works in VM
8. ✅ API token visible in Jenkins UI
9. ✅ No manual interventions required
10. ✅ All components accessible and functional

---

## If Test Fails

### Gather Diagnostics

```bash
# Save installation log
cp ~/logs/factory-vm-fresh-*.log ~/logs/FAILED-install-$(date +%Y%m%d-%H%M%S).log

# Check VM status
~/vms/factory/status-factory.sh > ~/logs/vm-status-failed.log 2>&1

# Check Jenkins logs
ssh -p 2222 root@localhost "docker logs jenkins" > ~/logs/jenkins-failed.log 2>&1

# Check which tests failed
# Document specific failures in GitHub issue or status document
```

### Report Failure

Document in `CURRENT-STATUS.md`:
- Which verification step(s) failed
- Error messages encountered
- Logs saved for analysis
- Expected vs actual behavior

---

## After Successful Test

### Cleanup

```bash
# Remove fix script (no longer needed)
rm ~/wip/nb/FinTechProj/factory-vm/fix-jenkins-token.sh

# Commit the removal
cd ~/wip/nb/FinTechProj
git rm factory-vm/fix-jenkins-token.sh
git commit -m "chore: remove one-time fix script after successful test"
```

### Update Documentation

1. Update `CURRENT-STATUS.md`:
   - Mark all 5 bugs as "✅ VERIFIED in fresh installation"
   - Document test date and results
   - Remove "needs testing" warnings

2. Update `FactoryVM-Sprint2-Status-Nov18.md`:
   - Mark test as complete
   - Document that all fixes work
   - Move to next sprint phase

3. Create success summary:
   ```bash
   echo "Fresh Installation Test - SUCCESS" > ~/wip/nb/FinTechProj/factory-vm/TEST-RESULTS.md
   date >> ~/wip/nb/FinTechProj/factory-vm/TEST-RESULTS.md
   echo "All 5 bugs verified fixed" >> ~/wip/nb/FinTechProj/factory-vm/TEST-RESULTS.md
   ```

---

## Test Execution Checklist

- [ ] Current VM stopped
- [ ] All Factory VM files cleaned up
- [ ] Fresh installation started
- [ ] Installation completed successfully
- [ ] Bash configuration sourced
- [ ] Bug #1 verified (PID file)
- [ ] Bug #2 verified (Docker status)
- [ ] Bug #3 verified (Firefox cert)
- [ ] Bug #4 verified (Jenkins password)
- [ ] Bug #5 verified (API token)
- [ ] Additional tests passed
- [ ] Success documented
- [ ] Ready for Sprint 2 continuation

---

**Prepared by:** GitHub Copilot  
**Date:** November 20, 2025  
**Status:** Ready for execution
