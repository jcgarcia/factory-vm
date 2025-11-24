# Jenkins CLI Quick Reference

## 🚀 Setup

```bash
# After Factory VM installation
source ~/.bashrc

# Test connection
jenkins-factory who-am-i
```

## 📋 Common Commands

### Jobs
```bash
jenkins-factory list-jobs                    # List all jobs
jenkins-factory create-job <name> < job.xml  # Create from XML
jenkins-factory get-job <name> > job.xml     # Export to XML
jenkins-factory build <name>                 # Trigger build
jenkins-factory build <name> -p KEY=value    # Build with params
jenkins-factory console <name>               # View console
jenkins-factory console <name> -f            # Follow console
jenkins-factory delete-job <name>            # Delete job
jenkins-factory enable-job <name>            # Enable job
jenkins-factory disable-job <name>           # Disable job
```

### System
```bash
jenkins-factory version                      # Jenkins version
jenkins-factory who-am-i                     # Current user
jenkins-factory restart                      # Restart immediately
jenkins-factory safe-restart                 # Restart when idle
jenkins-factory reload-configuration         # Reload from disk
```

### Plugins
```bash
jenkins-factory list-plugins                 # List all plugins
jenkins-factory install-plugin <name>        # Install plugin
```

### Nodes
```bash
jenkins-factory list-nodes                   # List all nodes
jenkins-factory get-node <name>              # Node details
jenkins-factory online-node <name>           # Bring online
jenkins-factory offline-node <name>          # Take offline
```

### Groovy
```bash
jenkins-factory groovy = < script.groovy     # Execute file
jenkins-factory groovy = "println('Hello')"  # Execute command
```

## 🔑 Credentials

- **Username**: foreman
- **Password**: foreman123
- **Token**: Auto-managed in `~/.jenkins-factory-token`

## 📚 Full Documentation

See [JENKINS-CLI.md](./JENKINS-CLI.md) for complete reference

## 🆘 Troubleshooting

```bash
# Refresh token
rm ~/.jenkins-factory-token && source ~/.bashrc

# Check Jenkins is running
ssh factory 'docker ps | grep jenkins'

# View Jenkins logs
ssh factory 'docker logs jenkins'

# Re-run CLI setup
~/vms/factory/setup-jenkins-cli.sh
```

## 💡 Pro Tips

```bash
# Create job from template
jenkins-factory get-job template-job | \
    sed 's/template-job/new-job/g' | \
    jenkins-factory create-job new-job

# Trigger all jobs matching pattern
jenkins-factory list-jobs | grep 'test-' | \
    xargs -I {} jenkins-factory build {}

# Export all jobs
for job in $(jenkins-factory list-jobs); do
    jenkins-factory get-job "$job" > "${job}.xml"
done
```

## 🔗 Quick Links

- Installation: [README.md](./README.md#quick-start)
- Configuration: [JENKINS-CONFIGURATION.md](./JENKINS-CONFIGURATION.md)
- Full CLI Guide: [JENKINS-CLI.md](./JENKINS-CLI.md)
- Changelog: [CHANGELOG.md](./CHANGELOG.md)
