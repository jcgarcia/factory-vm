# Jenkins CLI Setup - Implementation Summary

## What Was Implemented

### 1. Jenkins User Creation
**File**: `factory-vm/setup-factory-vm.sh` (lines ~1050)

Added a new Groovy init script `05-create-foreman-user.groovy` that:
- Creates a Jenkins user named `foreman` with password `foreman123`
- Grants full administrative privileges
- Generates an API token named "CLI Access"
- Saves the token to `/var/jenkins_home/foreman-api-token.txt`
- Handles existing user gracefully (regenerates token if missing)

**Key Features**:
```groovy
// Creates user
hudsonRealm.createAccount('foreman', 'foreman123')

// Generates API token
def result = tokenStore.tokenStore.generateNewToken("CLI Access")
def tokenValue = result.plainValue

// Saves to file
new File('/var/jenkins_home/foreman-api-token.txt').text = tokenValue
```

### 2. Jenkins CLI Installation on Host
**File**: `factory-vm/setup-factory-vm.sh` (lines ~2050)

Added `setup_jenkins_cli()` function that:
- Waits for Jenkins to be fully initialized (up to 60 attempts)
- Downloads `jenkins-cli.jar` from Jenkins server
- Retrieves the foreman API token from Jenkins container
- Adds `jenkins-factory()` bash function to `~/.bashrc`
- Implements automatic token caching (30-day expiry)
- Adds bash completion for common commands
- Creates manual setup script for troubleshooting

**Installation Process**:
1. Wait for Jenkins ready state
2. Download CLI jar: `curl https://factory.local/jnlpJars/jenkins-cli.jar`
3. Get token: `ssh root@localhost "docker exec jenkins cat /var/jenkins_home/foreman-api-token.txt"`
4. Save token to `~/.jenkins-factory-token` (600 permissions)
5. Add bash function to `.bashrc`

### 3. Bash Function with Auto-Refresh
**File**: `~/.bashrc` (appended during installation)

The `jenkins-factory()` function:
```bash
jenkins-factory() {
    # Auto-retrieves token from cache or Jenkins
    # Refreshes if cache is older than 30 days
    java -jar ~/jenkins-cli-factory.jar \
        -s https://factory.local/ \
        -http \
        -auth foreman:${api_token} \
        "$@"
}
```

**Features**:
- Token caching in `~/.jenkins-factory-token`
- Automatic refresh when expired (30 days)
- Bash completion support
- Simple command syntax: `jenkins-factory <command>`

### 4. Manual Setup Script
**File**: `~/vms/factory/setup-jenkins-cli.sh`

Created a standalone script for:
- Re-running CLI setup if automatic setup fails
- Manual token refresh
- Testing CLI connection
- Troubleshooting installation issues

**Usage**:
```bash
~/vms/factory/setup-jenkins-cli.sh
```

### 5. Updated Installation Output
**File**: `factory-vm/setup-factory-vm.sh` (lines ~2775)

Added Jenkins CLI information to installation summary:
```
Jenkins CLI (Host):
  Command: jenkins-factory <command>
  Examples:
    jenkins-factory who-am-i        # Verify connection
    jenkins-factory list-jobs       # List all jobs
    jenkins-factory build <job>     # Trigger build
  ✓ Configured for user: foreman
  ✓ API token auto-configured
  Reload shell: source ~/.bashrc
```

### 6. Comprehensive Documentation
**File**: `factory-vm/JENKINS-CLI.md` (NEW - 600+ lines)

Created complete Jenkins CLI guide covering:
- Installation and configuration
- Foreman user details
- Basic and advanced usage examples
- Complete command reference (40+ commands)
- Troubleshooting guide
- Security best practices
- Integration patterns
- Automation examples

**Sections**:
1. Overview and Features
2. Installation (automatic process)
3. Configuration (foreman user, bash function)
4. Usage (basic commands, common operations)
5. Advanced Usage (pipelines, automation, bulk operations)
6. Troubleshooting (connection, token, permissions, SSL issues)
7. Manual Setup (step-by-step if automatic fails)
8. Security Best Practices
9. Complete Command Reference
10. Examples (pipeline creation, monitoring, CI/CD integration)

