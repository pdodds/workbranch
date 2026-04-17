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
