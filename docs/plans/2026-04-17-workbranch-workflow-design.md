# Workbranch Workflow Orchestrator — Design

## Overview

Convert workbranch from a Linear context-injection plugin into an opinionated development workflow orchestrator for Claude Code. The full loop: problem description → Linear ticket → git worktree → implement → PR → review → cleanup.

## Dependencies

- **worktrunk** (`wt` CLI) — worktree lifecycle management (also owns worktree path configuration)
- **linear** CLI v2 — ticket management
- **gh** CLI — PR creation and management
- **git** — branch/worktree operations
- **python3** or **jq** — JSON parsing in hook scripts

## Configuration

`.workbranch.json` per repo:

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

- **team** — Linear team prefix for ticket creation and branch naming.
- **reviewers** — GitHub usernames to request as PR reviewers. Required for team workflows. If empty or missing, Claude prompts for a reviewer at PR creation time.
- **branch_prefix** — maps Linear issue types to branch prefixes. Claude infers issue type from context. Keys are arbitrary; values become the branch prefix.
- **bootstrap** — command to run after creating a worktree (deps, codegen).
- **test** — test suite command. Run before committing, included in PR body.
- **lint** — linter command. Run before committing.
- **typecheck** — type checker command. Run before committing.

All command fields are optional. Claude skips any that aren't defined.

**Note:** Worktree paths are managed by worktrunk's own configuration (`~/.config/worktrunk/config.toml` `worktree-path` template), not by this plugin. Configure worktrunk separately to use your preferred layout (e.g. `~/kodexa-wt/{{ branch | sanitize }}`).

## Branch Naming Convention

Format: `type/TEAM-123-slug`

Examples:
- `fix/ENGG-456-invoice-timeout`
- `feat/ENGG-789-sso-support`
- `chore/ENGG-101-update-deps`

The ticket ID embedded in the branch name is the link between git and Linear — no marker convention needed. The ConversationStart hook extracts the ticket ID by matching the team prefix pattern (`TEAM-\d+`) anywhere in the branch name, so custom `branch_prefix` values are supported.

## Commit Message Format

Conventional commits with ticket ID on its own line for Linear auto-linking:

```
type(scope): description

ENGG-123
```

Example:
```
fix(extraction): increase upload timeout to handle files over 20MB

ENGG-456
```

This format is communicated to Claude via the `/work` skill's closing output, so it applies to all commits during the work session.

## The Main Loop

```
You describe a problem
  → /work
    → Claude creates Linear ticket (assigned to you, started)
    → Claude creates worktree via `wt switch -c`
    → Claude bootstraps the worktree
    → Claude waits for your direction
  → You direct implementation
    → Claude implements + tests + commits (conventional format with ticket ID)
  → /work-pr
    → Claude pushes, opens PR (configured reviewers requested)
    → Linear ticket auto-transitions to In Review
  → You review, test locally, approve, merge
  → /work-done (run from main worktree, not the work worktree)
    → Claude removes worktree via `wt remove <branch>`
    → Cleans up branch
```

## ConversationStart Hook

Fires on every conversation. Injects worktree, ticket, and PR context.

Output:
```
WORKBRANCH: Branch is fix/ENGG-456-invoice-timeout (team: ENGG)
WORKBRANCH: Linked ticket: ENGG-456 — Invoice upload timeout on files over 20MB
WORKBRANCH: Status: In Progress
WORKBRANCH: Worktree: ~/kodexa-wt/fix-ENGG-456-invoice-timeout
WORKBRANCH: PR: #42 (open, CI passing, 1 approval)
```

Logic:
1. Get current branch via `git branch --show-current`
2. Read `.workbranch.json` for team prefix
3. Extract ticket ID from branch name by matching `TEAM-\d+` pattern (works regardless of branch prefix)
4. Fetch ticket details via `linear issue view TEAM-123 --json --no-pager`
5. Detect worktree via `git rev-parse --git-dir` vs `--git-common-dir` (linked worktree when they differ)
6. Check for open PR on this branch via `gh pr view --json state,url,statusCheckRollup,reviews`
7. Output the context summary

Lines that fail (no ticket, no PR, not in worktree) are silently skipped.

## Commands

### `/work` — Start working on something

The main entry point. You describe a problem, Claude sets everything up.

**Input:** Natural language description of a bug, feature, or task.

**Steps:**
1. Validate config — read `.workbranch.json`, report loaded settings. Check `linear`, `wt`, `gh` are available.
2. Parse intent — determine issue type from context. Map to `branch_prefix` config (bug → fix, feature → feat, etc.). Ask if ambiguous.
3. Create Linear ticket via `linear issue create --title "..." --description "..." --team TEAM --assignee self --start --no-interactive`. Parse the text output to extract the ticket identifier (e.g. `ENGG-456`). Then fetch full details via `linear issue view ENGG-456 --json --no-pager`.
4. Create worktree via `wt switch -c type/TEAM-123-slug`.
5. Run bootstrap command from `.workbranch.json` if defined.
6. Report: ticket ID + URL, worktree path, commit format reminder, ready for direction.

