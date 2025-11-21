# Factory VM v2.0 - Caching & SSH-Based Installation Architecture

## Overview

Version 2.0 will move from a heredoc-based installation script to a host-controlled, SSH-based installation with intelligent caching. This provides:

- ✅ **Real-time progress visibility** - All output streams to host terminal
- ✅ **Smart caching** - Download once, install many times
- ✅ **Faster subsequent installations** - Use cached files (10x faster)
- ✅ **Bandwidth savings** - Reuse downloaded files across installations
- ✅ **Offline capable** - Once cached, can install without internet
- ✅ **Better debugging** - Run individual commands to troubleshoot
- ✅ **Version management** - Cache organized by detected versions

## Current vs. V2.0 Comparison

### Current (v1.x)
```
Host                                    VM
────                                    ──
1. Detect versions                      
2. Create vm-setup.sh (heredoc)         
3. SCP vm-setup.sh → VM                 
4. SSH: bash vm-setup.sh                → Buffered output, no visibility
                                        → Downloads inside VM
                                        → Installs inside VM
                                        → Plugins via docker exec
```

**Issues:**
- ❌ Output buffered, user sees nothing
- ❌ Downloads repeated on every install
- ❌ Slow on poor connections
- ❌ Hard to debug failures
- ❌ Jenkins plugins installed inside VM

### V2.0 Architecture
```
Host                                    VM
────                                    ──
1. Check git repo updates (git pull)    
2. Detect tool versions                 
3. Download & cache tools (parallel)    
   - Check cache/terraform/terraform_${VER}
   - Download if missing
   - Same for kubectl, helm, jenkins plugins
4. Start VM, wait for SSH               → Alpine boots
5. SCP cached files → VM                → Receives files (fast, local)
6. SSH: install commands (real-time)    → Extract, move, configure
   - ssh: unzip terraform...            → [real-time output]
   - ssh: mv kubectl...                 → [real-time output]
7. Download jenkins-cli.jar to HOST     
8. SSH tunnel: localhost:8080           → Jenkins running
9. Install plugins FROM HOST            → [real-time output]
   - java -jar jenkins-cli.jar install-plugin git
10. SCP jenkins-cli.jar → VM            → For user convenience
```

**Benefits:**
- ✅ Real-time output on host terminal
- ✅ First install: same speed, subsequent: 10x faster
- ✅ Offline installation after first download
- ✅ Easy debugging (can run individual SSH commands)
- ✅ Better visibility for end users

## Cache Directory Structure

```
~/vms/factory/
├── cache/                              # New in v2.0
│   ├── alpine/                         # Alpine ISOs (already done)
│   │   └── alpine-virt-3.22.2-aarch64.iso
│   ├── terraform/
│   │   └── terraform_1.14.0_linux_arm64.zip
│   ├── kubectl/
│   │   └── kubectl_1.34.2
│   ├── helm/
│   │   └── helm-v4.0.0-linux-arm64.tar.gz
│   ├── aws-cli/
│   │   └── awscli-exe-linux-aarch64.zip
│   ├── jenkins/
│   │   ├── jenkins-cli.jar
│   │   └── plugins/
│   │       ├── git.jpi
│   │       ├── docker-plugin.jpi
│   │       ├── workflow-aggregator.jpi
│   │       └── ... (25 total)
│   └── versions.json                   # Track cached versions
├── isos/                               # Existing
│   └── alpine-virt-3.22.2-aarch64.iso
├── factory.qcow2
├── factory-data.qcow2
└── vm-setup.sh                         # Will be removed in v2.0
```

## Implementation Plan

### Phase 1: Download & Caching Functions

