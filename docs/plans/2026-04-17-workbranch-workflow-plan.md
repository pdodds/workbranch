# Workbranch Workflow Orchestrator Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Convert the workbranch plugin from a Linear context-injection tool into a full development workflow orchestrator with worktree management, PR creation, and team support.

**Architecture:** Claude Code plugin with 6 slash-command skills, a ConversationStart hook, and per-repo JSON config. Orchestrates `linear` CLI, `wt` (worktrunk), `gh` CLI, and `git` to manage the full ticket→worktree→implement→PR→merge→cleanup loop.

**Tech Stack:** Claude Code plugin (skills as Markdown, hooks as JSON), shell commands, `linear` CLI v2, `gh` CLI, `wt` (worktrunk), `git`

---

### Task 1: Update config template and gitignore

**Files:**
- Modify: `.workbranch.json.example`
- Modify: `.gitignore`

**Step 1: Update `.workbranch.json.example` with the new config shape**

```json
{
  "team": "ENGG",
  "reviewers": ["ghuser1", "ghuser2"],
  "branch_prefix": {
    "bug": "fix",
    "feature": "feat",
    "improvement": "chore"
  },
  "bootstrap": "npm install",
  "test": "npm test",
  "lint": "npm run lint",
  "typecheck": "npm run typecheck"
}
```

Note: `worktree_root` is intentionally absent — worktrunk manages its own paths via `~/.config/worktrunk/config.toml`.

**Step 2: Verify `.gitignore` still ignores `.workbranch.json`**

Current `.gitignore` already has `.workbranch.json` — no change needed. Verify it's there.

Also verify that `.claude/settings.local.json` is gitignored (it is — line 3). This file stays user-local and is NOT committed.

**Step 3: Commit**

```bash
git add .workbranch.json.example
git commit -m "chore: update config template with workflow fields

Add reviewers, branch_prefix, bootstrap, test, lint, typecheck.
Remove worktree_root (managed by worktrunk)."
```

---

### Task 2: Rewrite the ConversationStart hook

**Files:**
- Modify: `hooks/hooks.json`
- Create: `hooks/conversation-start.sh`

**Step 1: Update `hooks/hooks.json` to call the standalone script**

```json
{
  "hooks": {
    "ConversationStart": [
      {
        "type": "command",
        "command": "bash hooks/conversation-start.sh"
      }
    ]
  }
}
```

**Step 2: Create `hooks/conversation-start.sh`**

The script must:
- Never block conversation start (all lookups fail silently)
- Use `set -uo pipefail` (NOT `-e` — the fail-silent pattern is incompatible with errexit)
- Extract ticket ID using the team prefix pattern `TEAM-\d+` (not hardcoded branch prefixes)
- Detect worktrees via `git rev-parse --git-dir` vs `--git-common-dir`
- Check for `python3` availability before using it

