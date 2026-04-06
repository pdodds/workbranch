---
name: workbranch
description: Show the Linear project, issues, and documents linked to the current git branch
user_invocable: true
---

# /workbranch — Show linked project status

When this skill is invoked, follow these steps:

## 1. Get the current branch

Run:
```bash
git branch --show-current
```

Save the branch name for the next steps.

## 2. Read the team prefix

Check if `.workbranch.json` exists in the repository root. If it does, read it and extract the `team` field. If the file does not exist or has no `team` field, default to `ENGG`.

## 3. Find the linked Linear project

Run:
```bash
linear project list --json
```

Parse the JSON output (an array of project objects). Search for a project whose `description` field contains the marker `[branch: <branch-name>]`, where `<branch-name>` is the branch from step 1.

## 4. Display results

### If a matching project is found

Show a summary with:
- **Project name** and **status** (from `status.name`)
- **URL** (from `url`)

Then fetch and display the project's issues:
```bash
linear issue list --project "PROJECT_NAME" --all-states --all-assignees --json --no-pager
```
Show each issue with its `identifier`, `title`, and `state.name`.

Then fetch and display the project's documents:
```bash
linear doc list --project "PROJECT_NAME" --json
```
Show each document with its `title` and `url`.

Present everything in a clean, readable format. Group issues by state if there are many.

### If no matching project is found

Tell the user:
> No Linear project is linked to branch `<branch-name>`. Run `/workbranch-init` to create and link a project.
