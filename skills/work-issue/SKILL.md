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