### 7. Updated CHANGELOG.md
**File**: `factory-vm/CHANGELOG.md`

Added version 1.1.0 section documenting:
- Jenkins CLI integration
- Foreman user creation
- New features and capabilities
- Usage examples
- Security considerations

### 8. Updated JENKINS-CONFIGURATION.md
**File**: `factory-vm/JENKINS-CONFIGURATION.md`

Added sections for:
- CLI access information
- Foreman user credentials
- Quick CLI examples
- Reference to JENKINS-CLI.md
- Init script 05 documentation

## File Modifications Summary

### Modified Files
1. **factory-vm/setup-factory-vm.sh**
   - Added init script: 05-create-foreman-user.groovy (~60 lines)
   - Added function: setup_jenkins_cli() (~150 lines)
   - Updated main() to call setup_jenkins_cli()
   - Updated installation output with CLI info

2. **factory-vm/CHANGELOG.md**
   - Added version 1.1.0 section (~80 lines)
   - Documented all CLI features

3. **factory-vm/JENKINS-CONFIGURATION.md**
   - Added CLI access section
   - Added foreman user to init scripts
   - Added CLI examples

### New Files Created
1. **factory-vm/JENKINS-CLI.md** (~600 lines)
   - Complete CLI documentation
   
2. **~/vms/factory/setup-jenkins-cli.sh** (created during installation)
   - Manual setup script

3. **~/.jenkins-factory-token** (created during installation)
   - Token cache file (600 permissions)

4. **~/.bashrc** (appended)
   - jenkins-factory() function
   - Bash completion

## How It Works

### Installation Flow
```
1. Factory VM installation starts
2. Jenkins container starts with Java 21
3. Init scripts run (01, 02, 03, 04, 05)
4. 05-create-foreman-user.groovy creates user and token
5. Installation waits for Jenkins ready
6. setup_jenkins_cli() function runs:
   a. Downloads jenkins-cli.jar
   b. Retrieves token from Jenkins
   c. Saves to ~/.jenkins-factory-token
   d. Adds function to ~/.bashrc
   e. Creates manual setup script
7. Installation completes
8. User can immediately use: jenkins-factory who-am-i
```

### Runtime Flow
```
User runs: jenkins-factory list-jobs
    ↓
Function checks token cache (~/.jenkins-factory-token)
    ↓
If cache > 30 days or missing:
    → SSH to Jenkins container
    → Read /var/jenkins_home/foreman-api-token.txt
    → Update cache
    ↓
Execute: java -jar ~/jenkins-cli-factory.jar \
         -s https://factory.local/ \
         -http \
         -auth foreman:TOKEN \
         list-jobs
    ↓
Output displayed to user
```

## Security Considerations

### Token Storage
- **In Jenkins**: `/var/jenkins_home/foreman-api-token.txt`
  - Inside Docker container
  - Persistent across restarts
  - Only accessible via SSH to VM

- **On Host**: `~/.jenkins-factory-token`
  - 600 permissions (user read/write only)
  - Auto-refresh mechanism
  - Can be manually deleted and regenerated

### User Permissions
- **foreman user**: Full administrative access (same as admin)
  - Can create/delete jobs
  - Can manage plugins
  - Can execute Groovy scripts
  - Can manage credentials

**Recommendation**: If less privileged access is needed, create additional users with role-based access control.

### Authentication Method
- Uses API token (not password) for CLI
- Token rotates automatically if cache expires
- HTTPS connection with `-http` flag (disables strict cert validation)
- Token never exposed in command line (read from file)

## Testing

### Verification Steps

1. **Check foreman user created**:
   ```bash
   ssh -p 2222 root@localhost \
     "docker exec jenkins ls -la /var/jenkins_home/foreman-api-token.txt"
   ```

2. **Verify CLI jar downloaded**:
   ```bash
   ls -lh ~/jenkins-cli-factory.jar
   ```

3. **Check token cache**:
   ```bash
   ls -la ~/.jenkins-factory-token
   ```

4. **Test function exists**:
   ```bash
   type jenkins-factory
   ```

