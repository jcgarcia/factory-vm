# Jenkins CLI Configuration

## Overview

The Factory VM includes a fully configured Jenkins CLI (Command-Line Interface) that allows you to interact with Jenkins from your host machine without needing to use the web UI. This is especially useful for automation, scripting, and quick operations.

## Features

- ✅ **Pre-configured** - Works out of the box after installation
- ✅ **Secure** - Uses API token authentication over HTTPS
- ✅ **Convenient** - Simple bash function wrapper
- ✅ **Auto-updating** - Token refreshes automatically when needed
- ✅ **Tab completion** - Bash completion for common commands
- ✅ **Foreman user** - Dedicated user with administrative privileges

## Installation

The Jenkins CLI is automatically installed and configured during Factory VM setup. The installation process:

1. Downloads `jenkins-cli.jar` from the Jenkins server
2. Creates the `foreman` user in Jenkins with administrative privileges
3. Generates an API token for the foreman user
4. Adds the `jenkins-factory()` bash function to `~/.bashrc`
5. Configures automatic token refresh

## Configuration

### Foreman User

A dedicated Jenkins user named `foreman` is created with the following properties:

| Property | Value |
|----------|-------|
| **Username** | `foreman` |
| **Password** | `use getsecrets to retrieve the password` |
| **Permissions** | Full administrative access |
| **API Token** | Auto-generated during installation |
| **Token Name** | `CLI Access` |
| **Token Location** | `/var/jenkins_home/foreman-api-token.txt` (in Jenkins container) |

The API token is stored securely:
- **In Jenkins**: `/var/jenkins_home/foreman-api-token.txt`
- **On Host**: `~/.jenkins-factory-token` (600 permissions)

### Bash Function

The `jenkins-factory()` function is added to your `~/.bashrc`:

```bash
jenkins-factory() {
    # Automatically retrieves and caches the API token
    # Refreshes token if cache is older than 30 days
    java -jar ~/jenkins-cli-factory.jar \
        -s https://factory.local/ \
        -http \
        -auth foreman:${api_token} \
        "$@"
}
```

**Features:**
- Automatic token retrieval from Jenkins
- Token caching for 30 days
- Auto-refresh when expired
- Bash completion support

## Usage

### Basic Commands

After installation, reload your shell:

```bash
source ~/.bashrc
```

Test the connection:

```bash
jenkins-factory who-am-i
```

Expected output:
```
Authenticated as: foreman
Authorities:
  authenticated
```

### Common Operations

#### List all jobs

```bash
jenkins-factory list-jobs
```

#### Get help

```bash
jenkins-factory help
```

#### Check Jenkins version

```bash
jenkins-factory version
```

#### Build a job

```bash
jenkins-factory build my-job-name
```

Build with parameters:

```bash
jenkins-factory build my-job-name -p PARAM1=value1 -p PARAM2=value2
```

Wait for build to complete:

```bash
jenkins-factory build my-job-name -s -v
```

Options:
- `-s` - Wait for build to start
- `-v` - Print build output to console

#### View build console output

```bash
jenkins-factory console my-job-name
```

View specific build number:

```bash
jenkins-factory console my-job-name 42
```

Follow console output (like tail -f):

```bash
jenkins-factory console my-job-name -f
```

#### Job Management

Create a job from XML:

```bash
jenkins-factory create-job my-new-job < job-config.xml
```

Get job configuration:

```bash
jenkins-factory get-job my-job-name > job-config.xml
```

Update job configuration:

```bash
jenkins-factory update-job my-job-name < updated-config.xml
```

Delete a job:

```bash
jenkins-factory delete-job my-job-name
```

Enable/disable a job:

```bash
jenkins-factory enable-job my-job-name
jenkins-factory disable-job my-job-name
```

#### View Management

Add job to view:

```bash
jenkins-factory add-job-to-view my-view my-job
```

#### Plugin Management

List installed plugins:

```bash
jenkins-factory list-plugins
```

Install a plugin:

```bash
jenkins-factory install-plugin plugin-name
```

Install specific version:

```bash
jenkins-factory install-plugin plugin-name -version 1.2.3
```