```bash
#!/usr/bin/env bash
set -uo pipefail

# 1. Get current branch
BRANCH=$(git branch --show-current 2>/dev/null) || { echo "WORKBRANCH: Not in a git repository."; exit 0; }
if [ -z "$BRANCH" ]; then
  echo "WORKBRANCH: Not on any branch (detached HEAD)."
  exit 0
fi

# 2. Read team prefix from config
TEAM="ENGG"
if [ -f .workbranch.json ] && which python3 >/dev/null 2>&1; then
  TEAM=$(python3 -c "import json; print(json.load(open('.workbranch.json')).get('team', 'ENGG'))" 2>/dev/null || echo "ENGG")
fi

echo "WORKBRANCH: Branch is $BRANCH (team: $TEAM)"

# 3. Extract ticket ID from branch name (matches TEAM-NNN anywhere in the branch)
TICKET_ID=""
if echo "$BRANCH" | grep -qoE "${TEAM}-[0-9]+"; then
  TICKET_ID=$(echo "$BRANCH" | grep -oE "${TEAM}-[0-9]+" | head -1)
fi

# 4. Fetch Linear ticket details if we have a ticket ID
if [ -n "$TICKET_ID" ] && which linear >/dev/null 2>&1 && which python3 >/dev/null 2>&1; then
  TICKET_JSON=$(linear issue view "$TICKET_ID" --json --no-pager 2>/dev/null) || TICKET_JSON=""
  if [ -n "$TICKET_JSON" ]; then
    TICKET_TITLE=$(echo "$TICKET_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))" 2>/dev/null || echo "")
    TICKET_STATE=$(echo "$TICKET_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('state',{}).get('name',''))" 2>/dev/null || echo "")
    TICKET_URL=$(echo "$TICKET_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('url',''))" 2>/dev/null || echo "")
    echo "WORKBRANCH: Linked ticket: $TICKET_ID — $TICKET_TITLE"
    [ -n "$TICKET_STATE" ] && echo "WORKBRANCH: Status: $TICKET_STATE"
    [ -n "$TICKET_URL" ] && echo "WORKBRANCH: URL: $TICKET_URL"
  fi
fi

# 5. Detect if inside a linked worktree (not the main worktree)
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON" ] && [ "$GIT_DIR" != "$GIT_COMMON" ]; then
  echo "WORKBRANCH: Worktree: $(pwd)"
fi

# 6. Check for open PR
if which gh >/dev/null 2>&1; then
  PR_JSON=$(gh pr view --json state,url,statusCheckRollup,reviews 2>/dev/null) || PR_JSON=""
  if [ -n "$PR_JSON" ] && which python3 >/dev/null 2>&1; then
    PR_STATE=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('state',''))" 2>/dev/null || echo "")
    PR_URL=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || echo "")
    if [ -n "$PR_STATE" ]; then
      CI_STATUS=$(echo "$PR_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
checks=d.get('statusCheckRollup',[]) or []
if not checks: print('no checks')
elif all(c.get('conclusion')=='SUCCESS' or c.get('status')=='COMPLETED' for c in checks): print('passing')
elif any(c.get('conclusion')=='FAILURE' for c in checks): print('failing')
else: print('pending')
" 2>/dev/null || echo "unknown")
      APPROVALS=$(echo "$PR_JSON" | python3 -c "
import sys,json
reviews=json.load(sys.stdin).get('reviews',[]) or []
approvals=len([r for r in reviews if r.get('state')=='APPROVED'])
print(f'{approvals} approval' + ('s' if approvals!=1 else ''))
" 2>/dev/null || echo "")
      echo "WORKBRANCH: PR: $PR_URL ($PR_STATE, CI $CI_STATUS, $APPROVALS)"
    fi
  fi
fi

# 7. Note config loaded
if [ -f .workbranch.json ]; then
  echo "WORKBRANCH: Config loaded (.workbranch.json)"
fi
```

**Step 3: Make the script executable**

```bash
chmod +x hooks/conversation-start.sh
```

**Step 4: Test the hook manually**

```bash
cd /Users/pdodds/src/pdodds/workbench && bash hooks/conversation-start.sh
```

Expected output (on main branch, no ticket):
```
WORKBRANCH: Branch is main (team: ENGG)
```

**Step 5: Commit**

```bash
git add hooks/hooks.json hooks/conversation-start.sh
git commit -m "refactor: extract ConversationStart hook to standalone script

Add worktree detection (git-dir vs git-common-dir), ticket extraction
via team prefix pattern, and PR status injection."
```

---

### Task 3: Create `/work` skill

**Files:**
- Create: `skills/work/SKILL.md`

**Step 1: Write the skill file**

