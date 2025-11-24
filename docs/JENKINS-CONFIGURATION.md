# Jenkins Configuration - Factory VM

## Overview

Factory VM includes a fully automated Jenkins CI/CD setup with production-ready configuration, Java 21 support, and best practices for distributed builds.

## Key Features

### ✅ Java 21 LTS
- **Long-term support until September 2029**
- Replaces Java 17 (EOL March 2026)
- Better performance and modern language features
- Future-proof for the next 4+ years

### ✅ Agent-Based Architecture
- **Built-in node DISABLED** (industry best practice)
- All builds run on dedicated agents
- Isolation and resource management
- Scalable architecture

### ✅ Pre-configured Agent
- **Name**: `factory-agent-1`
- **Executors**: 2
- **Labels**: `arm64`, `docker`, `kubernetes`
- **Runtime**: Docker container (isolated environment)
- **Capabilities**: ARM64 builds, Docker-in-Docker, Kubernetes CLI

### ✅ Essential Plugins (Auto-installed)

#### Source Control Management
- `git` - Git plugin
- `github` - GitHub integration
- `gitlab-plugin` - GitLab integration

#### Pipeline & Workflow
- `workflow-aggregator` - Complete Pipeline suite
- `pipeline-stage-view` - Pipeline visualization
- `pipeline-graph-view` - Graph view for pipelines

#### Container & Orchestration
- `docker-workflow` - Docker Pipeline steps
- `docker-plugin` - Docker plugin
- `kubernetes` - Kubernetes plugin
- `kubernetes-cli` - kubectl integration

#### Cloud & AWS
- `aws-credentials` - AWS credentials provider
- `amazon-ecr` - AWS Elastic Container Registry
- `pipeline-aws` - AWS Pipeline steps

#### Build Tools
- `nodejs` - Node.js support
- `gradle` - Gradle builds
- `maven-plugin` - Maven builds

#### Utilities
- `credentials-binding` - Credential binding
- `ssh-agent` - SSH agent support
- `timestamper` - Build timestamps
- `ws-cleanup` - Workspace cleanup
- `build-timeout` - Build timeouts
- `ansicolor` - ANSI color output

#### Notifications
- `email-ext` - Extended email notifications
- `slack` - Slack integration

#### Security
- `matrix-auth` - Matrix-based security
- `role-strategy` - Role-based access control

## Access Information

### Web UI
- **URL**: `https://factory.local`
- **Admin Username**: `admin`
- **Admin Password**: `admin123`

### CLI Access
- **CLI User**: `foreman`
- **CLI Password**: `foreman123`
- **API Token**: Auto-generated (see `~/.jenkins-factory-token`)
- **Command**: `jenkins-factory <command>`
- **Documentation**: See [JENKINS-CLI.md](./JENKINS-CLI.md)

**Quick CLI Examples**:
```bash
# Verify connection
jenkins-factory who-am-i

# List all jobs
jenkins-factory list-jobs

# Trigger a build
jenkins-factory build my-job
```

### Security
- HTTPS with trusted certificate (no warnings after setup)
- Anonymous access disabled
- Two users: `admin` (web UI) and `foreman` (CLI/automation)
- Admin-only access by default

## Architecture

### Jenkins Controller
- Runs in Docker container
- Java 21 LTS
- 2GB heap memory (`-Xmx2g`)
- Port 8080 (HTTP, internal)
- Port 50000 (JNLP for agents)
- Accessible via `https://factory.local`

### Jenkins Agent
- Runs in separate Docker container
- Mounts Docker socket (Docker-in-Docker)
- Isolated workspace: `/opt/jenkins/agent`
- Auto-connects to controller
- 2 concurrent build executors

## Configuration Files

### Init Scripts
Located in `/opt/jenkins/init.groovy.d/`:

1. **01-basic-security.groovy**
   - Skips setup wizard
   - Creates admin user (admin/admin123)
   - Configures security realm

2. **02-configure-executors.groovy**
   - Disables built-in node
   - Sets exclusive mode

3. **03-create-agent.groovy**
   - Creates factory-agent-1
   - Configures labels and executors
   - Sets up Docker launcher

4. **04-install-plugins.groovy**
   - Installs 25+ essential plugins
   - Handles failures gracefully

5. **05-create-foreman-user.groovy** ⭐ NEW
   - Creates foreman user (foreman/foreman123)
   - Generates API token for CLI access
   - Saves token to `/var/jenkins_home/foreman-api-token.txt`
   - Used for jenkins-factory CLI command

### Jenkins Configuration as Code (JCasC)
Located in `/opt/jenkins/jenkins.yaml`:

```yaml
jenkins:
  systemMessage: "Factory VM Jenkins - ARM64 Build Server"
  numExecutors: 0  # Disabled
  mode: EXCLUSIVE
  
unclassified:
  location:
    url: "https://factory.local/"
```

## Best Practices Implemented

### ✅ Security
- No anonymous access
- Strong authentication
- No builds on controller (isolation)

### ✅ Scalability
- Agent-based architecture
- Easy to add more agents
- Resource isolation

### ✅ Maintainability
- Infrastructure as Code (JCasC)
- Automated configuration
- Version controlled setup

### ✅ Performance
- Java 21 optimizations
- Configured heap size
- Workspace cleanup

## Build Pipeline Example

```groovy
pipeline {
    agent {
        label 'arm64'
    }
    
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
        
        stage('Push to ECR') {
            steps {
                withAWS(credentials: 'aws-credentials') {
                    sh '''
                        aws ecr get-login-password --region us-east-1 | \
                        docker login --username AWS --password-stdin $ECR_REGISTRY
                        docker push $ECR_REGISTRY/myapp:arm64
                    '''
                }
            }
        }
    }
}
```

## Troubleshooting

