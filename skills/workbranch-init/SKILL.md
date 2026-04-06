---
name: workbranch-init
description: Create a new Linear project linked to the current git branch
user_invocable: true
---

# /workbranch-init — Link branch to a new Linear project

When this skill is invoked, follow these steps:

## 1. Check that the `linear` CLI is installed

Run:
```bash
which linear
```

If the command is not found, tell the user:
> The `linear` CLI is not installed. Install it with `npm install -g @linear/cli` or `brew install linear`, then try again.

Stop here if `linear` is not available.

## 2. Get the current branch

Run:
```bash
git branch --show-current
```

Save the branch name for the next steps.

## 3. Check if a project is already linked

Run:
```bash
linear project list --json
```

Parse the JSON output (an array of project objects). Search for a project whose `description` field contains the marker `[branch: <branch-name>]`, where `<branch-name>` is the branch from step 2.

### If a matching project is found

Tell the user the branch is already linked and show:
- **Project name** (from `name`)
- **URL** (from `url`)

Stop here — do not create a duplicate project.

## 4. Ask the user for a project name

Suggest a sensible default name based on the branch name:
- Strip common prefixes like `feature/`, `fix/`, `chore/`, `bugfix/`, `hotfix/`, `release/`
- Replace hyphens and underscores with spaces
- Convert to Title Case
- Example: `feature/auth-rework` becomes "Auth Rework"

Present the suggestion and ask the user to confirm or provide a different name. Also ask if they want to add a short description of the project's purpose (optional).

## 5. Read the team prefix

Check if `.workbranch.json` exists in the repository root. If it does, read it and extract the `team` field. If the file does not exist or has no `team` field, default to `ENGG`.

## 6. Create the Linear project

Build the description by combining:
- Any user-provided context about the project's purpose (if given in step 4)
- The branch marker: `[branch: <branch-name>]`

The description must always end with the `[branch: <branch-name>]` marker so that `/workbranch` can discover the link later.

For example, if the user provided context "Rework the authentication flow to support SSO", the description would be:
```
Rework the authentication flow to support SSO

[branch: feature/auth-rework]
```

If no context was provided, the description is just:
```
[branch: feature/auth-rework]
```

Run:
```bash
linear project create --name "PROJECT_NAME" --description "DESCRIPTION" --team TEAM --status started --json
```

Where:
- `PROJECT_NAME` is the confirmed name from step 4
- `DESCRIPTION` is the constructed description containing the branch marker
- `TEAM` is the team from step 5

## 7. Confirm creation

Parse the JSON output from the create command. Show the user:
- **Project name**
- **URL** (from `url`)
- Confirm that the project is now linked to the current branch

Let the user know they can run `/workbranch` at any time to see the project status, issues, and documents.