```bash
# New functions to add to setup-factory-vm.sh

CACHE_DIR="${VM_DIR}/cache"

download_and_cache_terraform() {
    local version="$1"
    local cache_file="${CACHE_DIR}/terraform/terraform_${version}_linux_arm64.zip"
    
    if [ -f "$cache_file" ]; then
        log_info "Terraform ${version} already cached"
        return 0
    fi
    
    log_info "Downloading Terraform ${version}..."
    mkdir -p "${CACHE_DIR}/terraform"
    curl -L "https://releases.hashicorp.com/terraform/${version}/terraform_${version}_linux_arm64.zip" \
        -o "$cache_file"
    log_success "Terraform cached"
}

download_and_cache_kubectl() {
    local version="$1"
    local cache_file="${CACHE_DIR}/kubectl/kubectl_${version}"
    
    if [ -f "$cache_file" ]; then
        log_info "kubectl ${version} already cached"
        return 0
    fi
    
    log_info "Downloading kubectl ${version}..."
    mkdir -p "${CACHE_DIR}/kubectl"
    curl -L "https://dl.k8s.io/release/v${version}/bin/linux/arm64/kubectl" \
        -o "$cache_file"
    chmod +x "$cache_file"
    log_success "kubectl cached"
}

download_and_cache_helm() {
    local version="$1"
    local cache_file="${CACHE_DIR}/helm/helm-v${version}-linux-arm64.tar.gz"
    
    if [ -f "$cache_file" ]; then
        log_info "Helm ${version} already cached"
        return 0
    fi
    
    log_info "Downloading Helm ${version}..."
    mkdir -p "${CACHE_DIR}/helm"
    curl -L "https://get.helm.sh/helm-v${version}-linux-arm64.tar.gz" \
        -o "$cache_file"
    log_success "Helm cached"
}

download_and_cache_jenkins_plugins() {
    local plugins_file="$1"  # Path to plugins.txt
    
    mkdir -p "${CACHE_DIR}/jenkins/plugins"
    
    log_info "Downloading Jenkins plugins to cache..."
    while IFS= read -r plugin || [ -n "$plugin" ]; do
        # Skip comments and empty lines
        [[ "$plugin" =~ ^#.*$ ]] && continue
        [[ -z "$plugin" ]] && continue
        
        # Remove :latest suffix if present
        plugin_name=$(echo "$plugin" | sed 's/:latest$//')
        cache_file="${CACHE_DIR}/jenkins/plugins/${plugin_name}.jpi"
        
        if [ -f "$cache_file" ]; then
            log_info "  ${plugin_name} already cached"
        else
            log_info "  Downloading ${plugin_name}..."
            # Download from Jenkins update center
            curl -sL "https://updates.jenkins.io/latest/${plugin_name}.hpi" \
                -o "$cache_file"
        fi
    done < "$plugins_file"
    
    log_success "All Jenkins plugins cached"
}

cache_all_tools() {
    log "Downloading and caching installation files..."
    log_info "First-time downloads will be cached for faster subsequent installations"
    
    # Detect versions (already implemented)
    TERRAFORM_VERSION=$(get_latest_terraform_version)
    KUBECTL_VERSION=$(get_latest_kubectl_version)
    HELM_VERSION=$(get_latest_helm_version)
    
    log_info "Tool versions:"
    log_info "  Terraform: ${TERRAFORM_VERSION}"
    log_info "  kubectl: ${KUBECTL_VERSION}"
    log_info "  Helm: ${HELM_VERSION}"
    
    # Download in parallel (background jobs)
    download_and_cache_terraform "$TERRAFORM_VERSION" &
    download_and_cache_kubectl "$KUBECTL_VERSION" &
    download_and_cache_helm "$HELM_VERSION" &
    
    # Wait for parallel downloads
    wait
    
    # Download Jenkins plugins (sequential, or could be parallel)
    download_and_cache_jenkins_plugins "${SCRIPT_DIR}/jenkins/plugins.txt"
    
    log_success "All tools cached and ready for installation"
}
```

### Phase 2: SSH-Based Installation Functions

