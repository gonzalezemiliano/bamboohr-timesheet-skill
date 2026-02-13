# Contributing

Thanks for your interest in contributing to the BambooHR Timesheet Skill! This guide explains how to get your changes reviewed and merged.

## How to Contribute

### 1. Fork and Clone

```bash
gh repo fork gonzalezemiliano/bamboohr-timesheet-skill --clone
cd bamboohr-timesheet-skill
```

### 2. Create a Branch

Create a descriptive branch from `main`:

```bash
git checkout -b fix/short-description
# or
git checkout -b feat/short-description
```

Use these prefixes:
- `feat/` — new features or capabilities
- `fix/` — bug fixes
- `docs/` — documentation changes
- `chore/` — maintenance, cleanup, CI

### 3. Make Your Changes

- Keep changes focused — one feature or fix per PR
- Update `README.md` if your change affects setup or usage
- Update `SKILL.md` if your change affects the AI agent instructions
- Test scripts manually before submitting (`init.sh`, `submit.sh`)

### 4. Commit and Push

```bash
git add <files>
git commit -m "feat: short description of the change"
git push origin feat/short-description
```

Write clear commit messages. Use [Conventional Commits](https://www.conventionalcommits.org/) style:
- `feat: add support for multiple calendars`
- `fix: handle empty API response in submit.sh`
- `docs: add troubleshooting entry for token expiration`

### 5. Open a Pull Request

```bash
gh pr create --title "feat: short description" --body "What this PR does and why"
```

Or use the GitHub web UI to create a PR targeting `main`.

## Review Process

All pull requests are reviewed by [@gonzalezemiliano](https://github.com/gonzalezemiliano) before merging. Direct pushes to `main` are not allowed.

What I look for:
- **Does it work?** — scripts should run without errors
- **Is it portable?** — changes to `SKILL.md` should work across AI agents (Claude Code, Gemini, Codex, etc.), not just one
- **Is it safe?** — no hardcoded credentials, employee IDs, or company-specific data
- **Is it documented?** — new features should be reflected in `README.md` and/or `SKILL.md`

## What You Can Work On

- Bug fixes in `init.sh` or `submit.sh`
- Support for additional calendar MCP servers
- New task mapping patterns in `SKILL.md`
- Documentation improvements
- Support for additional AI agents (installation guides)
- Localization or timezone handling improvements

## Code Style

- **Shell scripts**: POSIX-compatible bash, use `shellcheck` if available
- **Markdown**: Standard GitHub-flavored markdown
- **No external dependencies** beyond `bash`, `curl`, and `jq`

## Questions?

Open an [issue](https://github.com/gonzalezemiliano/bamboohr-timesheet-skill/issues) if you have questions or want to discuss a change before starting work.