**Commit format reminder in output:**
```
When committing, use this format:
  type(scope): description

  ENGG-456
```

Claude does NOT auto-implement. It sets up the workspace and waits for direction.

**Partial failure handling:**
- If ticket creation succeeds but worktree creation fails: report the ticket ID and URL so the user can retry `wt switch -c` manually or delete the ticket.
- If bootstrap fails: report the error but keep the worktree. The user can fix and re-run.

### `/work-status` — Show current state

Replaces the old `/workbranch` command.

Shows:
- Linked Linear ticket: ID, title, status, assignee, URL
- Worktree path and state (clean/dirty)
- PR status if one exists: URL, CI status, review status
- Recent commits on this branch

### `/work-pr` — Push and open a PR

**Steps:**
1. Run test, lint, typecheck commands from config (skip any not defined). Stop on first failure.
2. Push branch via `git push -u origin <branch>`.
3. Open PR via `gh pr create` with body:
   ```markdown
   ## Summary
   <1-3 bullet points derived from the ticket>

   ## Linear
   Closes ENGG-456

   ## Test locally
   ```
   cd <worktree-path> && <bootstrap> && <test>
   ```
   ```
   The worktree path in the PR body comes from `$(pwd)`, not config.
4. Request reviewers from the `reviewers` field in `.workbranch.json` via `gh pr edit --add-reviewer user1,user2`. If no reviewers are configured, ask the user for a GitHub username.
5. Report: PR URL, Linear ticket link.

The "Closes ENGG-456" line triggers Linear auto-transition to In Review.

### `/work-done` — Clean up after merge

**Important:** This command should be run from the main worktree, not from inside the work worktree being cleaned up. If Claude detects it's inside the target worktree, it should instruct the user to switch to the main repo first, or use `wt switch main` before cleanup.

**Steps:**
1. Verify the PR is merged via `gh pr view <branch> --json state`.
2. Remove the worktree via `wt remove <branch>` (specifying the branch name, not relying on current directory).
3. Delete the remote branch via `git push origin --delete <branch>` (skip if already deleted by GitHub auto-delete).
4. Report: cleanup complete.

If the PR isn't merged yet, warn and ask for confirmation before proceeding.

### `/work-issue` — Create an additional issue

Creates an issue in Linear using the team prefix from config. Assigns to the authenticated user. If on a work branch with a ticket ID, offers to note the relationship. Useful when implementation surfaces a separate bug.

### `/work-doc` — Create a Linear document

Creates a design doc or planning document in Linear. When on a work branch with a ticket ID, attaches the document to the current issue via `linear doc create --title "..." --content-file /tmp/... --issue TICKET_ID`.

## Team Support

- Tickets are assigned to the person who described the issue (via `--assignee self`).
- PRs request reviewers from the `reviewers` list in `.workbranch.json`. GitHub usernames.
- Team members each authenticate their own `linear` and `gh` CLIs.
- The `.workbranch.json` config is shared per repo so everyone uses the same conventions.
- Branch naming and commit conventions are enforced by the plugin, not individual discipline.
- To assign a ticket to someone else, tell Claude: "assign this to @username" — Claude uses `--assignee username` on issue creation.

## Error Recovery

Each workflow step reports what succeeded before failing. Partial states:

| Succeeded | Failed | Recovery |
|-----------|--------|----------|
| Ticket created | Worktree creation | Retry `wt switch -c` manually, or delete ticket in Linear |
| Ticket + worktree | Bootstrap | Fix deps, re-run bootstrap command manually |
| Checks pass | Push fails | Check remote access, retry push |
| Push succeeds | PR creation fails | Retry `gh pr create` manually |
| PR merged | Worktree removal fails | Run `git worktree remove` manually, `git worktree prune` |

## Migration from Current Plugin

- `/workbranch` → `/work-status`
- `/workbranch-init` → removed (ticket + branch created together by `/work`)
- `/workbranch-issue` → `/work-issue`
- `/workbranch-doc` → `/work-doc`
- `[branch: name]` project marker convention → removed (ticket ID in branch name)
- ConversationStart hook → rewritten to inject richer context

## Prerequisites for Users

1. Claude Code installed
2. `wt` (worktrunk) installed and configured with desired `worktree-path` template
3. `linear` CLI installed and authenticated (`linear auth`)
4. `gh` CLI installed and authenticated (`gh auth login`)
5. `.workbranch.json` in each repo with team prefix, reviewers, and commands