```bash
install_terraform_via_ssh() {
    local version="$1"
    local cache_file="${CACHE_DIR}/terraform/terraform_${version}_linux_arm64.zip"
    
    log_info "Installing Terraform ${version}..."
    
    # Copy from cache to VM
    scp -i "$VM_SSH_PRIVATE_KEY" -P "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$cache_file" root@localhost:/tmp/
    
    # Install via SSH (real-time output)
    ssh -tt -i "$VM_SSH_PRIVATE_KEY" -p "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        root@localhost << 'EOF'
cd /tmp
unzip -q terraform_*_linux_arm64.zip
mv terraform /usr/local/bin/
rm terraform_*_linux_arm64.zip
terraform version
EOF
    
    log_success "Terraform installed"
}

install_kubectl_via_ssh() {
    local version="$1"
    local cache_file="${CACHE_DIR}/kubectl/kubectl_${version}"
    
    log_info "Installing kubectl ${version}..."
    
    # Copy directly to destination (already executable)
    scp -i "$VM_SSH_PRIVATE_KEY" -P "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$cache_file" root@localhost:/usr/local/bin/kubectl
    
    # Verify
    ssh -tt -i "$VM_SSH_PRIVATE_KEY" -p "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        root@localhost 'kubectl version --client'
    
    log_success "kubectl installed"
}

install_helm_via_ssh() {
    local version="$1"
    local cache_file="${CACHE_DIR}/helm/helm-v${version}-linux-arm64.tar.gz"
    
    log_info "Installing Helm ${version}..."
    
    # Copy and install
    scp -i "$VM_SSH_PRIVATE_KEY" -P "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$cache_file" root@localhost:/tmp/
    
    ssh -tt -i "$VM_SSH_PRIVATE_KEY" -p "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        root@localhost << 'EOF'
cd /tmp
tar -zxf helm-v*-linux-arm64.tar.gz
mv linux-arm64/helm /usr/local/bin/
rm -rf linux-arm64 helm-v*-linux-arm64.tar.gz
helm version
EOF
    
    log_success "Helm installed"
}
```

### Phase 3: Jenkins Plugin Installation from Host

```bash
install_jenkins_plugins_from_host() {
    local plugins_file="$1"
    
    log_info "Installing Jenkins plugins from host..."
    
    # Wait for Jenkins to be ready (check HTTP endpoint)
    log_info "Waiting for Jenkins to be ready..."
    for i in {1..60}; do
        if ssh -i "$VM_SSH_PRIVATE_KEY" -p "$VM_SSH_PORT" \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            root@localhost 'curl -s http://localhost:8080/login >/dev/null 2>&1'; then
            log_success "Jenkins is ready"
            break
        fi
        if [ $i -eq 60 ]; then
            log_error "Jenkins did not start in time"
            return 1
        fi
        sleep 2
    done
    
    # Download jenkins-cli.jar to HOST
    log_info "Downloading jenkins-cli.jar to host..."
    mkdir -p ~/.java/jars
    ssh -i "$VM_SSH_PRIVATE_KEY" -p "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        root@localhost 'docker exec jenkins cat /var/jenkins_home/war/WEB-INF/jenkins-cli.jar' \
        > ~/.java/jars/jenkins-cli-factory.jar
    
    # Setup SSH tunnel for jenkins-cli (background)
    ssh -i "$VM_SSH_PRIVATE_KEY" -p "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -L 8080:localhost:8080 -N root@localhost &
    local tunnel_pid=$!
    sleep 2
    
    # Install plugins one-by-one from HOST using cached .jpi files
    local plugin_count=$(grep -v '^#' "$plugins_file" | grep -v '^$' | wc -l)
    local plugin_num=0
    
    log_info "Installing ${plugin_count} plugins..."
    
    while IFS= read -r plugin || [ -n "$plugin" ]; do
        [[ "$plugin" =~ ^#.*$ ]] && continue
        [[ -z "$plugin" ]] && continue
        
        plugin_name=$(echo "$plugin" | sed 's/:latest$//')
        plugin_num=$((plugin_num + 1))
        
        echo -n "  [$plugin_num/$plugin_count] Installing $plugin_name..."
        
        # Install from cached file using jenkins-cli
        if java -jar ~/.java/jars/jenkins-cli-factory.jar \
            -s http://localhost:8080/ \
            -auth admin:"${JENKINS_FOREMAN_PASSWORD}" \
            install-plugin "${CACHE_DIR}/jenkins/plugins/${plugin_name}.jpi" \
            2>/dev/null; then
            echo " ✓"
        else
            echo " ⚠ (timeout or failed)"
        fi
    done < "$plugins_file"
    
    # Kill SSH tunnel
    kill $tunnel_pid 2>/dev/null
    
    # Restart Jenkins to activate plugins
    log_info "Restarting Jenkins to activate plugins..."
    ssh -i "$VM_SSH_PRIVATE_KEY" -p "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        root@localhost 'docker restart jenkins'
    
    # Also copy jenkins-cli.jar to VM for user convenience
    log_info "Installing jenkins-cli.jar in VM for user access..."
    ssh -i "$VM_SSH_PRIVATE_KEY" -p "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        root@localhost 'mkdir -p /usr/local/share/jenkins'
    scp -i "$VM_SSH_PRIVATE_KEY" -P "$VM_SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ~/.java/jars/jenkins-cli-factory.jar \
        root@localhost:/usr/local/share/jenkins/jenkins-cli.jar
    
    log_success "Jenkins plugins installed from host"
}
```

