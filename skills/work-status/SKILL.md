---
name: work-status
description: Show the current ticket, worktree, PR status, and recent commits for the active branch
user_invocable: true
---

# /work-status — Show current state

When this skill is invoked, follow these steps:

## 1. Get the current branch

```bash
git branch --show-current
```

If on `main` or `master`, tell the user there's no active work branch. Suggest `/work` to start something.

## 2. Read configuration

Read `.workbranch.json` for `team` prefix (default: `ENGG`).

## 3. Extract ticket ID

Parse the branch name to extract the ticket ID by matching the pattern `TEAM-\d+` anywhere in the branch name.

Example: `fix/ENGG-456-invoice-timeout` → `ENGG-456`

If no ticket ID is found in the branch name, note that this branch isn't linked to a Linear ticket.

## 4. Fetch Linear ticket details

If a ticket ID was found:

```bash
linear issue view TICKET_ID --json --no-pager
```

Display:
- **Ticket**: identifier, title
- **Status**: state name
- **Assignee**: assignee name
- **URL**: link to Linear

## 5. Show worktree info

Detect if inside a linked worktree:
```bash
git rev-parse --git-dir
git rev-parse --git-common-dir
```

If they differ, show the current worktree path via `pwd`. Otherwise note this is the main worktree.

## 6. Check working tree state

```bash
git status --short
```

Show if the worktree is clean or has uncommitted changes.

## 7. Show recent commits

```bash
git log --oneline -5
```

Show the last 5 commits on this branch.

## 8. Check PR status

```bash
gh pr view --json state,url,title,statusCheckRollup,reviews,number 2>/dev/null
```

If a PR exists, display:
- **PR**: number, title, URL
- **State**: open/closed/merged
- **CI**: passing/failing/pending
- **Reviews**: count of approvals

If no PR exists, note that no PR has been opened yet. Suggest `/work-pr` when ready.

## 9. Present everything

Format all sections in a clean, readable summary. Example:

```
## Active Work

**Ticket:** ENGG-456 — Invoice upload timeout on files over 20MB
**Status:** In Progress | **Assignee:** Philip Dodds
**URL:** https://linear.app/team/issue/ENGG-456

**Branch:** fix/ENGG-456-invoice-timeout
**Worktree:** ~/kodexa-wt/fix-ENGG-456-invoice-timeout (clean)

**Recent commits:**
  abc1234 fix(extraction): increase upload timeout
  def5678 test: add upload timeout test

**PR:** not opened yet — run /work-pr when ready
```