```markdown
---
name: work
description: Describe a problem — Claude creates a Linear ticket, sets up a worktree, and prepares for implementation
user_invocable: true
---

# /work — Start working on something

When this skill is invoked, follow these steps:

## 1. Check prerequisites

Verify these tools are available (run `which` for each):
- `linear` — if missing, tell the user: `npm install -g @anthropic-ai/linear-cli && linear auth`
- `wt` — if missing, tell the user to install worktrunk
- `gh` — if missing, tell the user: `brew install gh && gh auth login`

Stop if any are missing.

## 2. Read and validate configuration

Read `.workbranch.json` from the repository root. If it doesn't exist, use defaults:
- `team`: `ENGG`
- `reviewers`: `[]` (empty — will prompt at PR time)
- `branch_prefix`: `{"bug": "fix", "feature": "feat", "improvement": "chore"}`

Report the loaded config briefly:
```
Config: team=ENGG, reviewers=[ghuser1, ghuser2], test=npm test
```

## 3. Understand the problem

The user has described a problem, bug, feature, or task either:
- In the same message as `/work`
- Earlier in the conversation

Parse the description to determine:
- **Issue type**: bug, feature, or improvement. Match against the keys in `branch_prefix` config. If ambiguous, ask.
- **Title**: concise summary (under 80 chars)
- **Description**: repro steps (for bugs), requirements (for features), or scope (for improvements)
- **Acceptance criteria**: what "done" looks like

Present your interpretation to the user for confirmation before proceeding:
```
Type: bug
Title: Invoice upload timeout on files over 20MB
Description: Users hitting 500 when uploading large invoices. Trace shows timeout in extraction pipeline.
Acceptance criteria:
- Files up to 50MB upload without timeout
- Appropriate error message for files exceeding the limit
```

Wait for confirmation.

## 4. Create Linear ticket

```bash
linear issue create --title "TITLE" --description "DESCRIPTION" --team TEAM --assignee self --start --no-interactive
```

Where:
- `TITLE` is the confirmed title
- `DESCRIPTION` is the full description including acceptance criteria, formatted in Markdown. For long descriptions, write to a temp file and use `--description-file /tmp/workbranch-desc.md` instead.
- `TEAM` is from config
- `--start` transitions the issue to the team's started state (portable across Linear workspace configurations)

**Important:** `linear issue create` does NOT support `--json`. Parse the text output to extract the issue identifier (e.g. `ENGG-456`). Then fetch full details:

```bash
linear issue view ENGG-456 --json --no-pager
```

Parse the JSON to get the `url` field.

## 5. Create branch name

Build the branch name from:
- Prefix: look up issue type in `branch_prefix` config (bug→fix, feature→feat, improvement→chore)
- Ticket ID: from step 4 (e.g. `ENGG-456`)
- Slug: lowercase, hyphenated version of the title, truncated to keep total branch name under 60 chars

Example: `fix/ENGG-456-invoice-upload-timeout`

## 6. Create worktree

```bash
wt switch -c BRANCH_NAME
```

Worktrunk handles the path based on its own configuration (`~/.config/worktrunk/config.toml`).

**If worktree creation fails** but the ticket was already created: report the ticket ID and URL so the user can retry `wt switch -c` manually or delete the ticket in Linear. Do NOT silently continue.

## 7. Bootstrap

If `.workbranch.json` has a `bootstrap` command, run it:

```bash
BOOTSTRAP_CMD
```

**If bootstrap fails:** report the error but keep the worktree. The user can fix dependencies and re-run the command manually.

## 8. Report

Present the summary:
```
Created ENGG-456: Invoice upload timeout on files over 20MB
URL: https://linear.app/team/issue/ENGG-456
Branch: fix/ENGG-456-invoice-upload-timeout
Worktree: <path reported by wt>

When committing during this session, use this format:
  fix(extraction): description of change

  ENGG-456

Ready to implement. What's your approach, or should I investigate?
```

Do NOT auto-implement. Wait for the user's direction.
```

**Step 2: Verify file structure**

```bash
ls skills/work/SKILL.md
```

**Step 3: Commit**

```bash
git add skills/work/SKILL.md
git commit -m "feat: add /work skill for ticket and worktree creation"
```

---

### Task 4: Create `/work-status` skill

**Files:**
- Create: `skills/work-status/SKILL.md`

**Step 1: Write the skill file**

```markdown
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
```

**Step 2: Commit**

```bash
git add skills/work-status/SKILL.md
git commit -m "feat: add /work-status skill for active work overview"
```

---

### Task 5: Create `/work-pr` skill

**Files:**
- Create: `skills/work-pr/SKILL.md`

**Step 1: Write the skill file**

