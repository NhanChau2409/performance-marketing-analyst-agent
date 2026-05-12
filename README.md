# Performance Marketing Analyst Agent

A conversational AI agent that answers marketing questions by querying a PostgreSQL database, running Python analytics, and generating reports — built on **LangGraph**, **FastAPI**, and **React**.

This repository is the companion code for the bachelor's thesis:
> *Design and Implementation of a LangGraph-Based Marketing Analytics Agent: An Exploration of Agentic Patterns for Autonomous Data Analysis*
> Nhan Chau — Tampere University

---

## What This Project Is

Most LLM demos stop at "call the API and print the reply." This project goes further: it builds a **real agent system** with tool use, state management, interrupt-based human-in-the-loop confirmation, and multi-agent orchestration. The domain is marketing analytics — campaign performance, channel attribution, funnel drop-offs — but the architecture generalises to any data analysis problem.

The agent can:
- Query a marketing database in natural language and explain the results
- Generate matplotlib charts and Excel reports on demand
- Delegate parallel data-gathering tasks to sub-agents
- Stream real-time progress to a chat UI over SSE
- Pause before executing tools and ask the user for confirmation

---

## Repository Layout

```
docs/
  00-README.md              # Documentation map — start here
  01-proposal.md            # Architecture, data model, POC milestones
  02-skills-catalog.md      # 20 agent skills across 8 categories
  03-langgraph-guide.md     # LangGraph concepts: ReAct, State, Nodes, Edges
  04-implementation-guide.md# Step-by-step build guide
  05-tools-reference.md     # 4 tools: implementation + design rationale
  06-system-prompts.md      # Lead agent + subagent system prompts
  thesis/                   # Typst thesis source (TAU template)
    tauthesis.typ           # TAU template (do not edit)
    template/
      main.typ              # Entry point — compile this
      metadata.typ          # Title, author, thesis type, fonts
      mainmatter/           # Chapter files (01.typ – 06.typ)
      frontmatter/          # Abstract, preface, glossary, AI use statement
      appendices/           # Appendix files
      images/               # SVG/PNG figures
      bibliography.yaml     # References (Hayagriva)
marketing-agent/            # Python backend (FastAPI + LangGraph)
  src/marketing_agent/
    api/                    # FastAPI app, SSE streaming route
    graph/                  # LangGraph graph, nodes, router
    tools/                  # 4 tools: list_tables, describe_table, query_data, render_chart
    skills/                 # Prompt templates (weekly_report, campaign_analysis, …)
    models/                 # Pydantic state models
    db/                     # SQLAlchemy async connection + seed script
  scripts/seed_data.py      # Populates the database with sample marketing data
  pyproject.toml
  Dockerfile
  docker-compose.yml
web/                        # React + Tailwind chat UI
  src/
    App.tsx
    components/             # ChatView, MessageBubble, ToolCallBlock
    lib/adapter.ts          # SSE stream parser
  Dockerfile
```

---

## Architecture

```
User (browser)
    │  HTTP / SSE
    ▼
FastAPI  ──SSE stream──►  React chat UI
    │
    ▼
LangGraph ReAct graph
    ├── lead_agent node   (Claude / GPT-4o)
    ├── router node       (tool call or END)
    └── tool_executor node
            ├── list_tables      — discover available tables
            ├── describe_table   — get column names + types
            ├── query_data       — run a read-only SQL query
            └── render_chart     — execute Python in a sandbox, return image
    │
    ▼
PostgreSQL (marketing data)
```

The agent follows the **ReAct loop**: the LLM reasons about what tool to call, the tool executes, the result is appended to the message thread, and the LLM reasons again — until it has enough information to answer.

---

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Python | ≥ 3.12 | |
| [uv](https://docs.astral.sh/uv/) | latest | Fast Python package manager |
| Docker + Docker Compose | latest | Runs Postgres, the API, and the web UI |
| An LLM API key | — | OpenRouter, Anthropic, or OpenAI — see `.env.example` |

---

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/NhanChau2409/performance-marketing-analyst-agent.git
cd performance-marketing-analyst-agent/marketing-agent

cp .env.example .env
# Open .env and fill in your API key:
#   OPENROUTER_API_KEY=sk-or-...   (or ANTHROPIC_API_KEY / OPENAI_API_KEY)
#   LLM_MODEL=anthropic/claude-sonnet-4-5
```

### 2. Start everything with Docker Compose

```bash
docker compose up --build
```

This starts three services:
- **postgres** — PostgreSQL 16 on port `5433`
- **api** — FastAPI agent server on port `8000`
- **web** — React chat UI on port `3000`

Wait for all three to be healthy (you'll see `Application startup complete` in the api logs).

### 3. Seed the database

```bash
docker compose exec api uv run python scripts/seed_data.py
```

This populates the database with sample marketing campaigns, channels, and performance metrics.

### 4. Open the chat UI

Go to [http://localhost:3000](http://localhost:3000) and start asking questions:

> *"Which campaigns had the highest ROI last quarter?"*
> *"Show me a weekly trend chart for email vs paid search."*
> *"Investigate why conversions dropped in March."*

---

## Running Locally (without Docker)

If you prefer to run the backend directly:

```bash
cd marketing-agent

# Install dependencies
uv sync

# Start Postgres only via Docker
docker compose up postgres -d

# Run database migrations / seed
uv run python scripts/seed_data.py

# Start the API server
uv run uvicorn marketing_agent.api.app:app --reload --port 8000

# Or use the terminal REPL (no UI needed)
uv run python -m marketing_agent.main
```

For the web UI:

```bash
cd web
npm install
npm run dev        # starts Vite dev server on http://localhost:5173
```

---

## Running Tests

```bash
cd marketing-agent
uv sync --extra dev
uv run pytest
```

---

## Compiling the Thesis (Typst)

The thesis source is in `docs/thesis/`. You need [mise](https://mise.jdx.dev/) to get the right Typst version:

```bash
mise install    # installs typst 0.14.2

# Development build
typst compile docs/thesis/template/main.typ --root docs/thesis --font-path docs/thesis/fonts

# Watch mode
typst watch docs/thesis/template/main.typ --root docs/thesis --font-path docs/thesis/fonts

# Final submission (PDF/UA-1)
typst compile docs/thesis/template/main.typ --root docs/thesis --font-path docs/thesis/fonts --pdf-standard ua-1
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Agent framework | LangGraph |
| LLM | Claude / GPT-4o / Gemini via LiteLLM |
| API | FastAPI + SSE streaming |
| Database | PostgreSQL 16 + SQLAlchemy (async) |
| Frontend | React + Tailwind CSS + Vite |
| Thesis | Typst (TAU template) |