#### Credentials Management

List credentials:

```bash
jenkins-factory list-credentials system::system::jenkins
```

Create credentials (from XML):

```bash
jenkins-factory create-credentials-by-xml system::system::jenkins < credentials.xml
```

#### Node/Agent Management

List all nodes:

```bash
jenkins-factory list-nodes
```

Get node info:

```bash
jenkins-factory get-node factory-agent-1
```

Take node offline:

```bash
jenkins-factory offline-node factory-agent-1 -m "Maintenance"
```

Bring node online:

```bash
jenkins-factory online-node factory-agent-1
```

#### System Management

Restart Jenkins (waits for jobs to complete):

```bash
jenkins-factory safe-restart
```

Restart immediately:

```bash
jenkins-factory restart
```

Shutdown Jenkins safely:

```bash
jenkins-factory safe-shutdown
```

Put Jenkins in quiet mode (no new builds):

```bash
jenkins-factory quiet-down
```

Cancel quiet mode:

```bash
jenkins-factory cancel-quiet-down
```

Reload configuration from disk:

```bash
jenkins-factory reload-configuration
```

#### Groovy Scripts

Execute Groovy script:

```bash
jenkins-factory groovy = < script.groovy
```

Execute Groovy command:

```bash
jenkins-factory groovy = "println(Jenkins.instance.pluginManager.plugins)"
```

### Advanced Usage

#### Pipeline Job Creation

Create a simple pipeline job:

```bash
cat > pipeline-job.xml << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>My Pipeline Job</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>
pipeline {
    agent { label 'arm64' }
    stages {
        stage('Build') {
            steps {
                sh 'echo "Building on ARM64"'
                sh 'uname -m'
            }
        }
    }
}
    </script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF

jenkins-factory create-job my-pipeline-job < pipeline-job.xml
```

#### Automated Build Triggering

Create a script to trigger builds:

```bash
#!/bin/bash
# trigger-build.sh

JOB_NAME="$1"
BUILD_PARAMS="$2"

echo "Triggering build for ${JOB_NAME}..."

if [ -n "$BUILD_PARAMS" ]; then
    jenkins-factory build "$JOB_NAME" -p "$BUILD_PARAMS" -s -v
else
    jenkins-factory build "$JOB_NAME" -s -v
fi
```

Usage:

```bash
./trigger-build.sh my-app "ENVIRONMENT=production VERSION=1.2.3"
```

#### Bulk Operations

Disable all jobs matching pattern:

```bash
for job in $(jenkins-factory list-jobs | grep "^test-"); do
    jenkins-factory disable-job "$job"
    echo "Disabled: $job"
done
```

Trigger all jobs in a folder:

```bash
for job in $(jenkins-factory list-jobs | grep "^my-folder/"); do
    jenkins-factory build "$job"
    echo "Triggered: $job"
done
```

#### Integration with CI/CD

Use in shell scripts:

```bash
#!/bin/bash
# deploy.sh

set -e

# Build Docker image
docker build -t myapp:latest .

# Push to registry
docker push myapp:latest

# Trigger Jenkins deployment job
jenkins-factory build deploy-to-production \
    -p IMAGE_TAG=latest \
    -p ENVIRONMENT=prod \
    -s -v

echo "Deployment triggered successfully"
```

## Troubleshooting

### Connection Issues

**Problem**: Cannot connect to Jenkins

```bash
jenkins-factory who-am-i
# ERROR: Could not retrieve Jenkins API token
```

**Solutions**:

1. Verify Factory VM is running:
   ```bash
   ssh factory 'docker ps | grep jenkins'
   ```

2. Check Jenkins is accessible:
   ```bash
   curl -I https://factory.local/
   ```

3. Verify SSL certificate is trusted (should see no warnings)

4. Re-run the setup script:
   ```bash
   ~/vms/factory/setup-jenkins-cli.sh
   ```

### Token Issues

**Problem**: API token is invalid or expired

**Solution**: Refresh the token manually:

```bash
# Remove old token
rm -f ~/.jenkins-factory-token

# Get new token from Jenkins
ssh -p 2222 root@localhost \
    "docker exec jenkins cat /var/jenkins_home/foreman-api-token.txt" \
    > ~/.jenkins-factory-token

chmod 600 ~/.jenkins-factory-token
```