```markdown
---
name: work-pr
description: Run checks, push the branch, and open a GitHub PR linked to the Linear ticket
user_invocable: true
---

# /work-pr — Push and open a PR

When this skill is invoked, follow these steps:

## 1. Verify state

Get the current branch:
```bash
git branch --show-current
```

If on `main` or `master`, tell the user there's nothing to push. Stop.

Check for uncommitted changes:
```bash
git status --short
```

If there are uncommitted changes, ask whether to commit them first or abort.

## 2. Read configuration

Read `.workbranch.json` for:
- `team` prefix
- `reviewers` array (GitHub usernames)
- `test` command (optional)
- `lint` command (optional)
- `typecheck` command (optional)
- `bootstrap` command (for the PR body)

## 3. Run checks

Run each configured check command in order. Stop on first failure.

If `lint` is defined:
```bash
LINT_CMD
```

If `typecheck` is defined:
```bash
TYPECHECK_CMD
```

If `test` is defined:
```bash
TEST_CMD
```

If any check fails, show the output and ask the user how to proceed (fix and retry, or skip and push anyway).

## 4. Extract ticket info

Parse the branch name to extract the ticket ID by matching `TEAM-\d+`.

If a ticket ID was found, fetch the ticket details:
```bash
linear issue view TICKET_ID --json --no-pager
```

Extract the title and URL for the PR body.

## 5. Push the branch

```bash
git push -u origin BRANCH_NAME
```

**If push fails:** report the error. Common causes: no remote access, branch already exists with divergent history. Do not force-push.

## 6. Build PR body

Construct the PR body using a heredoc for correct formatting:

```markdown
## Summary
<1-3 bullet points derived from the Linear ticket description and recent commits>

## Linear
Closes TICKET_ID

## Test locally
\```
cd WORKTREE_PATH && BOOTSTRAP_CMD && TEST_CMD
\```
```

Where:
- `TICKET_ID` is from the branch name
- `WORKTREE_PATH` is `$(pwd)` (the actual current directory)
- `BOOTSTRAP_CMD` is from config (omit if not defined)
- `TEST_CMD` is from config (omit if not defined)

If no test or bootstrap commands are defined, omit the "Test locally" section.

## 7. Create the PR

Derive the PR title from the ticket: `TICKET_ID: Ticket Title`

```bash
gh pr create --title "PR_TITLE" --body "$(cat <<'EOF'
PR_BODY_HERE
EOF
)"
```

**If PR creation fails** but push succeeded: report the error. The user can retry `gh pr create` manually. The branch is already pushed.

## 8. Request reviewers

Read the `reviewers` array from `.workbranch.json`.

If reviewers are configured:
```bash
gh pr edit --add-reviewer "user1,user2"
```

If no reviewers are configured, ask the user:
> No reviewers configured in `.workbranch.json`. Enter a GitHub username to request review, or press enter to skip.

**Important:** Do NOT attempt to add the current user as a reviewer — GitHub does not allow self-review requests.

## 9. Report

Present:
- **PR URL** (from gh output)
- **Linear ticket URL**
- **Reviewers requested**
- Note that the `Closes TICKET_ID` in the PR body will auto-transition the Linear ticket

```
PR opened: https://github.com/org/repo/pull/42
Linear: https://linear.app/team/issue/ENGG-456
Reviewers: ghuser1, ghuser2
Waiting for review.
```
```

**Step 2: Commit**

```bash
git add skills/work-pr/SKILL.md
git commit -m "feat: add /work-pr skill for PR creation with Linear linking"
```

---

### Task 6: Create `/work-done` skill

**Files:**
- Create: `skills/work-done/SKILL.md`

**Step 1: Write the skill file**

```markdown
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
```

**Step 2: Commit**

```bash
git add skills/work-done/SKILL.md
git commit -m "feat: add /work-done skill for post-merge cleanup

Requires running from main worktree to avoid deleting the
current working directory."
```

---

### Task 7: Update `/work-issue` skill (rename from workbranch-issue)

**Files:**
- Create: `skills/work-issue/SKILL.md` (based on existing `skills/workbranch-issue/SKILL.md`)
- Delete: `skills/workbranch-issue/` (in Task 9)

**Step 1: Write the updated skill**

```markdown
---
name: work-issue
description: Create a Linear issue, optionally linked to the current work ticket
user_invocable: true
---

