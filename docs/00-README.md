# Marketing Analytics Agent — Project Documentation

> A side project to learn AI engineering by building a marketing analytics agent
> from scratch using LangGraph, FastAPI, and Python.

---

## Who Is This For?

This is a **teaching-oriented** project. If you're a student or developer who wants to
learn how to build AI agents — not just call an LLM API, but build a real agent system
with tools, state management, streaming, and multi-agent orchestration — this project
walks you through every concept with working code.

You'll build an agent that can:
- Query a marketing database and analyze campaign performance
- Generate charts (matplotlib) and Excel reports (openpyxl)
- Create polished PDF reports from natural language requests
- Delegate work to sub-agents that run in parallel
- Stream real-time progress updates to a chat UI

---

## Documentation Map

Read in this order:

### 1. [Proposal](01-proposal.md) — The "What" and "Why"
- Problem statement: what does the agent do?
- High-level architecture diagram
- Data model (marketing tables)
- Sandbox design (where Python runs)
- Security considerations
- POC milestones

### 2. [Skills Catalog](02-skills-catalog.md) — The "Use Cases"
- 20 skills across 8 categories (reports, analysis, investigation, etc.)
- How skills work (prompt templates that orchestrate tools)
- Each skill: trigger, steps, data needed, output format
- POC priority: which 3 skills to build first

### 3. [LangGraph Guide](03-langgraph-guide.md) — The "How It Works" (Concepts)
- What is an AI agent? (vs. chatbot, vs. pipeline)
- The ReAct pattern explained from first principles
- LangGraph concepts: State, Nodes, Edges, Graph
- How tool calling works (LLM → tool → LLM loop)
- Checkpointing and memory
- Message management and context windows
- Subagents and multi-agent patterns
- **All concepts illustrated with code you can run**

### 4. [Implementation Guide](04-implementation-guide.md) — The "Build It" (Step by Step)
- Project setup (Python, uv, dependencies)
- Step 1: Build a minimal agent (LLM + one tool)
- Step 2: Add the ReAct graph (nodes, router, tool executor)
- Step 3: Add marketing data tools (query, schema discovery)
- Step 4: Add the Python sandbox (Docker)
- Step 5: "Smart agent, simple tools" — why 4 tools is all you need
- Step 6: Add SSE streaming (FastAPI)
- Step 7: Add subagents (parallel data gathering)
- Step 8: Add skills (prompt templates)
- Each step: explanation → code → test → verify

### 5. [Tools Reference](05-tools-reference.md) — The "Details"
- 4 tools: design rationale, full implementation, usage examples
- "Smart agent, simple tools" — why fewer tools is better
- Tool patterns: input validation, error handling, sandbox interaction
- How to add new tools

### 6. [System Prompts](06-system-prompts.md) — The "Brain"
- Lead agent prompt: full text with every section explained
- Subagent prompt: lean worker prompt
- Prompt architecture (static prompt + session context + conversation)
- How skills inject into the prompt
- Prompt design principles (6 rules)
- Testing scenarios to validate prompt quality

---

## Tech Stack

| Component | Technology | What You'll Learn |
|-----------|-----------|-------------------|
| Agent framework | **LangGraph** | State machines, graph execution, ReAct loop |
| LLM | **Claude / GPT-4 / Gemini** (via LiteLLM) | Tool calling, prompt engineering, model switching |
| API layer | **FastAPI** | SSE streaming, async Python, REST APIs |
| Data | **PostgreSQL** + seed data | SQL, data modeling, read-only access patterns |
| Sandbox | **Docker** | Container isolation, code execution, file I/O |
| Viz | **matplotlib, openpyxl, weasyprint** | Chart rendering, Excel generation, PDF export |

---

## Prerequisites

- Python 3.12+
- Basic understanding of async/await in Python
- An LLM API key (Anthropic, OpenAI, or Google)
- Docker installed (for the sandbox)
- PostgreSQL (local or Docker)

No prior experience with LangGraph, agents, or AI engineering required.
That's what this project teaches.

---

## Quick Start

```bash
# Clone and setup (TBD — project not yet scaffolded)
git clone <repo-url>
cd marketing-agent
uv sync

# Seed the database with sample marketing data
uv run python scripts/seed_data.py

# Start the agent
uv run python -m marketing_agent.main

# Or start the API server
uv run uvicorn marketing_agent.api:app --reload
```
