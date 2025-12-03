# Jenkins Docker Cloud Agent Guide

## Overview

Factory VM uses Jenkins Docker Cloud to dynamically provision build agents. Instead of permanent agents, Docker containers are spun up on-demand for each build and automatically cleaned up after.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Factory VM (Alpine)                   │
│                                                          │
│  ┌──────────────────┐     ┌──────────────────────────┐  │
│  │ Jenkins Container │────▶│ Docker Socket            │  │
│  │ (Controller)      │     │ /var/run/docker.sock     │  │
│  └──────────────────┘     └──────────────────────────┘  │
│           │                          │                   │
│           │                          ▼                   │
│           │               ┌──────────────────────────┐  │
│           │               │ Agent Container          │  │
│           │               │ (jenkins/inbound-agent)  │  │
│           │               │ - Runs build             │  │
│           │               │ - Auto-removed after     │  │
│           └──────────────▶│                          │  │
│               (JNLP)      └──────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Configuration

### Docker Cloud (auto-configured via JCasC)

Location: Manage Jenkins → Clouds → docker

| Setting | Value |
|---------|-------|
| Name | docker |
| Docker Host URI | unix:///var/run/docker.sock |
| Container Cap | 10 |

### Agent Template

| Setting | Value |
|---------|-------|
| Labels | `docker-agent linux arm64` |
| Image | jenkins/inbound-agent:latest |
| Remote FS Root | /home/jenkins/agent |
| Connect method | Attach Docker container |

## How It Works

1. **Job Requests Agent**: When a job with label `docker-agent` runs
2. **Container Provisioned**: Jenkins tells Docker to create a new container
3. **Agent Connects**: Container runs JNLP agent that connects back to Jenkins
4. **Build Runs**: Job executes inside the container
5. **Cleanup**: Container is automatically removed after the job

## Using Docker Agents in Jobs

### Freestyle Job

1. Create new Freestyle project
2. Check "Restrict where this project can be run"
3. Label Expression: `docker-agent`
4. Add build steps as normal

### Pipeline Job

```groovy
pipeline {
    agent {
        label 'docker-agent'
    }
    stages {
        stage('Build') {
            steps {
                sh 'echo "Running on Docker agent"'
                sh 'uname -a'
            }
        }
    }
}
```

### Docker Pipeline (nested containers)

```groovy
pipeline {
    agent {
        label 'docker-agent'
    }
    stages {
        stage('Build in Container') {
            steps {
                script {
                    docker.image('node:20').inside {
                        sh 'node --version'
                        sh 'npm --version'
                    }
                }
            }
        }
    }
}
```

## Troubleshooting

### Build Stuck "Waiting for next available executor"

**Cause**: No agents available yet

**Solutions**:
1. Check Clouds page - is "docker" cloud listed?
2. Check Docker socket permissions: `ssh factory "ls -la /var/run/docker.sock"`
   - Should be `srw-rw-rw-` (666 permissions)
3. Check Jenkins logs: `ssh factory "sudo docker logs jenkins 2>&1 | tail -50"`

### Agent Won't Connect

**Check Docker connectivity**:
```bash
ssh factory "sudo docker exec jenkins curl -s --unix-socket /var/run/docker.sock http://localhost/version"
```

**Fix socket permissions**:
```bash
ssh factory "sudo chmod 666 /var/run/docker.sock"
```

### First Build is Slow

The first build pulls the `jenkins/inbound-agent` image (~324MB). Subsequent builds reuse the cached image.

**Pre-pull the image**:
```bash
ssh factory "sudo docker pull jenkins/inbound-agent:latest"
```

### Container Cleanup Issues

Containers should auto-remove. If they don't:
```bash
ssh factory "sudo docker ps -a | grep jenkins/inbound"
ssh factory "sudo docker container prune -f"
```

## Viewing Agent Logs

1. Go to Manage Jenkins → Nodes
2. Click on the agent (e.g., docker-00000hy7q3eyj)
3. Click "Log" in left sidebar

Or via CLI:
```bash
jenkins-factory console <job-name> <build-number>
```

## Testing the Agent

### Quick Test via CLI

```bash
# Create and run test job
cat << 'EOF' | jenkins-factory create-job test-docker-agent
<?xml version='1.1' encoding='UTF-8'?>
<project>
  <assignedNode>docker-agent</assignedNode>
  <canRoam>false</canRoam>
  <builders>
    <hudson.tasks.Shell>
      <command>echo "Hello from Docker agent!"
hostname
uname -a</command>
    </hudson.tasks.Shell>
  </builders>
</project>
EOF

# Run the job
jenkins-factory build test-docker-agent -s -v
```

### Verify via UI

1. Go to https://factory.local
2. Click "New Item" → Freestyle project
3. Name: "test-agent"
4. Check "Restrict where this project can be run"
5. Label: `docker-agent`
6. Add build step: Execute shell → `hostname && uname -a`
7. Save and click "Build Now"

## Advanced: Custom Agent Images

Create custom agent images for specific toolchains:

```dockerfile
FROM jenkins/inbound-agent:latest

# Add Node.js
RUN apt-get update && apt-get install -y nodejs npm

# Add Python
RUN apt-get install -y python3 python3-pip
```

Build and push, then update the template in Manage Jenkins → Clouds → docker → Configure.

## Performance Notes

- **TCG Emulation**: Factory VM runs ARM64 on x86_64 via TCG, so builds are slower than native
- **First build**: Pulls agent image (~1-2 min)
- **Subsequent builds**: Start in ~10-20 seconds
- **Container reuse**: Agents are ephemeral, no state persists between builds