# /work-issue — Create a Linear issue

When this skill is invoked, follow these steps:

## 1. Read configuration

Read `.workbranch.json` for `team` prefix (default: `ENGG`).

## 2. Check for current work context

Get the current branch and try to extract a ticket ID by matching `TEAM-\d+` in the branch name.

If a ticket ID is found, this new issue can optionally be noted as related. Ask the user if the new issue is related to the current work.

## 3. Determine issue details

If the user provided a title and/or description along with the command, use those directly.

If the user has been discussing a specific bug, task, or feature earlier in the conversation, infer a sensible title and description. Present for confirmation before proceeding.

If there is no context, ask for:
- **Title** (required)
- **Description** (optional)

## 4. Create the issue

```bash
linear issue create --title "TITLE" --description "DESCRIPTION" --team TEAM --assignee self --no-interactive
```

**Important:** `linear issue create` does NOT support `--json`. Parse the text output to extract the issue identifier. Then fetch details:

```bash
linear issue view ISSUE_ID --json --no-pager
```

## 5. Confirm creation

Show:
- **Issue identifier** (e.g. `ENGG-789`)
- **Title**
- **URL** (from the JSON view)

If this was identified as related to the current work, note the relationship and suggest the user link them in Linear if needed.
```

**Step 2: Commit**

```bash
git add skills/work-issue/SKILL.md
git commit -m "feat: add /work-issue skill for creating Linear issues

Replaces /workbranch-issue. Drops project-based linking,
uses branch-based context instead."
```

---

### Task 8: Update `/work-doc` skill (rename from workbranch-doc)

**Files:**
- Create: `skills/work-doc/SKILL.md` (based on existing `skills/workbranch-doc/SKILL.md`)
- Delete: `skills/workbranch-doc/` (in Task 9)

**Step 1: Write the updated skill**

```markdown
---
name: work-doc
description: Create a Linear document, optionally attached to the current work ticket
user_invocable: true
---

# /work-doc — Create a Linear document

When this skill is invoked, follow these steps:

## 1. Check for current work context

Get the current branch and extract ticket ID by matching `TEAM-\d+` in the branch name (read team prefix from `.workbranch.json`, default `ENGG`).

## 2. Determine document title and content

If the user provided a title and/or content, use those directly.

If the user has been discussing design, architecture, or scope earlier in the conversation, offer to generate a document from that context. Present for confirmation.

If no context, ask for:
- **Title** (required)
- **Content** (optional, Markdown)

## 3. Create the document

For short content:
```bash
linear doc create --title "TITLE" --content "CONTENT"
```

For longer content, write to a temp file:
```bash
cat > /tmp/workbranch-doc.md << 'DOCEOF'
CONTENT_HERE
DOCEOF
linear doc create --title "TITLE" --content-file /tmp/workbranch-doc.md
```

If on a work branch with a ticket ID, attach the document to the current issue:
```bash
linear doc create --title "TITLE" --content-file /tmp/workbranch-doc.md --issue TICKET_ID
```

## 4. Confirm creation

Show:
- **Document title**
- Whether it was attached to a ticket (if applicable)
- Confirm creation
```

**Step 2: Commit**

```bash
git add skills/work-doc/SKILL.md
git commit -m "feat: add /work-doc skill for creating Linear documents

Replaces /workbranch-doc. Attaches docs to current issue
via --issue flag when on a work branch."
```

---

### Task 9: Remove old skills

**Files:**
- Delete: `skills/workbranch/SKILL.md`
- Delete: `skills/workbranch-init/SKILL.md`
- Delete: `skills/workbranch-issue/SKILL.md`
- Delete: `skills/workbranch-doc/SKILL.md`

**Step 1: Remove old skill directories**

```bash
rm -rf skills/workbranch skills/workbranch-init skills/workbranch-issue skills/workbranch-doc
```

- `/workbranch` → replaced by `/work-status`
- `/workbranch-init` → replaced by `/work`
- `/workbranch-issue` → replaced by `/work-issue`
- `/workbranch-doc` → replaced by `/work-doc`

**Step 2: Commit**

```bash
git rm -r skills/workbranch skills/workbranch-init skills/workbranch-issue skills/workbranch-doc
git commit -m "chore: remove old /workbranch-* skills