Or regenerate a new token:

```bash
# Access Jenkins UI
# Navigate to: People → foreman → Configure
# Click "Add new Token" under API Token section
# Copy the token and save it to ~/.jenkins-factory-token
```

### Permission Issues

**Problem**: Permission denied when running commands

**Solution**: Verify foreman user has admin privileges:

```bash
jenkins-factory groovy = "println(User.get('foreman').authorities)"
```

Should show administrative authorities.

### Java Issues

**Problem**: Java not found

```bash
jenkins-factory: java: command not found
```

**Solution**: Install Java on the host:

```bash
# Ubuntu/Debian
sudo apt-get install openjdk-21-jre-headless

# macOS
brew install openjdk@21

# Fedora/RHEL
sudo dnf install java-21-openjdk-headless
```

### Certificate Issues

**Problem**: SSL certificate verification fails

**Solution**: The jenkins-factory function uses `-http` flag which disables certificate validation. If you still have issues:

```bash
# Update CA certificates
sudo update-ca-certificates

# Or manually trust the Caddy certificate
curl -k https://factory.local/ca.crt | sudo tee /usr/local/share/ca-certificates/factory-ca.crt
sudo update-ca-certificates
```

## Manual Setup

If automatic setup fails, you can manually configure Jenkins CLI:

### Step 1: Download Jenkins CLI jar

```bash
curl -sSL https://factory.local/jnlpJars/jenkins-cli.jar -o ~/jenkins-cli-factory.jar
chmod 644 ~/jenkins-cli-factory.jar
```

### Step 2: Get API Token

```bash
# Retrieve token from Jenkins container
ssh -p 2222 root@localhost \
    "docker exec jenkins cat /var/jenkins_home/foreman-api-token.txt" \
    > ~/.jenkins-factory-token

chmod 600 ~/.jenkins-factory-token
```

### Step 3: Test Connection

```bash
java -jar ~/jenkins-cli-factory.jar \
    -s https://factory.local/ \
    -http \
    -auth foreman:$(cat ~/.jenkins-factory-token) \
    who-am-i
```

### Step 4: Add Bash Function

Add to `~/.bashrc`:

```bash
jenkins-factory() {
    local api_token=$(cat ~/.jenkins-factory-token 2>/dev/null)
    
    if [ -z "$api_token" ]; then
        echo "ERROR: Token file not found" >&2
        return 1
    fi
    
    java -jar ~/jenkins-cli-factory.jar \
        -s https://factory.local/ \
        -http \
        -auth foreman:${api_token} \
        "$@"
}
```

Then reload:

```bash
source ~/.bashrc
```

## Security Best Practices

1. **Protect the token file**:
   ```bash
   chmod 600 ~/.jenkins-factory-token
   ```

2. **Rotate tokens periodically**:
   - Create new token in Jenkins UI
   - Update `~/.jenkins-factory-token`
   - Revoke old tokens

3. **Limit foreman user permissions** (if needed):
   - Use Matrix-based security
   - Create role-based access control
   - Limit to specific job folders

4. **Audit CLI usage**:
   - Check Jenkins audit logs
   - Monitor foreman user activity
   - Review build triggers

5. **Use separate tokens for automation**:
   - Create additional tokens for CI/CD pipelines
   - Name tokens descriptively
   - Revoke unused tokens

## Reference

### Complete Command List

