# cs-thesis-writer-workspace

## Purpose
A workspace for writing a CS thesis using the TAU Typst thesis template (Tampere University).
The docs/ folder contains reference documentation for the thesis topic (marketing analytics agent).

## Structure
```
CLAUDE.md               # This file — Claude reads it every session
.mise.toml              # Tool versions (typst 0.14.2)
docs/                   # All documentation
  thesis/               # The actual thesis (Typst)
    tauthesis.typ       # Local copy of the TAU template package (do not edit)
    template/           # All writable content lives here
      main.typ          # Entry point — compile this file
      metadata.typ      # Author, title, thesis type, fonts, flags
      preamble.typ      # Custom commands/functions
      frontmatter/      # abstract.typ, preface.typ, glossary.typ, use-of-ai.typ
      mainmatter/       # index.typ + per-chapter files (01.typ, 02.typ, ...)
      appendices/       # index.typ + per-appendix files (A.typ, B.typ, ...)
      images/           # SVG/PNG images (no PDF images — use SVG for accessibility)
      bibliography.yaml # References (Hayagriva format)
      bibliography.bib  # References (BibLaTeX format, alternative)
  # Reference docs for thesis topic (read in order 00 → 06)
  00-README.md          # Project overview, doc map, tech stack
  01-proposal.md        # Architecture, data model, sandbox, POC milestones
  02-skills-catalog.md  # 20 skills across 8 categories (use cases)
  03-langgraph-guide.md # LangGraph concepts: ReAct, State, Nodes, Edges
  04-implementation-guide.md # Step-by-step build guide
  05-tools-reference.md # 4 tools: full implementation + design rationale
  06-system-prompts.md  # Lead agent + subagent system prompts
.claude/
  settings.json         # Project-scoped Claude Code config (do not touch global ~/.claude/)
  commands/             # Custom slash commands for this project
```

## Commands
```sh
# Compile thesis to PDF (development — fast, no accessibility checks)
typst compile docs/thesis/template/main.typ --root docs/thesis --font-path docs/thesis/fonts

# Watch for changes and auto-recompile (development)
typst watch docs/thesis/template/main.typ --root docs/thesis --font-path docs/thesis/fonts

# Compile for final submission (PDF/UA-1 accessibility standard)
typst compile docs/thesis/template/main.typ --root docs/thesis --font-path docs/thesis/fonts --pdf-standard ua-1

# Install tools (requires mise)
mise install
```
Note: `--root docs/thesis` is required because main.typ imports `../tauthesis.typ` (one level up).

## Conventions
- All config changes must go into `.claude/settings.json` — never modify `~/.claude/` or any global Claude Code config
- Tools are managed via `.mise.toml` (typst pinned to 0.14.2)
- tauthesis.typ is a local copy — do not modify it unless fixing a bug
- Write chapters in mainmatter/ as separate files and include them in mainmatter/index.typ
- Use SVG for vector graphics (not PDF) to maintain PDF/UA-1 accessibility
- Bibliography: use bibliography.yaml (Hayagriva) by default
