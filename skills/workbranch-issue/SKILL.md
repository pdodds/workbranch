---
name: workbranch-issue
description: Create a Linear issue in the project linked to the current git branch
user_invocable: true
---

# /workbranch-issue — Create an issue in the linked project

When this skill is invoked, follow these steps:

## 1. Get the current branch

Run:
```bash
git branch --show-current
```

Save the branch name for the next steps.

## 2. Find the linked Linear project

Run:
```bash
linear project list --json
```

Parse the JSON output (an array of project objects). Search for a project whose `description` field contains the marker `[branch: <branch-name>]`, where `<branch-name>` is the branch from step 1.

### If no matching project is found

Tell the user:
> No Linear project is linked to branch `<branch-name>`. Run `/workbranch-init` to create and link a project first.

Stop here — an issue cannot be created without a linked project.

## 3. Determine the issue title and description

If the user provided a title and/or description along with the command, use those directly.

If the user has been discussing a specific bug, task, or feature earlier in the conversation, infer a sensible title and description from that context. Present the inferred title and description to the user for confirmation before proceeding.

If there is no context to infer from and the user did not provide details, ask the user for:
- **Title** (required): a short summary of the issue
- **Description** (optional): additional detail about the issue

## 4. Read the team prefix

Check if `.workbranch.json` exists in the repository root. If it does, read it and extract the `team` field. If the file does not exist or has no `team` field, default to `ENGG`.

## 5. Create the Linear issue

Run:
```bash
linear issue create --title "TITLE" --description "DESC" --project "PROJECT_NAME" --team TEAM --no-interactive
```

Where:
- `TITLE` is the issue title from step 3
- `DESC` is the issue description from step 3 (use an empty string if none was provided)
- `PROJECT_NAME` is the `name` field of the matched project from step 2
- `TEAM` is the team from step 4

## 6. Confirm creation

Parse the output from the create command. Show the user:
- **Issue identifier** (e.g., `ENGG-123`)
- **Title**
- Confirm that the issue was added to the linked project
