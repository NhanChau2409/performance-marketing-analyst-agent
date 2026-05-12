# Performance Marketing Analyst Agent

**Design and Implementation of a LangGraph-Based Marketing Analytics Agent**
*An Exploration of Agentic Patterns for Autonomous Data Analysis*

Bachelor's thesis — Tampere University
Author: Nhan Chau | Examiner: Professor Ahmed Farooq

---

## Overview

This repository contains the source for a bachelor's thesis written in [Typst](https://typst.app/) using the official TAU (Tampere University) thesis template.

The thesis covers the design and implementation of a conversational AI agent for marketing analytics, built with LangGraph and FastAPI. Key topics include:

- The **ReAct loop** — how agents reason and act iteratively
- **Tool calling** — integrating SQL queries, Python sandboxes, and report generation
- **Multi-agent orchestration** — parallel subagents for data gathering
- **Prompt engineering** — structured skill templates that drive agent behavior

The `docs/` folder contains the full reference documentation for the marketing agent project itself (architecture, skills catalog, implementation guide, system prompts).

---

## Repository Structure

```
thesis/                 # Typst thesis source
  tauthesis.typ         # TAU template (do not edit)
  template/
    main.typ            # Entry point — compile this
    metadata.typ        # Title, author, thesis type, fonts
    preamble.typ        # Custom Typst commands
    frontmatter/        # Abstract, preface, glossary, AI use statement
    mainmatter/         # Chapter files (01.typ, 02.typ, …)
    appendices/         # Appendix files (A.typ, B.typ, …)
    images/             # SVG/PNG figures
    bibliography.yaml   # References (Hayagriva format)
docs/                   # Reference docs for the thesis topic
  00-README.md          # Project overview and doc map
  01-proposal.md        # Architecture, data model, POC milestones
  02-skills-catalog.md  # 20 agent skills across 8 categories
  03-langgraph-guide.md # LangGraph concepts: ReAct, State, Nodes, Edges
  04-implementation-guide.md  # Step-by-step build guide
  05-tools-reference.md # 4 tools: implementation + design rationale
  06-system-prompts.md  # Lead agent + subagent system prompts
```

---

## Prerequisites

- [mise](https://mise.jdx.dev/) — manages tool versions
- Typst 0.14.2 (installed via mise)

```sh
mise install
```

---

## Compiling the Thesis

```sh
# Development build (fast, no accessibility checks)
typst compile thesis/template/main.typ --root thesis --font-path thesis/fonts

# Watch mode (auto-recompile on save)
typst watch thesis/template/main.typ --root thesis --font-path thesis/fonts

# Final submission build (PDF/UA-1 accessibility standard)
typst compile thesis/template/main.typ --root thesis --font-path thesis/fonts --pdf-standard ua-1
```

> The `--root thesis` flag is required because `main.typ` imports `../tauthesis.typ`.

---

## Keywords

AI agent · LangGraph · ReAct · marketing analytics · large language models · tool calling · multi-agent systems