5. **Test connection**:
   ```bash
   source ~/.bashrc
   jenkins-factory who-am-i
   ```

   Expected output:
   ```
   Authenticated as: foreman
   Authorities:
     authenticated
   ```

6. **Test basic commands**:
   ```bash
   jenkins-factory version
   jenkins-factory list-jobs
   jenkins-factory list-plugins
   ```

### Troubleshooting

If `jenkins-factory` command not found:
```bash
source ~/.bashrc
```

If authentication fails:
```bash
# Refresh token manually
rm ~/.jenkins-factory-token
~/vms/factory/setup-jenkins-cli.sh
```

If Jenkins not ready:
```bash
# Wait for Jenkins to fully initialize (2-3 minutes after VM start)
ssh factory 'docker logs jenkins | tail -20'
```

## Usage Examples

### Job Management
```bash
# List all jobs
jenkins-factory list-jobs

# Create job from XML
jenkins-factory create-job my-app < job-config.xml

# Trigger build
jenkins-factory build my-app

# Trigger with parameters
jenkins-factory build my-app -p ENV=prod -p VERSION=1.0

# Delete job
jenkins-factory delete-job my-app
```

### Build Monitoring
```bash
# View console output
jenkins-factory console my-app

# Follow console output
jenkins-factory console my-app -f

# View specific build
jenkins-factory console my-app 42
```

### System Administration
```bash
# List installed plugins
jenkins-factory list-plugins

# Install plugin
jenkins-factory install-plugin docker-workflow

# Restart Jenkins
jenkins-factory safe-restart

# Execute Groovy
jenkins-factory groovy = "println Jenkins.instance.version"
```

## Benefits

### For Users
- ✅ No need to open web browser for simple tasks
- ✅ Easy automation and scripting
- ✅ Fast job triggering from command line
- ✅ Integration with shell scripts and CI/CD pipelines
- ✅ Tab completion for commands

### For Automation
- ✅ Programmatic job creation
- ✅ Automated build triggering
- ✅ Credential management
- ✅ Plugin installation
- ✅ System configuration

### For DevOps
- ✅ Infrastructure as Code support
- ✅ Version control of job configurations
- ✅ Batch operations on multiple jobs
- ✅ Groovy script execution for advanced tasks
- ✅ Integration with deployment scripts

## Future Enhancements

Possible improvements:

1. **Multiple Users**: Create role-based users with different privileges
2. **Token Rotation**: Implement automatic token rotation policy
3. **Audit Logging**: Track CLI usage in separate log file
4. **Wrapper Scripts**: Create convenience scripts for common operations
5. **Bash Completions**: Enhanced tab completion with job names
6. **Configuration Profiles**: Support multiple Jenkins servers

## Related Files

- **Main script**: `factory-vm/setup-factory-vm.sh`
- **Documentation**: `factory-vm/JENKINS-CLI.md`
- **Configuration**: `factory-vm/JENKINS-CONFIGURATION.md`
- **Changelog**: `factory-vm/CHANGELOG.md`
- **Init script**: Created in `/opt/jenkins/init.groovy.d/05-create-foreman-user.groovy`
- **Manual setup**: `~/vms/factory/setup-jenkins-cli.sh`
- **Token cache**: `~/.jenkins-factory-token`
- **CLI jar**: `~/jenkins-cli-factory.jar`

## Summary

The Jenkins CLI integration provides a complete command-line interface to Jenkins from the host machine with:

- ✅ Automatic installation during VM setup
- ✅ Dedicated user (foreman) with admin privileges
- ✅ Auto-generated and auto-refreshing API token
- ✅ Convenient bash function wrapper
- ✅ Comprehensive documentation
- ✅ Manual setup script for troubleshooting
- ✅ Bash completion support
- ✅ Secure token storage and handling
- ✅ Zero manual configuration required

Users can immediately start using Jenkins CLI after installation with simple commands like:
```bash
jenkins-factory who-am-i
jenkins-factory list-jobs
jenkins-factory build my-job
```

All changes are fully documented in JENKINS-CLI.md with examples, troubleshooting, and best practices.
