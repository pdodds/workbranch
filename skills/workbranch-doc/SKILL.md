---
name: workbranch-doc
description: Create a Linear document in the project linked to the current git branch
user_invocable: true
---

# /workbranch-doc — Create a document in the linked project

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

Extract the `slugId` field from the matched project — this is needed to create the document.

### If no matching project is found

Tell the user:
> No Linear project is linked to branch `<branch-name>`. Run `/workbranch-init` to create and link a project first.

Stop here — a document cannot be created without a linked project.

## 3. Determine the document title and content

If the user provided a title and/or content along with the command, use those directly.

If the user has been discussing design, scope, architecture, or other topics earlier in the conversation, offer to generate a document from that context. Present the inferred title and a summary of the content to the user for confirmation before proceeding.

If there is no context to infer from and the user did not provide details, ask the user for:
- **Title** (required): a short name for the document
- **Content** (optional): the document body in Markdown

## 4. Create the Linear document

For short content (a few lines), run:
```bash
linear doc create --title "TITLE" --content "CONTENT" --project "PROJECT_SLUG_ID"
```

For longer content (more than a few lines), write the content to a temp file first and use `--content-file`:
```bash
cat > /tmp/workbranch-doc.md << 'DOCEOF'
CONTENT_HERE
DOCEOF
linear doc create --title "TITLE" --content-file /tmp/workbranch-doc.md --project "PROJECT_SLUG_ID"
```

Where:
- `TITLE` is the document title from step 3
- `CONTENT` is the document body from step 3
- `PROJECT_SLUG_ID` is the `slugId` of the matched project from step 2

**Important:** The `--project` flag takes the project's `slugId`, not the project name.

## 5. Confirm creation

Show the user:
- **Document title**
- Confirm that the document was added to the linked project
