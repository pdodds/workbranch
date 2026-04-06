# Workbranch

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin that connects git branches to [Linear](https://linear.app) projects. Workbranch automatically injects project context into every conversation — issues, documents, and status — so you never have to context-switch between your terminal and your project tracker.

Big work gets Linear documents for planning and design. Small fixes get Linear issues for tracking. Branch context is automatic.

## How it works

```
┌─────────────────────────────────────────────────────┐
│  You start a Claude Code conversation on a branch   │
│                                                     │
│  ConversationStart hook fires automatically         │
│    ↓                                                │
│  Reads current git branch                           │
│    ↓                                                │
│  Searches Linear for a project with                 │
│    [branch: <branch-name>] in its description       │
│    ↓                                                │
│  Injects project status, issues, and documents      │
│  into the session context                           │
└─────────────────────────────────────────────────────┘
```

Projects are linked to branches via a `[branch: <name>]` marker in the Linear project description. Once linked, every conversation on that branch starts with full project context — no commands needed.

## Prerequisites

Install and authenticate the [Linear CLI](https://www.npmjs.com/package/@anthropic-ai/linear-cli):

```sh
npm install -g @anthropic-ai/linear-cli
linear auth
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

The plugin's hooks run `git`, `python3`, and `linear` commands. Claude Code will prompt you to allow these on first use, or you can pre-approve them by adding to your project's `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(python3:*)",
      "Bash(linear:*)"
    ]
  }
}
```

## Quick start

```sh
# Switch to a feature branch
git checkout -b feature/my-feature

# Start Claude Code (the hook auto-detects your branch)
claude
```

Then inside Claude Code:

1. **`/workbranch-init`** — creates a Linear project linked to your branch
2. **`/workbranch-issue`** — creates issues as you work
3. **`/workbranch-doc`** — creates design docs for bigger efforts
4. **`/workbranch`** — shows the full project status at any time

The ConversationStart hook runs automatically on every session, so project context is always there without running any commands.

## Commands

| Command | What it does |
|---|---|
| `/workbranch` | Show the linked project's status, issues, and documents |
| `/workbranch-init` | Create a new Linear project and link it to the current branch |
| `/workbranch-issue` | Create a Linear issue in the linked project |
| `/workbranch-doc` | Create a Linear document in the linked project |

## Configuration

Optionally create a `.workbranch.json` file at your repo root to set the Linear team prefix (defaults to `ENGG`):

```json
{
  "team": "YOUR_TEAM"
}
```

See [`.workbranch.json.example`](.workbranch.json.example) for a template.

## Project structure

```
workbranch/
├── .claude-plugin/
│   └── plugin.json                # Plugin manifest
├── hooks/
│   └── hooks.json                 # ConversationStart hook
├── skills/
│   ├── workbranch/SKILL.md        # /workbranch — show project status
│   ├── workbranch-init/SKILL.md   # /workbranch-init — link branch to project
│   ├── workbranch-issue/SKILL.md  # /workbranch-issue — create issues
│   └── workbranch-doc/SKILL.md    # /workbranch-doc — create documents
├── .workbranch.json.example       # Config template
├── LICENSE                        # Apache 2.0
└── README.md
```

## License

[Apache License 2.0](LICENSE)
