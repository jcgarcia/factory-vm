# Factory VM v1.2.5 - Security Hardening

**Date**: November 18, 2025  
**Version**: v1.2.5  
**Status**: Ready for Testing

---

## Security Changes Summary

### Critical Fixes

1. **✅ Eliminated Hardcoded Passwords**
   - Removed: `ChangeMe123!`, `admin123`, `foreman123`
   - All passwords now cryptographically secure random generated
   - 20-character passwords: letters, numbers, safe symbols

2. **✅ Secure Password Generation**
   ```bash
   generate_secure_password() {
       openssl rand -base64 32 | tr -d "=+/" | cut -c1-20
   }
   ```

3. **✅ SSH Hardening**
   - Password authentication DISABLED
   - SSH keys ONLY
   - Root login via password DISABLED
   - Configuration:
     ```
     PasswordAuthentication no
     PermitRootLogin prohibit-password
     PubkeyAuthentication yes
     ChallengeResponseAuthentication no
     ```

4. **✅ Credentials Storage**
   - Saved to: `~/.factory-vm/credentials.txt`
   - Permissions: `600` (owner read/write only)
   - Directory: `~/.factory-vm/` (chmod 700)
   - **NOT in git** (added to .gitignore)

5. **✅ Password Display**
   - Jenkins password shown ONCE at end of installation
   - Clear warning to save it
   - Credentials file location displayed

---

## What Changed

### Files Modified

1. **factory-vm/setup-factory-vm.sh**
   - Added `generate_secure_password()` function
   - Generate 3 passwords at start: root, foreman OS, Jenkins
   - Pass Jenkins password via environment variable to vm-setup.sh
   - SSH hardening configuration added
   - Credentials file creation
   - Password display in final summary
   - All hardcoded passwords removed

2. **.gitignore**
   - Added security patterns:
     - `*.token`
     - `*.password`
     - `.jenkins-*`
     - `.factory-vm/`
     - `credentials.txt`
     - `factory-passwords.*`

### Passwords Generated

| User/Service | Password Variable | Usage |
|--------------|-------------------|-------|
| Alpine root | `VM_ROOT_PASSWORD` | Emergency console access |
| Foreman OS user | `FOREMAN_OS_PASSWORD` | Emergency console access |
| Jenkins foreman user | `JENKINS_FOREMAN_PASSWORD` | Web UI login |

**Note**: SSH uses keys only. OS passwords are for emergency console access.

---

## User Experience

### During Installation

```
[INFO] Generating secure passwords...
```

*(Passwords generated silently - not shown during installation)*

### At End of Installation

```
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║          IMPORTANT: Jenkins Web Console Credentials      ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

  URL:      https://factory.local
  Username: foreman
  Password: Kx9mNz7pQw2LrT4vYhJ8

  ⚠  Save this password - it is shown only once!

  Credentials saved to: ~/.factory-vm/credentials.txt
  (Includes emergency OS passwords if needed)

  SSH uses keys only - no password needed for SSH access

✓ Factory VM setup complete!

Installation time: 17 minutes 26 seconds
```

### Credentials File Content

```
Factory VM Credentials - Mon Nov 18 12:00:00 PST 2025

=== Jenkins Web Console ===
URL:      https://factory.local
Username: foreman
Password: Kx9mNz7pQw2LrT4vYhJ8

This is the password for web UI access.
Jenkins CLI uses API token (auto-configured).

=== Emergency OS Access (SSH keys recommended) ===
root:    Zy3nMx8qRt5LpW9vKhN2
foreman: Bx6mQz4wYt7LsV2nJhP9

SSH access uses keys by default (no password needed).
Passwords are for emergency console access only.

=== Notes ===
- SSH authentication: Keys only (password auth disabled)
- Jenkins CLI: Uses API token (configured automatically)
- Web UI: Use foreman username and password above
```

---

## Security Features

### Authentication Methods

| Service | Method | Notes |
|---------|--------|-------|
| SSH to VM | **SSH keys only** | Password auth disabled |
| Jenkins Web UI | **Username + Password** | foreman / (generated password) |
| Jenkins CLI | **API Token** | Auto-configured, no password needed |
| OS Console | **Password** | Emergency only (if VM console access) |

### Password Characteristics

- **Length**: 20 characters
- **Character set**: `A-Za-z0-9` (alphanumeric)
- **Generation**: `openssl rand -base64 32` (cryptographic quality)
- **Entropy**: ~119 bits
- **Guessing difficulty**: 62^20 = ~2.1 × 10^35 combinations

### Storage Security

- **File**: `~/.factory-vm/credentials.txt`
- **Permissions**: `600` (rw-------)
- **Directory**: `~/.factory-vm/` (chmod 700)
- **Location**: User's home directory (not in project)
- **Git**: Explicitly ignored (.gitignore)

---

## Testing Plan

### Test 1: Fresh Installation
```bash
# Clean previous installation
sudo pkill -9 -f qemu-system
sudo rm -rf ~/vms/factory ~/.factory-vm

# Run installation
cd /home/jcgarcia/wip/nb/FinTechProj
./factory-vm/setup-factory-vm.sh --auto

# Verify:
# 1. Installation completes
# 2. Password is displayed at end
# 3. Credentials file exists: ls -la ~/.factory-vm/credentials.txt
# 4. File has correct permissions: should be -rw-------
```

### Test 2: SSH Authentication
```bash
# Start VM
~/vms/factory/start-factory.sh

# SSH should work with keys
ssh factory 'echo "SSH works"'

# Password auth should fail
# (Can't easily test this, but config is set)
```

