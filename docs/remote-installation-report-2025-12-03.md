# Factory VM Remote Installation Report

**Date**: December 3, 2025  
**Test Server**: cognito (x86_64 Ubuntu 24.04.3 LTS)  
**Installation Method**: One-liner installer via GitHub  
**Emulation**: ARM64 guest via QEMU TCG on x86_64 host

## Executive Summary

Successfully installed Factory VM on a remote x86_64 server using the public GitHub one-liner installer. The installation completed in **22 minutes 32 seconds** with all components working correctly, including the Docker socket permission fix.

## Installation Command

```bash
curl -fsSL https://raw.githubusercontent.com/jcgarcia/factory-vm/main/install.sh | bash
```

## Installation Results

| Component | Status | Version/Details |
|-----------|--------|-----------------|
| Alpine Linux VM | ✅ Installed | Alpine 3.19 (ARM64 via TCG) |
| Docker | ✅ Running | 25.0.5 |
| Docker Socket | ✅ Fixed | `srw-rw-rw-` (666 permissions) |
| Jenkins | ✅ Running | 2.528.2 (LTS) |
| Caddy | ✅ Running | 2.7.6 (HTTPS reverse proxy) |
| kubectl | ✅ Installed | v1.34.2 |
| Helm | ✅ Installed | v4.0.1 |
| Terraform | ✅ Installed | v1.14.0 |
| AWS CLI | ✅ Installed | 2.15.14 |
| jcscripts | ✅ Installed | 42 scripts |

## Installation Time Breakdown

- **Total Time**: 22m 32s
- **Note**: TCG emulation (ARM64 on x86_64) adds overhead compared to native ARM64

## Accessing Jenkins from a Remote Browser

After installing Factory VM on a remote server, additional steps are needed to access Jenkins from your local browser with proper HTTPS certificates.

### Step 1: Install Remote Certificates

Use the `install-remote-certs.sh` script to download and install the Factory VM CA certificates on your local machine:

```bash
# From the FactoryVM-wip/tools directory (or public distro tools/)
./install-remote-certs.sh <ssh-host>

# Example:
./install-remote-certs.sh lcognito
```

The script will:
1. Connect to the remote server via SSH
2. Download the Caddy CA certificates from the Factory VM
3. Install them to your system's trust store
4. Install them to browser certificate databases (Firefox, Chrome, etc.)
5. Display the remote server's IP address for `/etc/hosts`

**Sample Output:**
```
╔══════════════════════════════════════════════════════════╗
║  Factory VM Remote Certificate Installer                 ║
╚══════════════════════════════════════════════════════════╝

[INFO] Testing SSH connection to lcognito...
[✓] SSH connection OK
[INFO] Checking for Factory VM certificates on remote server...
[✓] Certificates found on remote server
[INFO] Downloading certificates from lcognito...
[✓] Certificates downloaded to /home/user/.factory-certs
[INFO] Detected OS type: debian
[INFO] Installing certificates to system trust store...
[✓] Certificates installed to system trust store
[INFO] Installing to browser certificate databases...
[✓] Certificates installed to 4 browser profile(s)

╔══════════════════════════════════════════════════════════╗
║  Certificate Installation Complete!                      ║
╚══════════════════════════════════════════════════════════╝

[✓] Certificates installed successfully

Next steps:

1. Add this line to your /etc/hosts file:

   192.168.8.105    factory.local

   Run this command:
   echo '192.168.8.105    factory.local' | sudo tee -a /etc/hosts

2. Restart your browser to apply certificate changes

3. Access Jenkins at: https://factory.local
```

### Step 2: Update /etc/hosts

Add the remote server's IP address to your local `/etc/hosts` file:

```bash
# Replace with the IP shown by the script
echo '192.168.8.105    factory.local' | sudo tee -a /etc/hosts
```

### Step 3: Restart Browser

Restart your browser to load the new certificates.

### Step 4: Access Jenkins

Navigate to: **https://factory.local**

The Jenkins login page should load without any certificate warnings.

## Credentials

