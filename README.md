# Workbranch

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin that turns a problem description into a complete development workflow: Linear ticket, isolated git worktree, implementation, PR, review, and cleanup — all driven from the terminal.

## The idea

Development has a lot of ceremony. You find a bug, you create a ticket, you make a branch, you set up a worktree, you implement, you run tests, you push, you open a PR, you link the ticket, you request reviewers, you wait, you merge, you clean up the branch. Each step is small but the overhead adds up, especially across a team.

Workbranch collapses this into three commands. You describe the problem in plain language. Claude handles the plumbing. You focus on the fix.

## The approach

Workbranch is opinionated. It assumes:

- **GitHub** for code and PRs (via `gh` CLI)
- **Linear** for tickets (via `linear` CLI)
- **Worktrunk** for git worktree management (via `wt` CLI)
- **Conventional commits** with ticket IDs for auto-linking
- **One ticket, one branch, one worktree** — isolated workspaces that don't interfere with each other

Every branch encodes the ticket ID in its name (`fix/ENGG-456-invoice-timeout`). This is the single source of truth linking git to Linear — no markers, no metadata files, no manual linking. The ConversationStart hook reads the branch name, fetches the ticket, checks for a PR, and injects all of that context into every Claude session automatically.

Worktree paths, hooks, and lifecycle are managed by [worktrunk](https://github.com/pdodds/worktrunk), not this plugin. Workbranch tells worktrunk what branch to create; worktrunk decides where it goes and how to bootstrap it.

## The main loop

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│  You: "Users are hitting a 500 when they upload invoices over    │
│        20MB. Trace shows a timeout in the extraction pipeline."  │
│                                                                  │
│  /work                                                           │
│    → Claude creates Linear ticket ENGG-456 (assigned to you)     │
│    → Claude creates worktree: fix/ENGG-456-invoice-timeout       │
│    → Claude runs bootstrap (npm install, etc.)                   │
│    → Claude waits for your direction                             │
│                                                                  │
│  You direct the implementation. Claude codes, tests, commits.    │
│                                                                  │
│  /work-pr                                                        │
│    → Runs lint, typecheck, tests                                 │
│    → Pushes branch, opens PR with Linear link                    │
│    → Requests reviewers from config                              │
│    → Linear ticket auto-transitions to In Review                 │
│                                                                  │
│  You review, test locally, approve, merge.                       │
│                                                                  │
│  /work-done                                                      │
│    → Removes worktree                                            │
│    → Deletes branch (local + remote)                             │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Walkthrough

### Starting work

Open Claude Code in your repo and describe what needs to happen:

```
> The invoice upload times out on files over 20MB. The trace shows
> the extraction pipeline hitting a 30s timeout. /work
```

Claude parses the description and presents its interpretation:

```
Type: bug
Title: Invoice upload timeout on files over 20MB
Description: Users hitting 500 on large invoice uploads. Extraction
pipeline timeout at 30s.
Acceptance criteria:
- Files up to 50MB upload without timeout
- Appropriate error message for files exceeding the limit

Confirm? (y/n)
```

After confirmation, Claude creates the Linear ticket, sets up the worktree, and reports:

```
Created ENGG-456: Invoice upload timeout on files over 20MB
URL: https://linear.app/team/issue/ENGG-456
Branch: fix/ENGG-456-invoice-upload-timeout
Worktree: ~/kodexa-wt/fix-ENGG-456-invoice-upload-timeout

When committing during this session, use this format:
  fix(extraction): description of change

  ENGG-456

Ready to implement. What's your approach, or should I investigate?
```

Claude does not auto-implement. You decide what happens next — "go fix it," "let me look at the trace first," or "here's what I think the issue is."

### Implementing

Work normally. Claude implements, writes tests, runs them, and commits with the conventional format:

```
fix(extraction): increase upload timeout to 120s for large files

ENGG-456
```

The ticket ID on its own line triggers Linear auto-linking — every commit shows up on the ticket.

### Opening a PR

When you're ready:

```
> /work-pr
```

Claude runs your configured checks (lint, typecheck, tests), pushes the branch, and opens a PR:

```
PR opened: https://github.com/org/repo/pull/42
Linear: https://linear.app/team/issue/ENGG-456
Reviewers: ghuser1, ghuser2
Waiting for review.
```

The PR body includes a "Test locally" section with the exact commands to run in the worktree, so reviewers know exactly how to verify.

### The fix cycle

If testing surfaces something, tell Claude in the same session. It stays in the same worktree, makes the fix, commits, pushes. The PR updates in place. Only spin up a new ticket (`/work-issue`) if the testing surfaced a genuinely separate bug.

### Cleaning up

After the PR merges:

```
> /work-done
```

Run this from your main repo checkout, not from inside the worktree. Claude removes the worktree, deletes the branch, and reports cleanup complete.

### Resuming in a new session

If you close your terminal and come back, the ConversationStart hook picks up where you left off. On any work branch, Claude automatically sees:

```
WORKBRANCH: Branch is fix/ENGG-456-invoice-timeout (team: ENGG)
WORKBRANCH: Linked ticket: ENGG-456 — Invoice upload timeout on files over 20MB
WORKBRANCH: Status: In Progress
WORKBRANCH: Worktree: ~/kodexa-wt/fix-ENGG-456-invoice-timeout
WORKBRANCH: PR: https://github.com/org/repo/pull/42 (OPEN, CI passing, 0 approvals)
```

No commands needed — context is always there.

## Commands

| Command | What it does |
|---|---|
| `/work` | Describe a problem — creates Linear ticket, sets up worktree, prepares for implementation |
| `/work-status` | Show current ticket, worktree, PR status, and recent commits |
| `/work-pr` | Run checks, push branch, open PR linked to Linear ticket |
| `/work-done` | Clean up worktree and branch after PR is merged (run from main worktree) |
| `/work-issue` | Create an additional Linear issue (e.g. when a fix surfaces a separate bug) |
| `/work-doc` | Create a Linear document (design docs, planning docs, attached to current ticket) |

## Conventions

### Branch naming

```
type/TEAM-NNN-slug
```

Examples: `fix/ENGG-456-invoice-timeout`, `feat/ENGG-789-sso-support`, `chore/ENGG-101-update-deps`

The type maps from the `branch_prefix` config. The ticket ID is extracted automatically by matching the team prefix pattern — custom prefix values work fine.

### Commit messages

Conventional commits with the ticket ID on a blank line:

```
fix(extraction): increase upload timeout to 120s for large files

ENGG-456
```

The ticket ID on its own line triggers Linear auto-linking.

### PR body

```markdown
## Summary
- Increased extraction pipeline timeout from 30s to 120s
- Added size validation with clear error message for files over 50MB

## Linear
Closes ENGG-456

## Test locally
cd ~/kodexa-wt/fix-ENGG-456-invoice-timeout && npm install && npm test
```

The `Closes ENGG-456` line auto-transitions the Linear ticket when the PR merges.

## Prerequisites

**Claude Code** — [install docs](https://docs.anthropic.com/en/docs/claude-code)

**worktrunk** (`wt`) — manages git worktrees. Configure your preferred worktree path layout in `~/.config/worktrunk/config.toml`:
```toml
worktree-path = "~/kodexa-wt/{{ branch | sanitize }}"
```

**Linear CLI** — ticket management:
```sh
npm install -g @anthropic-ai/linear-cli
linear auth
```

**GitHub CLI** — PR management:
```sh
brew install gh
gh auth login
```

## Installation

### 1. Install the plugin

Clone the repo and point Claude Code at it:

```sh
git clone https://github.com/pdodds/workbranch.git
claude --plugin-dir /path/to/workbranch
```

Or use the plugin marketplace from within Claude Code:

```
/plugin marketplace add pdodds/workbranch
/plugin install workbranch@pdodds-workbranch
```

### 2. Configure your repo

Copy the example config to your repo root:

```sh
cp /path/to/workbranch/.workbranch.json.example .workbranch.json
```

Edit `.workbranch.json` with your team's settings. At minimum, set `team` and `reviewers`.

### 3. Grant permissions

Add to your project's `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)", "Bash(python3:*)", "Bash(linear:*)",
      "Bash(gh:*)", "Bash(wt:*)", "Bash(which:*)"
    ]
  }
}
```

Or let Claude Code prompt you on first use.

## Configuration

`.workbranch.json` at the repo root:

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

| Field | Default | Purpose |
|---|---|---|
| `team` | `ENGG` | Linear team prefix for ticket creation and branch naming |
| `reviewers` | `[]` | GitHub usernames to request as PR reviewers |
| `branch_prefix` | `{"bug":"fix","feature":"feat","improvement":"chore"}` | Maps issue type to branch name prefix |
| `bootstrap` | — | Command to run after worktree creation (install deps, codegen) |
| `test` | — | Test suite command, run before PR, shown in PR body |
| `lint` | — | Lint command, run before PR |
| `typecheck` | — | Type-check command, run before PR |

All fields except `team` are optional. Claude skips any commands that aren't defined.

Worktree paths are managed by worktrunk (`~/.config/worktrunk/config.toml`), not this plugin.

## Team workflow

Workbranch is designed for teams. Here's how it works:

1. **Shared config** — commit `.workbranch.json` to the repo (or gitignore it if teams differ). Everyone uses the same conventions, branch prefixes, and check commands.

2. **Individual auth** — each team member runs `linear auth` and `gh auth login` on their own machine. Tickets are assigned to whoever describes the issue. PRs are opened under their GitHub account.

3. **Reviewers** — the `reviewers` array in config controls who gets review requests. Set it to your team's GitHub usernames. Claude never tries to add you as a reviewer on your own PR.

4. **Assigning to others** — by default, tickets are assigned to the person who runs `/work`. To assign to someone else, just say: "assign this to @juandev" — Claude uses `--assignee juandev` on the Linear ticket.

5. **Worktree isolation** — each piece of work gets its own worktree. Team members can work on different tickets simultaneously without branch conflicts.

## Error recovery

Each workflow step reports what succeeded before failing. You fix forward — earlier steps are not rolled back.

| Succeeded | Failed | Recovery |
|---|---|---|
| Ticket created | Worktree creation | Retry `wt switch -c` manually, or delete ticket in Linear |
| Ticket + worktree | Bootstrap | Fix deps, re-run bootstrap command manually |
| Checks pass | Push fails | Check remote access, retry push |
| Push succeeds | PR creation fails | Retry `gh pr create` manually |
| PR merged | Worktree removal fails | Run `git worktree remove` manually, then `git worktree prune` |

## Project structure

```
workbranch/
├── .claude-plugin/
│   └── plugin.json                # Plugin manifest (v2.0.0)
├── hooks/
│   ├── hooks.json                 # ConversationStart hook definition
│   └── conversation-start.sh     # Auto-injects ticket, worktree, PR context
├── skills/
│   ├── work/SKILL.md             # /work — describe problem, create ticket + worktree
│   ├── work-status/SKILL.md      # /work-status — show current state
│   ├── work-pr/SKILL.md          # /work-pr — run checks, push, open PR
│   ├── work-done/SKILL.md        # /work-done — clean up after merge
│   ├── work-issue/SKILL.md       # /work-issue — create additional issue
│   └── work-doc/SKILL.md         # /work-doc — create Linear document
├── .workbranch.json.example       # Config template — copy to your repo
├── LICENSE                        # Apache 2.0
└── README.md
```

## License

[Apache License 2.0](LICENSE)
