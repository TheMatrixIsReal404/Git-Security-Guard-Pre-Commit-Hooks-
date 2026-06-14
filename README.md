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
