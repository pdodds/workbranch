# Workbranch

Development workflow orchestrator for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Describe a problem. Workbranch creates the ticket, sets up an isolated worktree, and guides you through implementation, PR, review, and cleanup — all without leaving the terminal.

## How it works

```
describe problem → /work → ticket + worktree → implement → /work-pr → PR → review → /work-done → cleanup
```

```
┌──────────────────────────────────────────────────────────────┐
│  1. Describe a problem, bug, or feature                     │
│     ↓                                                       │
│  2. /work — creates Linear ticket, branch, worktree         │
│     ↓                                                       │
│  3. Implement — code, test, commit                          │
│     ↓                                                       │
│  4. /work-pr — runs checks, pushes, opens PR                │
│     ↓                                                       │
│  5. Review — address feedback, push updates                 │
│     ↓                                                       │
│  6. /work-done — removes worktree, cleans up branch         │
└──────────────────────────────────────────────────────────────┘
```

## Prerequisites

**Claude Code** — [install docs](https://docs.anthropic.com/en/docs/claude-code)

**worktrunk** (`wt`) — manages git worktrees:
```sh
# See https://github.com/pdodds/worktrunk for installation
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

### 2. Grant permissions

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

## Quick start

```sh
# Start Claude Code
claude
```

Then describe a problem and run `/work`:

> The invoice upload times out on files over 20MB. /work

Workbranch creates a Linear ticket, sets up a worktree, and waits for your direction. Implement the fix, then run `/work-pr` to push and open a PR. After it merges, `/work-done` cleans up.

## Commands

| Command | What it does |
|---|---|
| `/work` | Describe a problem — creates Linear ticket, sets up worktree, prepares for implementation |
| `/work-status` | Show current ticket, worktree, PR status, and recent commits |
| `/work-pr` | Run checks, push branch, open PR linked to Linear ticket |
| `/work-done` | Clean up worktree and branch after PR is merged |
| `/work-issue` | Create an additional Linear issue |
| `/work-doc` | Create a Linear document |

## Configuration

Create a `.workbranch.json` at the repo root. All fields are optional:

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
| `team` | `ENGG` | Linear team prefix |
| `reviewers` | `[]` | GitHub usernames to request review from |
| `branch_prefix` | `{"bug":"fix","feature":"feat","improvement":"chore"}` | Maps issue type to branch prefix |
| `bootstrap` | — | Run after worktree creation (e.g. `npm install`) |
| `test` | — | Test command, run before PR |
| `lint` | — | Lint command, run before PR |
| `typecheck` | — | Type-check command, run before PR |

Worktree paths are managed by worktrunk, not this plugin. See `~/.config/worktrunk/config.toml`.

## Team support

Share `.workbranch.json` in the repo so the whole team uses the same config. Each team member authenticates their own CLIs (`linear auth`, `gh auth login`). The `reviewers` array controls who gets review requests on PRs created with `/work-pr`.

## Error recovery

| Succeeded | Failed | Recovery |
|---|---|---|
| Ticket created | Worktree creation | Retry `wt switch -c` manually, or delete ticket |
| Ticket + worktree | Bootstrap | Fix deps, re-run bootstrap |
| Checks pass | Push fails | Check remote access, retry |
| Push succeeds | PR creation fails | Retry `gh pr create` |
| PR merged | Worktree removal fails | `git worktree remove` manually |

Each step reports clearly when it fails. Earlier steps are not rolled back — you fix forward.

## Project structure

```
workbranch/
├── .claude-plugin/
│   └── plugin.json                # Plugin manifest (v2.0.0)
├── hooks/
│   ├── hooks.json                 # ConversationStart hook
│   └── conversation-start.sh     # Branch context injection
├── skills/
│   ├── work/SKILL.md             # /work — start working
│   ├── work-status/SKILL.md      # /work-status — show state
│   ├── work-pr/SKILL.md          # /work-pr — push and open PR
│   ├── work-done/SKILL.md        # /work-done — clean up
│   ├── work-issue/SKILL.md       # /work-issue — create issue
│   └── work-doc/SKILL.md         # /work-doc — create document
├── .workbranch.json.example       # Config template
├── LICENSE                        # Apache 2.0
└── README.md
```

## License

[Apache License 2.0](LICENSE)
