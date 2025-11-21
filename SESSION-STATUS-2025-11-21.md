# Factory VM Session Status - November 21, 2025

## Session Summary
Debugging cache copy failures in the one-liner installer. Root cause identified: SCP commands were using `root@localhost` but SSH key is configured for `foreman` user.

## Issues Identified and Fixed

### 1. Cache Copy Failure (FIXED)
- **Problem**: SCP to VM failed silently during cache copy
- **Root Cause**: SCP commands used `root@localhost` but SSH key (~/.ssh/factory-foreman) is for `foreman` user
- **Solution**: Changed all SCP/SSH commands to use `foreman@localhost` with sudo for root operations
- **Commit**: 0749cf8 - "Fix cache copy: use foreman@localhost instead of root@localhost"

### 2. One-Liner Install Complexity (FIXED)
- **Problem**: Git-based installer had multiple issues:
  - Line ending conflicts (CRLF vs LF)
  - Git merge conflicts on updates
  - Complex branch/stash/pull logic
- **Solution**: Simplified installer to directly download setup-factory-vm.sh via curl (no git operations)
- **Commit**: 026ef1c - "Simplify installer: download script directly instead of git clone"

### 3. Unbound Variable Error (FIXED)
- **Problem**: Script uses `set -u` but DEBUG variable not initialized
- **Solution**: Use `${DEBUG:-}` syntax to provide empty default
- **Commit**: 87db63d - "Fix: Handle unset DEBUG variable with set -u"

### 4. GitHub CDN Cache (IN PROGRESS)
- **Problem**: GitHub raw.githubusercontent.com serves cached versions of files
- **Solution**: Added timestamp parameter to bypass CDN cache
- **Commit**: 573797c - "Fix: Bypass CDN cache when downloading setup script"

## Current State

### Repository Structure
```
~/wip/nb/FinTechProj/factory-vm/     # DEVELOPMENT (commit/push here)
~/factory-vm/                          # TEST (one-liner creates this)
```

### Cache Status
- Location: `~/factory-vm/cache/` (593MB)
- Contents:
  - Alpine ISO: 77MB
  - Terraform: 27MB
  - kubectl: 56MB
  - Helm: 17MB
  - AWS CLI: 56MB
  - Ansible requirements: 41B
  - Jenkins plugins: 25 plugins (~314MB)

### Latest Commits (main branch)
```
573797c Fix: Bypass CDN cache when downloading setup script
87db63d Fix: Handle unset DEBUG variable with set -u
026ef1c Simplify installer: download script directly instead of git clone
1434530 Fix: Use git reset --hard to avoid line ending conflicts on updates
fa3d570 Improve AWS CLI download: use temp file and add debug logging
830ed3e Fix: Preserve cache when removing non-git directory
```

## Testing Status

### Completed
- ✅ SSH to foreman@localhost works
- ✅ SCP to foreman@localhost works (user demonstrated)
- ✅ Cache structure exists and is preserved
- ✅ Simplified installer reduces complexity

### Failed/Blocked
- ❌ AWS CLI download fails in parallel execution
- ❌ GitHub CDN cache prevents immediate testing of fixes
- ❌ Multiple test attempts with manual edits in test directory

### Pending Tests
- ⏳ Full one-liner installation with all fixes
- ⏳ Cache copy verification (foreman@localhost)
- ⏳ Parallel download verification
- ⏳ Installation timing comparison

## Key Learnings

### Critical Rules Established
1. **NEVER modify ~/factory-vm** - only work in ~/wip/nb/FinTechProj/factory-vm
2. **Always test with one-liner** - simulates actual user experience
3. **No manual fixes in test environment** - all changes must go through dev→commit→push→test
4. **Preserve cache directory** - it's 593MB and valuable

### Technical Insights
- SSH config uses `User foreman` not root
- Git operations add complexity (line endings, merges, conflicts)
- Direct curl download simpler than git clone
- `set -u` requires `${VAR:-}` syntax for optional variables

## Next Steps

### Immediate (New Agent)
1. Clean ~/factory-vm (preserve cache)
2. Test one-liner with latest commits
3. Verify cache copy works with foreman@localhost
4. Confirm parallel downloads succeed

### Short Term
- Move from heredoc vm-setup.sh to SSH-based component installation
- Implement jenkins-cli plugin installation from host
- Add version checking (like jcscripts example)

### Long Term
- Complete parallel installation optimization
- Implement proper update mechanism
- Add rollback capability

## Files Modified This Session
- `install.sh` - Simplified to direct download, removed git operations
- `setup-factory-vm.sh` - Fixed DEBUG variable, improved AWS CLI download, changed SCP to use foreman

## Context for Next Agent
- User has cache already populated (593MB)
- Fix for foreman@localhost is committed (0749cf8)
- Simplified installer is committed (026ef1c, 573797c)
- Need to test complete flow with one-liner
- GitHub CDN may serve stale files for ~5-10 minutes after push