### Jenkins not starting
```bash
# Check Docker container
ssh factory 'sudo docker ps -a | grep jenkins'

# View logs
ssh factory 'sudo docker logs jenkins'

# Restart Jenkins
ssh factory 'sudo rc-service jenkins restart'
```

### Plugin installation failed
```bash
# Plugins install in background
# Check progress in Jenkins UI: Manage Jenkins → Manage Plugins

# Or check logs
ssh factory 'sudo docker exec jenkins cat /var/jenkins_home/logs/tasks/PluginManager.log'
```

### Agent not connecting
```bash
# Check agent status in Jenkins UI
# Navigate to: Manage Jenkins → Manage Nodes and Clouds

# Check Docker socket permissions
ssh factory 'ls -la /var/run/docker.sock'

# Restart agent (it will auto-reconnect)
ssh factory 'sudo docker ps | grep agent | awk "{print \$1}" | xargs docker restart'
```

## Upgrade Path

### Updating Jenkins
```bash
# Stop current Jenkins
ssh factory 'sudo rc-service jenkins stop'

# Pull latest LTS image with Java 21
ssh factory 'sudo docker pull jenkins/jenkins:lts-jdk21'

# Start Jenkins
ssh factory 'sudo rc-service jenkins start'

# Configuration persists in /opt/jenkins
```

### Adding More Agents
Edit `/opt/jenkins/init.groovy.d/03-create-agent.groovy` and add:

```groovy
// Create additional agent
if (instance.getNode('factory-agent-2') == null) {
    def agent = new DumbSlave(
        'factory-agent-2',
        'Additional ARM64 agent',
        '/opt/jenkins/agent2',
        '2',
        Node.Mode.NORMAL,
        'arm64 docker',
        launcher,
        RetentionStrategy.INSTANCE,
        []
    )
    instance.addNode(agent)
}
```

## Performance Tuning

### Heap Size
Adjust in `/etc/init.d/jenkins`:
```bash
-e JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx4g"  # 4GB heap
```

### Executors per Agent
Adjust in `03-create-agent.groovy`:
```groovy
def agentNumExecutors = 4  # Increase to 4 executors
```

## Integration Points

### AWS
- AWS credentials plugin pre-installed
- ECR support ready
- Use AWS credentials in pipelines

### Kubernetes
- Kubernetes plugin installed
- kubectl CLI available in agents
- Can deploy to K8s clusters

### Docker
- Docker-in-Docker available
- Build and push container images
- Multi-architecture builds supported

## Security Considerations

### Change Default Password
```groovy
// Edit /opt/jenkins/init.groovy.d/01-basic-security.groovy
hudsonRealm.createAccount("admin", "YOUR_STRONG_PASSWORD")
```

### Enable Matrix Security
```groovy
// Add to JCasC (jenkins.yaml)
jenkins:
  authorizationStrategy:
    globalMatrix:
      permissions:
        - "Overall/Administer:admin"
        - "Overall/Read:authenticated"
```

### SSL/TLS
- Already configured via Caddy reverse proxy
- Certificate auto-installed in browsers
- All traffic encrypted

## Monitoring

### Health Checks
```bash
# Jenkins HTTP endpoint
curl -I https://factory.local

# Container health
ssh factory 'sudo docker inspect jenkins | grep Health -A 10'
```

### Resource Usage
```bash
# Container stats
ssh factory 'sudo docker stats jenkins --no-stream'

# Disk usage
ssh factory 'sudo du -sh /opt/jenkins'
```

## Backup & Restore

### Backup
```bash
# Stop Jenkins
ssh factory 'sudo rc-service jenkins stop'

# Backup Jenkins home
ssh factory 'sudo tar -czf /tmp/jenkins-backup-$(date +%Y%m%d).tar.gz /opt/jenkins'

# Copy backup to host
scp factory:/tmp/jenkins-backup-*.tar.gz ~/backups/

# Restart Jenkins
ssh factory 'sudo rc-service jenkins start'
```

### Restore
```bash
# Stop Jenkins
ssh factory 'sudo rc-service jenkins stop'

# Restore from backup
scp ~/backups/jenkins-backup-*.tar.gz factory:/tmp/
ssh factory 'sudo tar -xzf /tmp/jenkins-backup-*.tar.gz -C /'

# Fix permissions
ssh factory 'sudo chown -R 1000:1000 /opt/jenkins'

# Start Jenkins
ssh factory 'sudo rc-service jenkins start'
```

## Migration from Java 17

The upgrade from Java 17 to Java 21 is automatic. Key benefits:

### Performance
- ~5-10% faster compilation
- Better garbage collection
- Improved startup time

### Support Timeline
- Java 17 LTS: Until September 2026
- Java 21 LTS: Until September 2029
- **3 additional years of support**

### Compatibility
- Fully backward compatible
- All plugins work with Java 21
- No code changes needed

## References

- [Jenkins Official Documentation](https://www.jenkins.io/doc/)
- [Jenkins Configuration as Code](https://github.com/jenkinsci/configuration-as-code-plugin)
- [Jenkins Best Practices](https://www.jenkins.io/doc/book/using/)
- [Java 21 Documentation](https://docs.oracle.com/en/java/javase/21/)
- [Docker in Jenkins](https://www.jenkins.io/doc/book/installing/docker/)

## Support

For issues specific to Factory VM Jenkins setup:
1. Check Jenkins logs: `ssh factory 'sudo docker logs jenkins'`
2. Review init scripts: `ssh factory 'ls /opt/jenkins/init.groovy.d/'`
3. Check plugin status: https://factory.local/pluginManager/
4. Verify agent connection: https://factory.local/computer/

---

**Factory VM Version**: 1.0  
**Jenkins Version**: Latest LTS with Java 21  
**Last Updated**: November 17, 2025
