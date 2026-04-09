# cs-thesis-writer-workspace

## Purpose
A workspace for writing and iterating on a CS thesis. Claude assists with drafting, editing, structuring, and reviewing thesis content.

## Structure
```
CLAUDE.md               # This file — Claude reads it every session
.claude/
  settings.json         # Project-scoped Claude Code config (do not touch global ~/.claude/)
  commands/             # Custom slash commands for this project
```

## Conventions
- All config changes must go into `.claude/settings.json` in this repo — never modify `~/.claude/` or any global Claude Code config
- Keep writing organized by iteration folders (e.g. `iteration-1/`, `iteration-2/`)

## Commands
_Add build/test/lint commands here as the project evolves._
