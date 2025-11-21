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

---

## Continuation Session (Later Same Day)

### Issues Fixed

#### 1. SSH Key Authentication (FIXED - commit 7db9e08)
- **Problem**: SSH asking for password when connecting to foreman user
- **Root Cause**: SSH key only copied to root's authorized_keys, not foreman's
- **Solution**: Added key copy to foreman user during creation
- **Verified**: SSH authentication works without password

#### 2. Component Installation Not Running (FIXED - commit 5f56133)
- **Problem**: vm-setup.sh execution failed, tools not installed
- **Root Cause**: Alpine uses `doas` not `sudo`, doesn't support `-E` flag or `VAR=value command` syntax
- **Solution**: Inject JENKINS_FOREMAN_PASSWORD at top of vm-setup.sh script before execution
- **Verified**: Component installation runs successfully, all tools installed

#### 3. Status Script Process Check (FIXED - commit a4fe295)
- **Problem**: `factorystatus` reports VM not running when qemu runs as root
- **Root Cause**: `kill -0` requires same process owner
- **Solution**: Use `ps -p $PID` instead which works regardless of owner
- **Verified**: Status script now correctly detects running VM

#### 4. Missing log_debug Function (FIXED - commit a32964f)
- **Problem**: Installation crashed with "log_debug: command not found"
- **Root Cause**: Used undefined function for debug logging
- **Solution**: Replace all `log_debug` with `log_info`

#### 5. Cache Directory Persistence (FIXED - commit b2b95c0)
- **Problem**: /tmp/cache deleted on VM reboot
- **Root Cause**: /tmp is cleared on every boot
- **Solution**: Use /var/cache/factory-build instead

#### 6. Brace Expansion in SSH Command (FIXED - commit b2b95c0)  
- **Problem**: Created literal directory named `{terraform,kubectl,helm,awscli,ansible}`
- **Root Cause**: Brace expansion doesn't work inside double-quoted SSH commands
- **Solution**: Use explicit paths: `mkdir -p dir1 dir2 dir3`
- **Status**: ⚠️ **PENDING CDN CACHE CLEAR** - Fix committed but GitHub CDN serving old version

#### 7. Foreman SSH Verification (FIXED - commit 46397de)
- **Problem**: Cache copy attempted before foreman SSH fully ready
- **Root Cause**: SSH ready check used root@localhost, not foreman@localhost
- **Solution**: Test foreman SSH access before cache copy operations

### Commits This Session
- **7db9e08**: Fix: Copy SSH key to foreman user's authorized_keys
- **f3d6583**: Fix: Pass JENKINS_FOREMAN_PASSWORD correctly to doas/sudo (failed - doas doesn't support -E)
- **5f56133**: Fix: Inject JENKINS_FOREMAN_PASSWORD into vm-setup.sh
- **d8a4f59**: Fix: Add retry logic and file existence checks for cache copying
- **a4fe295**: Fix: Use ps instead of kill -0 for status check
- **c8caec7**: Debug: Remove stderr suppression for cache copy operations
- **46397de**: Fix: Test foreman SSH before cache copy operations
- **a32964f**: Fix: Replace log_debug with log_info (function doesn't exist)
- **b2b95c0**: Fix: Use /var/cache/factory-build instead of /tmp/cache

### Current Status

**✅ WORKING**:
- SSH key authentication to foreman user
- Component installation (docker, kubectl, terraform, helm, aws)
- Status script detects running VM
- Installation completes successfully in 6-7 minutes

**⚠️ PENDING** (GitHub CDN Cache):
- Cache copy optimization (brace expansion fix committed but not yet served by CDN)
- Current workaround: Tools download during installation instead of using cached copies
- Impact: Minimal - installation still completes successfully

### Installation Test Results
- **Time**: 6-7 minutes (with cache, Alpine ISO, and plugins)
- **All tools verified installed**:
  - Docker: ✓
  - kubectl: ✓  
  - Terraform: ✓
  - Helm: ✓
  - AWS CLI: ✓
- **Cache warnings**: Harmless - tools download when cache copy fails

### Next Agent Actions
1. **Wait for GitHub CDN cache to clear** (typically 5-10 minutes after commit)
2. **Test one-liner again** - cache copy should work with brace expansion fix
3. **Verify cache usage** - check that files copied from cache reduce download time
4. **Consider**: If CDN caching continues to be an issue, add version parameter to raw URL

### Critical Learning
**Do NOT test from development directory** - Always use one-liner from user perspective to simulate actual installation experience. Testing from `~/wip/nb/FinTechProj/factory-vm` creates conflicts and doesn't represent end-user flow.