Replaced by /work, /work-status, /work-pr, /work-done,
/work-issue, /work-doc."
```

---

### Task 10: Update plugin manifest

**Files:**
- Modify: `.claude-plugin/plugin.json`

**Step 1: Update plugin.json**

```json
{
  "name": "workbranch",
  "description": "Development workflow orchestrator. Manages the full loop: describe problem → Linear ticket → git worktree → implement → PR → review → cleanup.",
  "version": "2.0.0",
  "author": {
    "name": "Philip Dodds",
    "url": "https://github.com/pdodds"
  },
  "repository": "https://github.com/pdodds/workbranch",
  "license": "Apache-2.0"
}
```

**Step 2: Commit**

Note: `.claude/settings.local.json` is gitignored and stays local. Users update their own permissions. The README documents required permissions.

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump plugin to v2.0.0 workflow orchestrator"
```

---

### Task 11: Update README

**Files:**
- Modify: `README.md`

**Step 1: Rewrite README**

Update to reflect the new workflow-oriented plugin:

- New description emphasizing the full workflow loop
- Updated prerequisites (add `wt`, `gh`)
- New command table (`/work`, `/work-status`, `/work-pr`, `/work-done`, `/work-issue`, `/work-doc`)
- Updated config section with all new fields including `reviewers`
- Workflow section showing the main loop
- Team support section explaining reviewer config
- Required permissions section (what to add to `.claude/settings.local.json`)
- Note that worktree paths are managed by worktrunk, not this plugin
- Error recovery table from the design doc
- Updated project structure

Keep the same tone and structure as the existing README. Don't over-document — the skills are the detailed docs.

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README for v2.0.0 workflow orchestrator"
```

---

### Task 12: Verify everything works together

**Step 1: Verify file structure**

```bash
find . -name "*.md" -path "*/skills/*" | sort
```

Expected:
```
./skills/work/SKILL.md
./skills/work-doc/SKILL.md
./skills/work-done/SKILL.md
./skills/work-issue/SKILL.md
./skills/work-pr/SKILL.md
./skills/work-status/SKILL.md
```

**Step 2: Verify no old skills remain**

```bash
ls skills/
```

Expected: `work/  work-doc/  work-done/  work-issue/  work-pr/  work-status/`

Verify none of the old directories exist:
```bash
test -d skills/workbranch && echo "ERROR: old skills/workbranch still exists" || echo "OK"
test -d skills/workbranch-init && echo "ERROR: old skills/workbranch-init still exists" || echo "OK"
test -d skills/workbranch-issue && echo "ERROR: old skills/workbranch-issue still exists" || echo "OK"
test -d skills/workbranch-doc && echo "ERROR: old skills/workbranch-doc still exists" || echo "OK"
```

**Step 3: Verify hook script runs**

```bash
bash hooks/conversation-start.sh
```

Should output at minimum: `WORKBRANCH: Branch is main (team: ENGG)`

**Step 4: Verify JSON files are valid**

```bash
python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); print('plugin.json: valid')"
python3 -c "import json; json.load(open('hooks/hooks.json')); print('hooks.json: valid')"
python3 -c "import json; json.load(open('.workbranch.json.example')); print('.workbranch.json.example: valid')"
```

**Step 5: Verify hook script is executable**

```bash
test -x hooks/conversation-start.sh && echo "OK: executable" || echo "ERROR: not executable"
```

**Step 6: Verify .gitignore**

```bash
grep -q "^\.workbranch\.json$" .gitignore && echo "OK: .workbranch.json ignored" || echo "ERROR"
grep -q "settings\.local\.json" .gitignore && echo "OK: settings.local.json ignored" || echo "ERROR"
```

**Step 7: Final commit if any fixes needed**

Only commit if verification uncovered issues that needed fixing.