### Phase 4: Main Installation Flow (Refactored)

```bash
# New main flow for v2.0

main_installation() {
    # Phase 1: Pre-download and cache (on host)
    cache_all_tools
    
    # Phase 2: Alpine installation (existing, unchanged)
    install_alpine
    
    # Phase 3: Start VM and wait for SSH (existing, unchanged)
    start_vm_and_wait_for_ssh
    
    # Phase 4: Install base packages via SSH
    install_base_packages_via_ssh
    
    # Phase 5: Install Docker via SSH
    install_docker_via_ssh
    
    # Phase 6: Install Caddy via SSH
    install_caddy_via_ssh
    
    # Phase 7: Install Kubernetes tools via SSH (from cache)
    install_kubectl_via_ssh "$KUBECTL_VERSION"
    install_helm_via_ssh "$HELM_VERSION"
    
    # Phase 8: Install Terraform via SSH (from cache)
    install_terraform_via_ssh "$TERRAFORM_VERSION"
    
    # Phase 9: Install Jenkins and wait for startup
    install_jenkins_via_ssh
    
    # Phase 10: Install Jenkins plugins from HOST (real-time)
    install_jenkins_plugins_from_host "${SCRIPT_DIR}/jenkins/plugins.txt"
    
    # Phase 11: Final configuration
    configure_jenkins_via_ssh
    
    log_success "Installation complete!"
}
```

## Migration Path

### Step 1: Add caching to current version (minimal change)
- Add `cache_all_tools()` function
- Call before `create_vm_setup_script()`
- Keep heredoc approach for now

### Step 2: Add `-tt` flag for real-time output
- Already implemented in current uncommitted changes
- Fixes buffering issue

### Step 3: Refactor to SSH-based installation (v2.0)
- Replace `create_vm_setup_script()` with individual `install_*_via_ssh()` functions
- Remove heredoc entirely
- Use cached files for all installations

### Step 4: Optimize with parallel operations
- Download tools in parallel (already shown above)
- Could install independent components in parallel

## Benefits Summary

### Speed Improvements
- **First installation**: Same as current (must download)
- **Second installation**: 10x faster (uses cache)
- **Offline**: Can install without internet after first run

### User Experience
- **Real-time progress**: See every step as it happens
- **Better error messages**: Know exactly which step failed
- **Easy debugging**: Can run individual SSH commands manually

### Maintenance
- **Easier to update**: Add new tools without complex heredoc escaping
- **Easier to test**: Test individual installation functions
- **Better code organization**: Each tool has its own install function

### Resource Efficiency
- **Bandwidth**: Download once, use many times
- **Time**: Cached files = faster installations
- **Disk**: ~500MB cache vs repeatedly downloading GB of data

## Version Tracking

Create `~/vms/factory/cache/versions.json`:
```json
{
  "alpine": "3.22.2",
  "terraform": "1.14.0",
  "kubectl": "1.34.2",
  "helm": "4.0.0",
  "jenkins_plugins": {
    "git": "5.0.0",
    "docker-plugin": "1.2.9",
    "workflow-aggregator": "2.7"
  },
  "last_updated": "2025-11-20T21:30:00Z"
}
```

This allows:
- Check if cache is outdated
- Show user what versions are cached
- Clean old versions automatically

## Future Enhancements

1. **Cache cleanup**: Remove old versions automatically
2. **Parallel installations**: Install independent tools simultaneously
3. **Resume capability**: If installation fails, resume from last successful step
4. **Cache sharing**: Multiple users/machines share cache via NFS or sync
5. **Integrity checking**: Verify checksums of cached files