After installation, credentials are saved to `~/vms/factory/credentials.txt` on the remote server:

```bash
ssh <remote-host> "cat ~/vms/factory/credentials.txt"
```

**Example credentials** (generated during this test):
- **Jenkins URL**: https://factory.local
- **Username**: foreman
- **Password**: (auto-generated, see credentials.txt)

## Verified Functionality

### Docker Socket Permissions
```bash
$ ssh lcognito "ssh factory 'ls -la /var/run/docker.sock'"
srw-rw-rw- 1 root docker 0 Dec  3 11:49 /var/run/docker.sock
```
✅ Permissions are 666 - Jenkins Docker agents will work correctly.

### Running Services
```bash
$ ssh lcognito "ssh factory 'rc-service docker status; rc-service caddy status'"
 * status: started
 * status: started
```

### Jenkins Container
```bash
$ ssh lcognito "ssh factory 'docker ps'"
CONTAINER ID   IMAGE                       STATUS          PORTS
19c710f361ad   jenkins/jenkins:lts-jdk21   Up 11 minutes   0.0.0.0:8080->8080/tcp, 0.0.0.0:50000->50000/tcp
```

### Caddy HTTPS Configuration
```bash
$ ssh lcognito "ssh factory 'cat /etc/caddy/Caddyfile'"
factory.local {
    reverse_proxy localhost:8080
    tls internal
}
```

## Supported Operating Systems for Certificate Installation

The `install-remote-certs.sh` script supports:

| OS | Trust Store Location | Update Command |
|----|---------------------|----------------|
| Ubuntu/Debian | `/usr/local/share/ca-certificates/` | `update-ca-certificates` |
| RHEL/Fedora/CentOS | `/etc/pki/ca-trust/source/anchors/` | `update-ca-trust` |
| Arch Linux | System trust anchors | `trust anchor --store` |
| Alpine Linux | `/usr/local/share/ca-certificates/` | `update-ca-certificates` |
| macOS | System Keychain | `security add-trusted-cert` |

Browser certificate databases (NSS) are also updated for:
- Firefox (all profiles)
- Chrome/Chromium
- Brave
- Microsoft Edge

## Comparison: Local vs Remote Installation

| Metric | Local (Laptop) | Remote (Cognito) |
|--------|----------------|------------------|
| Host OS | Ubuntu 24.04 x86_64 | Ubuntu 24.04 x86_64 |
| VM Emulation | ARM64 via QEMU TCG | ARM64 via QEMU TCG |
| Installation Time | 18m 13s | 22m 32s |
| Docker Socket Fix | ✅ Working | ✅ Working |
| Jenkins Startup | ~60s | ~60s |
| All Tests | PASS | PASS |

**Note**: Both installations use TCG emulation (ARM64 guest on x86_64 host). The time difference is due to network/hardware variations between the two systems.

## Files Created on Remote Server

```
~/vms/factory/
├── alpine.qcow2          # VM disk image (2.0G)
├── alpine-data.qcow2     # Persistent data disk (5.1G)
├── alpine-virt.iso       # Alpine installer ISO
├── credentials.txt       # Jenkins/VM credentials
├── caddy-root-ca.crt     # Root CA certificate
├── caddy-intermediate-ca.crt  # Intermediate CA certificate
├── start-factory.sh      # Start VM script
├── stop-factory.sh       # Stop VM script
└── vm.pid               # Running VM process ID
```

## Conclusion

The Factory VM remote installation test was successful. Key findings:

1. **One-liner installer works on remote servers** - No modifications needed
2. **Docker socket fix verified** - Permissions are correctly set to 666
3. **HTTPS access from remote browser** - Works with the new `install-remote-certs.sh` script
4. **Consistent performance** - Both local and remote installations completed in similar times (~18-22 minutes)
5. **All tools functional** - Docker, Jenkins, kubectl, Helm, Terraform, AWS CLI all working

The checkpoint `checkpoint-phase2-docker-fix` (commit 5b6215c) is confirmed working on both local and remote x86_64 systems.
