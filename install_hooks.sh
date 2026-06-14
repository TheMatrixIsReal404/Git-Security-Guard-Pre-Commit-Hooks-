#!/bin/bash
#
# install_hooks.sh — Git Security Guard installer
#
# Installs the pre-commit and commit-msg hooks into the current repo's
# .git/hooks directory, sets up git-secrets with AWS provider rules,
# and writes HOOKS_README.md documenting everything.
#
# Usage:
#   ./install_hooks.sh
#
# Run this script from anywhere inside the target git repository
# (it must sit alongside the pre-commit and commit-msg files it installs).

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo -e "${RED}✖ Error: not inside a git repository.${NC}"
    echo "  cd into your repo and re-run this script."
    exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
HOOKS_DIR="$REPO_ROOT/.git/hooks"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/pre-commit" ] || [ ! -f "$SCRIPT_DIR/commit-msg" ]; then
    echo -e "${RED}✖ Error: pre-commit and/or commit-msg not found next to install_hooks.sh${NC}"
    echo "  Expected them in: $SCRIPT_DIR"
    exit 1
fi

echo -e "${BLUE}${BOLD}🔧 Installing Git Security Guard into:${NC} $REPO_ROOT"
echo ""

# ---------------------------------------------------------------------------
# 1. Copy hooks + chmod +x
# ---------------------------------------------------------------------------
cp "$SCRIPT_DIR/pre-commit" "$HOOKS_DIR/pre-commit"
cp "$SCRIPT_DIR/commit-msg" "$HOOKS_DIR/commit-msg"
chmod +x "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/commit-msg"

echo -e "${GREEN}✓${NC} Installed ${BOLD}pre-commit${NC} -> $HOOKS_DIR/pre-commit"
echo -e "${GREEN}✓${NC} Installed ${BOLD}commit-msg${NC} -> $HOOKS_DIR/commit-msg"
echo -e "${GREEN}✓${NC} Marked both hooks executable (chmod +x)"
echo ""

# ---------------------------------------------------------------------------
# 2. Install git-secrets if not present
# ---------------------------------------------------------------------------
GIT_SECRETS_AVAILABLE=0

if command -v git-secrets >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} git-secrets already installed"
    GIT_SECRETS_AVAILABLE=1
else
    echo -e "${YELLOW}…${NC} git-secrets not found, attempting installation..."

    if command -v brew >/dev/null 2>&1; then
        brew install git-secrets && GIT_SECRETS_AVAILABLE=1
    elif command -v apt-get >/dev/null 2>&1; then
        TMP_DIR=$(mktemp -d)
        if git clone -q https://github.com/awslabs/git-secrets.git "$TMP_DIR/git-secrets" \
            && (cd "$TMP_DIR/git-secrets" && sudo make install >/dev/null 2>&1 || make install PREFIX="$HOME/.local" >/dev/null 2>&1); then
            export PATH="$HOME/.local/bin:$PATH"
            if command -v git-secrets >/dev/null 2>&1; then
                GIT_SECRETS_AVAILABLE=1
            fi
        fi
        rm -rf "$TMP_DIR"
    fi

    if [ "$GIT_SECRETS_AVAILABLE" -eq 1 ]; then
        echo -e "${GREEN}✓${NC} git-secrets installed successfully"
    else
        echo -e "${YELLOW}⚠${NC} Could not auto-install git-secrets."
        echo "   Install manually: https://github.com/awslabs/git-secrets"
        echo "   (The custom pre-commit/commit-msg hooks above are installed and active regardless.)"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Register AWS provider rules with git-secrets
# ---------------------------------------------------------------------------
if [ "$GIT_SECRETS_AVAILABLE" -eq 1 ]; then
    # NOTE: deliberately NOT calling `git secrets --install` — that command
    # overwrites .git/hooks/pre-commit and commit-msg with its own scripts,
    # which would clobber the hooks we just installed above. Instead we just
    # register the AWS patterns in this repo's config; our pre-commit hook
    # (above) calls `git secrets --pre_commit_hook` itself when available.
    git secrets --register-aws "$REPO_ROOT" >/dev/null 2>&1
    echo -e "${GREEN}✓${NC} Registered AWS provider rules with git-secrets"
else
    echo -e "${YELLOW}⚠${NC} Skipped AWS provider rule registration (git-secrets unavailable)"
fi

echo ""

# ---------------------------------------------------------------------------
# 4. Write HOOKS_README.md
# ---------------------------------------------------------------------------
cat > "$REPO_ROOT/HOOKS_README.md" << 'EOF'
# 🔒 Git Security Guard — Hooks Reference

This repository is protected by two local git hooks installed via
`install_hooks.sh`. They run automatically on every commit and require
no action from you beyond writing normal commits.

## What each hook does

### `pre-commit`
Scans every staged file for common secret patterns before a commit is
allowed to proceed:

| Check               | Pattern (simplified)                                  | Severity |
|---------------------|--------------------------------------------------------|----------|
| AWS Access Key ID    | `AKIA[0-9A-Z]{16}`                                      | Blocked (red) |
| Private key          | `-----BEGIN ...` (PEM headers)                          | Blocked (red) |
| Hardcoded password   | `password = "..."` / `password = '...'`               | Warning (yellow) |
| JWT token             | `eyJ...​.eyJ...​.signature`                              | Warning (yellow) |

Any match — red or yellow — exits with status `1` and **blocks the
commit** so the secret never reaches the repository history. Findings
are printed with the filename and line number so you can fix them
quickly.

### `commit-msg`
Validates that your commit message follows the
[Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(optional-scope): <description>
```

Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`,
`chore`, `ci`, `perf`, `build`, `revert`

Examples of valid messages:
```
feat: add login page
fix(auth): resolve token expiry bug
docs: update API usage examples
```

If your message doesn't match, the commit is rejected with an
explanation and examples.

### git-secrets (AWS rules)
If [git-secrets](https://github.com/awslabs/git-secrets) is available,
this installer also registers AWS's built-in provider rules
(`git secrets --register-aws`) for an extra layer of credential
scanning on top of the custom checks above.

## How to install

From the repo root, run:

```bash
bash install_hooks.sh
```

This copies `pre-commit` and `commit-msg` into `.git/hooks/`, makes
them executable, and (if possible) installs and configures
`git-secrets`.

> **Note:** `.git/hooks` is local to your clone and is **not** tracked
> by git. Anyone who clones this repo fresh needs to run
> `install_hooks.sh` once to enable these protections locally.

## How to bypass in emergencies

If you are absolutely certain a block is a false positive (e.g. a
test fixture that intentionally contains a fake key), you can skip
both hooks for a single commit with:

```bash
git commit --no-verify
```

**Use this sparingly** — it disables both the secret scan and the
commit message check for that commit. Prefer fixing the underlying
issue (removing the secret, rewording the message) whenever possible.
EOF

echo -e "${GREEN}✓${NC} Wrote ${BOLD}HOOKS_README.md${NC} -> $REPO_ROOT/HOOKS_README.md"
echo ""
echo -e "${GREEN}${BOLD}🎉 Git Security Guard installed successfully!${NC}"
echo -e "   Every commit will now be scanned for secrets and checked"
echo -e "   for Conventional Commits formatting. See HOOKS_README.md for details."