```bash
# General
help                          # Display help
version                       # Show Jenkins version
who-am-i                      # Display current user

# Jobs
list-jobs                     # List all jobs
build <job>                   # Trigger build
console <job> [build]         # Show console output
create-job <name>             # Create job from stdin
get-job <name>                # Get job config XML
update-job <name>             # Update job from stdin
delete-job <name>             # Delete job
enable-job <name>             # Enable job
disable-job <name>            # Disable job
copy-job <src> <dst>          # Copy job

# Builds
stop-builds <job>             # Stop all builds of job
get-build <job> <build>       # Get build information

# Views
list-views                    # List all views
create-view <name>            # Create view from stdin
get-view <name>               # Get view config
add-job-to-view <view> <job>  # Add job to view
remove-job-from-view          # Remove job from view

# Nodes
list-nodes                    # List all nodes
get-node <name>               # Get node information
online-node <name>            # Bring node online
offline-node <name>           # Take node offline
connect-node <name>           # Reconnect node
disconnect-node <name>        # Disconnect node

# Plugins
list-plugins                  # List installed plugins
install-plugin <name>         # Install plugin
enable-plugin <name>          # Enable plugin
disable-plugin <name>         # Disable plugin

# System
restart                       # Restart Jenkins
safe-restart                  # Restart when no jobs running
shutdown                      # Shutdown Jenkins
safe-shutdown                 # Shutdown when no jobs running
quiet-down                    # Put in quiet mode
cancel-quiet-down             # Cancel quiet mode
reload-configuration          # Reload config from disk

# Credentials
list-credentials <store>      # List credentials
create-credentials-by-xml     # Create credentials from XML
update-credentials-by-xml     # Update credentials from XML
delete-credentials <id>       # Delete credentials

# Advanced
groovy =                      # Execute Groovy script
groovysh                      # Interactive Groovy shell
clear-queue                   # Clear build queue
session-id                    # Display session ID
```

### Environment Variables

You can customize behavior with environment variables:

```bash
# Use custom Jenkins URL
export JENKINS_URL="https://factory.local/"

# Use custom credentials
export JENKINS_USER_ID="foreman"
export JENKINS_API_TOKEN="your-token-here"

# Then call without full authentication
java -jar ~/jenkins-cli-factory.jar list-jobs
```

### Files

| File | Purpose | Location |
|------|---------|----------|
| `jenkins-cli-factory.jar` | CLI executable | `~/jenkins-cli-factory.jar` |
| `.jenkins-factory-token` | Cached API token | `~/.jenkins-factory-token` |
| `foreman-api-token.txt` | Master token | `/var/jenkins_home/foreman-api-token.txt` (in Jenkins) |
| `setup-jenkins-cli.sh` | Manual setup script | `~/vms/factory/setup-jenkins-cli.sh` |

## Examples

### Create and Run Pipeline

```bash
# Create pipeline job
cat > my-pipeline.xml << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>ARM64 Build Pipeline</description>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition">
    <script>
pipeline {
    agent { label 'arm64' }
    stages {
        stage('Checkout') {
            steps {
                git 'https://github.com/myorg/myapp.git'
            }
        }
        stage('Build') {
            steps {
                sh 'docker build -t myapp:arm64 .'
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

jenkins-factory create-job my-arm64-build < my-pipeline.xml

# Trigger the build
jenkins-factory build my-arm64-build -s -v
```

### Monitor Build Status

```bash
#!/bin/bash
# monitor-build.sh

JOB="$1"
BUILD_NUMBER=$(jenkins-factory build "$JOB" -s | grep -oP 'build #\K\d+')

echo "Build started: #${BUILD_NUMBER}"

# Poll build status
while true; do
    STATUS=$(jenkins-factory get-build "$JOB" "$BUILD_NUMBER" | grep -oP 'result: \K\w+')
    
    if [ -n "$STATUS" ]; then
        echo "Build completed: $STATUS"
        break
    fi
    
    echo "Build in progress..."
    sleep 10
done

# Show console output
jenkins-factory console "$JOB" "$BUILD_NUMBER"
```

## Support

For issues or questions:

1. Check Jenkins logs: `ssh factory 'docker logs jenkins'`
2. Verify foreman user exists: `jenkins-factory who-am-i`
3. Re-run setup: `~/vms/factory/setup-jenkins-cli.sh`
4. Consult Jenkins CLI documentation: https://www.jenkins.io/doc/book/managing/cli/

## Related Documentation

- [JENKINS-CONFIGURATION.md](./JENKINS-CONFIGURATION.md) - Complete Jenkins setup guide
- [CHANGELOG.md](./CHANGELOG.md) - Version history and changes
- [Factory VM README](~/vms/factory/FACTORY-README.md) - VM usage guide