### Test 3: Jenkins Web UI
```bash
# Get password from credentials file
cat ~/.factory-vm/credentials.txt

# Open browser: https://factory.local
# Login with: foreman / (password from file)
# Should succeed
```

### Test 4: Jenkins CLI
```bash
# Start VM
~/vms/factory/start-factory.sh

# Jenkins CLI should work (uses API token)
source ~/.bashrc
jenkins-factory who-am-i

# Expected: "Authenticated as: foreman"
```

### Test 5: Password Not in Git
```bash
# Check git status
git status

# Credentials file should NOT appear
# ~/.factory-vm/ should be ignored

# Search for passwords in git
git grep -i "ChangeMe123" || echo "✓ No hardcoded passwords"
git grep -i "admin123" || echo "✓ No hardcoded passwords"
git grep -i "foreman123" || echo "✓ No hardcoded passwords"
```

---

## Rollback Plan

If testing fails, we have two safety options:

### Option 1: Git Tag
```bash
git checkout v1.2.4-stable
```

### Option 2: Backup Branch
```bash
git checkout backup/v1.2.4-pre-security
```

---

## GitGuardian Alerts

**Before**: 2 alerts
1. Jenkins API token (hardcoded)
2. Username Password (ChangeMe123!, admin123, foreman123)

**After**: Should be 0 alerts
- No hardcoded passwords
- No tokens in code
- All secrets in ignored files

---

## Browser Certificate Troubleshooting

### If Browsers Show "Connection Not Secure" for https://factory.local

The installation script automatically installs Caddy CA certificates to all browsers. However, if you still see certificate errors:

#### Supported Browsers
- ✅ Firefox (all profiles)
- ✅ Chrome (all profiles + system NSS database)
- ✅ Brave (all profiles)
- ✅ Chromium (all profiles)

#### Manual Certificate Installation (if needed)

**Step 1: Get certificates from VM**
```bash
# Certificates are saved during installation to:
ls -la ~/vms/factory/caddy-root-ca.crt
ls -la ~/vms/factory/caddy-intermediate-ca.crt
```

**Step 2: For Chrome/Brave/Chromium**
```bash
# Install to system NSS database (works for all Chromium browsers)
certutil -A -d sql:$HOME/.pki/nssdb -t "CT,C,C" \
  -n "Caddy Local CA - Factory" \
  -i ~/vms/factory/caddy-root-ca.crt

certutil -A -d sql:$HOME/.pki/nssdb -t ",," \
  -n "Caddy Intermediate CA - Factory" \
  -i ~/vms/factory/caddy-intermediate-ca.crt

# Verify installation
certutil -L -d sql:$HOME/.pki/nssdb | grep Caddy
```

**Step 3: For Brave specifically**
```bash
certutil -A -d sql:$HOME/.config/BraveSoftware/Brave-Browser/Default \
  -t "CT,C,C" -n "Caddy Local CA - Factory" \
  -i ~/vms/factory/caddy-root-ca.crt

certutil -A -d sql:$HOME/.config/BraveSoftware/Brave-Browser/Default \
  -t ",," -n "Caddy Intermediate CA - Factory" \
  -i ~/vms/factory/caddy-intermediate-ca.crt
```

**Step 4: For Firefox**
```bash
# Find your Firefox profile directory
ls -d ~/.mozilla/firefox/*.default*

# Install certificate (replace PROFILE_DIR with actual path)
PROFILE_DIR="~/.mozilla/firefox/xxxxx.default-release"

certutil -A -d sql:$PROFILE_DIR -t "CT,C,C" \
  -n "Caddy Local CA - Factory" \
  -i ~/vms/factory/caddy-root-ca.crt

certutil -A -d sql:$PROFILE_DIR -t ",," \
  -n "Caddy Intermediate CA - Factory" \
  -i ~/vms/factory/caddy-intermediate-ca.crt
```

**Step 5: Restart browser**
```bash
# Close ALL browser windows completely
# Then reopen browser and navigate to https://factory.local
```

#### Trust Flag Explanation

- `CT,C,C` = Trust for **C**ertificate Authority + **T**rust SSL + **C**ertificate signing
- `,,` = No special trust (used for intermediate CAs)

#### If Certificates Still Don't Work

```bash
# Delete all Caddy certificates and reinstall
certutil -D -d sql:$HOME/.pki/nssdb -n "Caddy Local CA - Factory"
certutil -D -d sql:$HOME/.pki/nssdb -n "Caddy Intermediate CA - Factory"

# Re-run the Jenkins CLI setup script (includes certificate installation)
~/vms/factory/setup-jenkins-cli.sh
```

---

## Next Steps

1. ✅ Changes complete
2. ✅ Browser certificate installation fixed (Chrome, Brave, Firefox)
3. ⏳ Test fresh installation
4. ⏳ Verify all authentication methods
5. ⏳ Confirm GitGuardian alerts cleared
6. ⏳ Update CHANGELOG.md
7. ⏳ Commit and push (v1.2.5)

---

## Implementation Notes

### Why Environment Variables for Jenkins Password?

Instead of modifying the heredoc (which would require escaping all variables), we:
1. Pass password as environment variable to vm-setup.sh
2. Script reads from `$JENKINS_ADMIN_PASSWORD`
3. Cleaner, more secure (not visible in process list when passed properly)

### Why Three Passwords?

1. **VM Root**: Alpine installation requires root password
2. **Foreman OS**: Separate user password (security best practice)
3. **Jenkins Foreman**: Web UI access (different from OS password)

### Why Disable Password Auth?

- SSH keys are more secure than passwords
- Prevents brute force attacks
- Industry best practice
- Passwords only for emergency console access

---

*Document created: November 18, 2025*  
*Next: Test installation with new security features*
