#!/usr/bin/env bash
set -uo pipefail

# 1. Get current branch
BRANCH=$(git branch --show-current 2>/dev/null) || { echo "WORKBRANCH: Not in a git repository."; exit 0; }
if [ -z "$BRANCH" ]; then
  echo "WORKBRANCH: Not on any branch (detached HEAD)."
  exit 0
fi

# 2. Read team prefix from config
TEAM="ENGG"
if [ -f .workbranch.json ] && which python3 >/dev/null 2>&1; then
  TEAM=$(python3 -c "import json; print(json.load(open('.workbranch.json')).get('team', 'ENGG'))" 2>/dev/null || echo "ENGG")
fi

echo "WORKBRANCH: Branch is $BRANCH (team: $TEAM)"

# 3. Extract ticket ID from branch name (matches TEAM-NNN anywhere in the branch)
TICKET_ID=""
if echo "$BRANCH" | grep -qoE "${TEAM}-[0-9]+"; then
  TICKET_ID=$(echo "$BRANCH" | grep -oE "${TEAM}-[0-9]+" | head -1)
fi

# 4. Fetch Linear ticket details if we have a ticket ID
if [ -n "$TICKET_ID" ] && which linear >/dev/null 2>&1 && which python3 >/dev/null 2>&1; then
  TICKET_JSON=$(linear issue view "$TICKET_ID" --json --no-pager 2>/dev/null) || TICKET_JSON=""
  if [ -n "$TICKET_JSON" ]; then
    TICKET_TITLE=$(echo "$TICKET_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))" 2>/dev/null || echo "")
    TICKET_STATE=$(echo "$TICKET_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('state',{}).get('name',''))" 2>/dev/null || echo "")
    TICKET_URL=$(echo "$TICKET_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('url',''))" 2>/dev/null || echo "")
    echo "WORKBRANCH: Linked ticket: $TICKET_ID — $TICKET_TITLE"
    [ -n "$TICKET_STATE" ] && echo "WORKBRANCH: Status: $TICKET_STATE"
    [ -n "$TICKET_URL" ] && echo "WORKBRANCH: URL: $TICKET_URL"
  fi
fi

# 5. Detect if inside a linked worktree (not the main worktree)
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON" ] && [ "$GIT_DIR" != "$GIT_COMMON" ]; then
  echo "WORKBRANCH: Worktree: $(pwd)"
fi

# 6. Check for open PR
if which gh >/dev/null 2>&1; then
  PR_JSON=$(gh pr view --json state,url,statusCheckRollup,reviews 2>/dev/null) || PR_JSON=""
  if [ -n "$PR_JSON" ] && which python3 >/dev/null 2>&1; then
    PR_STATE=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('state',''))" 2>/dev/null || echo "")
    PR_URL=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || echo "")
    if [ -n "$PR_STATE" ]; then
      CI_STATUS=$(echo "$PR_JSON" | python3 -c "
import sys,json
d=json.load(sys.stdin)
checks=d.get('statusCheckRollup',[]) or []
if not checks: print('no checks')
elif all(c.get('conclusion')=='SUCCESS' or c.get('status')=='COMPLETED' for c in checks): print('passing')
elif any(c.get('conclusion')=='FAILURE' for c in checks): print('failing')
else: print('pending')
" 2>/dev/null || echo "unknown")
      APPROVALS=$(echo "$PR_JSON" | python3 -c "
import sys,json
reviews=json.load(sys.stdin).get('reviews',[]) or []
approvals=len([r for r in reviews if r.get('state')=='APPROVED'])
print(f'{approvals} approval' + ('s' if approvals!=1 else ''))
" 2>/dev/null || echo "")
      echo "WORKBRANCH: PR: $PR_URL ($PR_STATE, CI $CI_STATUS, $APPROVALS)"
    fi
  fi
fi

# 7. Note config loaded
if [ -f .workbranch.json ]; then
  echo "WORKBRANCH: Config loaded (.workbranch.json)"
fi
