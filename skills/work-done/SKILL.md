---
name: work-done
description: Clean up the worktree and branch after a PR has been merged
user_invocable: true
---

# /work-done — Clean up after merge

**Important:** This command should be run from the main worktree, NOT from inside the work worktree being cleaned up. If you detect the current directory is inside a linked worktree (git-dir differs from git-common-dir), instruct the user to switch to their main repo checkout first, or run `wt switch main` (or `wt switch ^`).

When this skill is invoked, follow these steps:

## 1. Verify we are NOT inside the target worktree

```bash
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null)
```

If `$GIT_DIR` differs from `$GIT_COMMON`, we are inside a linked worktree. Tell the user:
> You're inside the worktree that would be deleted. Please switch to your main repo checkout first:
> ```
> cd /path/to/main/repo
> ```
> Then run `/work-done` again.

Stop here.

## 2. Determine which branch to clean up

If the user specified a branch name, use that. Otherwise, ask which work branch to clean up. You can list active worktrees:

```bash
wt list
```

Let the user pick.

## 3. Check PR status

```bash
gh pr view BRANCH_NAME --json state,mergedAt 2>/dev/null
```

### If PR is merged

Proceed to cleanup.

### If PR is open (not merged)

Warn the user:
> The PR for branch `BRANCH_NAME` has not been merged yet. Are you sure you want to clean up?

Wait for confirmation before proceeding. If the user says no, stop.

### If no PR exists

Warn the user:
> No PR found for branch `BRANCH_NAME`. The work may not be integrated. Are you sure you want to clean up?

Wait for confirmation before proceeding.

## 4. Remove the worktree

```bash
wt remove BRANCH_NAME
```

This removes the worktree and the local branch via worktrunk.

## 5. Delete remote branch

If the branch still exists on the remote:
```bash
git push origin --delete BRANCH_NAME
```

Skip silently if the branch was already deleted (e.g. by GitHub's auto-delete on merge setting).

## 6. Report

```
Cleanup complete:
- Worktree removed for BRANCH_NAME
- Remote branch deleted
- Linear ticket transitioned via PR merge
```
