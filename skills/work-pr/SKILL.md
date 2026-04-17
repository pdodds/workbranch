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
