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
