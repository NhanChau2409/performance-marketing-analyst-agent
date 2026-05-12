# Marketing Analytics Agent — Architecture Proposal (POC)

> **Status**: POC / Idea Phase — Side Project  
> **Date**: 2026-04-03  
> **Infra**: None yet. This document describes the target architecture and ideas.

---

## 1. Problem Statement

Marketing teams need to analyze campaign performance, generate reports, and create
visualizations from data stored across ad platforms and data warehouses. Today this
requires manual SQL queries, spreadsheet work, and BI tool navigation.

**Goal**: Build a conversational AI agent that can autonomously research marketing
data, perform analysis, generate charts/Excel files, and produce polished reports —
all from natural language requests.

**Examples of what users would ask**:

- "Compare Q1 vs Q2 ad spend across Google and Meta, break down by campaign type"
- "Which campaigns had the highest CAC last month? Show me a chart"
- "Generate a weekly performance report for the paid search team"
- "Why did our CTR drop on Meta campaigns in March?"
- "Export last month's campaign data as an Excel file with pivot tables"

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        User (Chat UI)                       │
└──────────────────────────┬──────────────────────────────────┘
                           │ SSE stream
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Agent Service                            │
│                  (FastAPI + LangGraph)                       │
│                                                             │
│   ┌──────────┐    ┌────────┐    ┌───────────────┐          │
│   │  Lead     │───▶│ Router │───▶│ Tool Executor │──┐      │
│   │  Agent    │    │        │    │  (parallel)   │  │      │
│   │          │◀───┤        │◀───┤               │  │      │
│   └──────────┘    └────────┘    └───────────────┘  │      │
│        │                              │             │      │
│        │                              ▼             │      │
│        │                     ┌─────────────────┐    │      │
│        │                     │  Python Sandbox  │    │      │
│        │                     │                  │    │      │
│        │                     │  ✓ pandas        │    │      │
│        │                     │  ✓ matplotlib    │    │      │
│        │                     │  ✓ openpyxl      │    │      │
│        │                     │  ✓ plotly        │    │      │
│        │                     │  ✓ full Python   │    │      │
│        │                     └─────────────────┘    │      │
│        │                                            │      │
│        ▼                                            │      │
│   ┌──────────────────┐                              │      │
│   │    Subagent(s)   │  Parallel research tasks     │      │
│   │  (same ReAct)    │                              │      │
│   └──────────────────┘                              │      │
│                                                             │
└──────────────────────┬──────────────────────────────────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
   ┌────────────┐ ┌──────────┐ ┌──────────┐
   │ Data       │ │ File     │ │ Report   │
   │ Warehouse  │ │ Storage  │ │ Delivery │
   │ (TBD)     │ │ (TBD)    │ │ (Chat /  │
   │            │ │          │ │  Download)│
   └────────────┘ └──────────┘ └──────────┘
```

All components are ideas at this stage. Nothing is deployed or built yet.

---

## 3. Core Idea: ReAct Agent Pattern

The agent follows a **ReAct loop** (Reason → Act → Observe → Repeat):

```
START → lead_agent → router → tool_executor → lead_agent → ... → END
                                    │
                                    ▼
                          (tools: query data, run python,
                           generate charts, export files)
```

**Lead Agent** — the main reasoning LLM. Understands the user's question, decides
what data to fetch, what analysis to run, and how to present results.

**Subagents** — spawned by the lead agent for parallel work. Example: when comparing
Google Ads vs Meta, spawn one subagent per platform to fetch data simultaneously,
then the lead agent synthesizes the results.

**Tool Executor** — runs tool calls from the LLM in parallel. Tools are how the
agent interacts with the outside world (database, sandbox, file storage).

---

## 4. Tool Set (Planned)

**Design principle: smart agent, simple tools.** The LLM decides what to do. Tools
are thin, generic, and composable. The agent writes matplotlib/openpyxl/weasyprint
code itself via `python_exec` — no special export tools needed.

| Tool | Category | What It Does |
|------|----------|-------------|
| Tool | Category | What It Does |
|------|----------|-------------|
| `query_data` | Data | Execute read-only SQL against the data warehouse. Saves results to sandbox as CSV. Returns summary to LLM. |
| `list_tables` | Data | List available tables with column names and types. |
| `describe_table` | Data | Show schema, sample rows, and value distributions for a table. |
| `python_exec` | Compute | Execute a Python script in the sandbox. Full library access (pandas, matplotlib, openpyxl, plotly, weasyprint, etc.). The agent uses this for **everything**: analysis, charts, Excel, PDFs, file I/O. |

**That's it. 4 tools.**

> **Why so few?** A tool should only exist when it **crosses a boundary** the LLM
> can't cross on its own. The LLM can't query the database → `query_data`. The LLM
> can't run Python → `python_exec`. But can the LLM read/write files? Yes — via
> `python_exec` with `open()`, `os.listdir()`, `pd.read_csv()`. No separate file
> I/O tools needed. No export tools needed — the sandbox has all the libraries.
> Skills (prompt templates) guide the agent on HOW to produce good output.

---

## 5. The Python Sandbox — Core Compute Layer

### 5.1 What It Is

A sandboxed Python environment where the agent can run arbitrary Python scripts
with full library access. This is where all the heavy lifting happens: data
manipulation, chart rendering, Excel generation, PDF compilation.

The sandbox needs:
- **Python 3.12+** with pre-installed libraries
- **Persistent filesystem** across tool calls within a session
- **Isolation** — no outbound network, no host access
- **Timeout enforcement** — kill long-running scripts

Pre-installed libraries:
```
Data:    pandas, numpy, pyarrow
Charts:  matplotlib, plotly, seaborn
Excel:   openpyxl, xlsxwriter
Tables:  tabulate
Stats:   scipy, scikit-learn (basic)
PDF:     weasyprint, jinja2
```

### 5.2 Implementation Options (TBD)

Since we have no infrastructure yet, here are the options we're considering:

| Option | Pros | Cons | Effort |
|--------|------|------|--------|
| **Docker container** (local) | Simple to start, full control, cheap | Must manage lifecycle, no scale | Low |
| **Subprocess** (in-process) | Simplest, zero infra | No real isolation, security risk | Lowest |
| **E2B.dev** (cloud sandbox API) | Zero infra, strong isolation, fast | External dependency, cost at scale | Low |
| **Modal.com** (serverless) | Auto-scale, persistent volumes | External dependency, cold starts | Medium |
| **K8s sandbox pods** (like as-agent) | Battle-tested pattern, strong isolation | Needs K8s cluster, most infra work | High |

**For POC**: Docker container (local) or E2B is the most practical starting point.
We can migrate to K8s pods later if this goes to production.

### 5.3 The Key Insight: Sandbox-as-Memory

The sandbox is not just for running code — **it's the agent's working memory**.

Data lives in the sandbox filesystem, not in the LLM context. The LLM only sees
summaries. This is critical for keeping costs low and conversations long.

**Without sandbox-as-memory** (bad):
```
Agent fetches 500 campaign rows  → 50K tokens dumped into LLM context
Agent fetches daily breakdowns   → 30K more tokens
Agent fetches creative data      → 20K more tokens
                                   ─────────────────
                                   100K tokens consumed. Slow, expensive, LLM loses focus.
```

**With sandbox-as-memory** (good):
```
Agent fetches 500 campaign rows  → saved as data/q1.csv in sandbox
                                 → LLM sees: "Saved 500 rows. 3 platforms.
                                   Total spend: $2.4M." (~100 tokens)

Agent analyzes top performers    → python_exec: df.nlargest(10, 'roas')
                                 → LLM sees: printed 10-row table (~300 tokens)

Agent creates chart              → python_exec: matplotlib code
                                 → LLM sees: "Chart saved." (~20 tokens)
```

**~25x context efficiency.** The sandbox holds gigabytes; the LLM context holds
the summaries and reasoning.

### 5.4 How a Conversation Flows Through the Sandbox

```
┌─ Turn 1 ─────────────────────────────────────────────────────────────┐
│                                                                       │
│  User: "Analyze our Q1 campaigns"                                    │
│                                                                       │
│  Agent calls: query_data(                                            │
│    sql="SELECT * FROM campaigns WHERE quarter='Q1'",                 │
│    save_as="q1_campaigns.csv"                                        │
│  )                                                                   │
│  → Executes query, writes 500 rows to sandbox: /data/q1.csv         │
│  → Returns to LLM: "Saved 500 rows. Google (210), Meta (180),       │
│    LinkedIn (110). Total spend: $2.4M."                              │
│                                                                       │
│  Agent calls: python_exec("""                                        │
│    import pandas as pd                                                │
│    df = pd.read_csv('data/q1_campaigns.csv')                         │
│    print(df.groupby('platform').agg(                                 │
│        spend=('cost','sum'), avg_roas=('roas','mean')                │
│    ).round(2).to_markdown())                                          │
│  """)                                                                 │
│  → Returns: formatted table to LLM (~200 tokens)                    │
│                                                                       │
│  Agent writes analysis to user.                                      │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

┌─ Turn 2 (data already on disk — no re-fetch!) ──────────────────────┐
│                                                                       │
│  User: "Show me a bar chart of spend by platform"                    │
│                                                                       │
│  Agent calls: python_exec("""                                        │
│    import pandas as pd                                                │
│    import matplotlib.pyplot as plt                                    │
│    df = pd.read_csv('data/q1_campaigns.csv')  # already there!      │
│    spend = df.groupby('platform')['cost'].sum().sort_values()        │
│    spend.plot(kind='barh', figsize=(10,6))                           │
│    plt.title('Q1 Ad Spend by Platform')                              │
│    plt.savefig('charts/q1_spend.png', dpi=150)                       │
│    print('Chart saved.')                                              │
│  """)                                                                 │
│  → Chart rendered in sandbox, returned to user                       │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

┌─ Turn 3 (Excel export — same data, no re-fetch) ────────────────────┐
│                                                                       │
│  User: "Export this as an Excel file with a summary sheet"           │
│                                                                       │
│  Agent calls: python_exec("""                                        │
│    import pandas as pd                                                │
│    df = pd.read_csv('data/q1_campaigns.csv')  # still there!        │
│    with pd.ExcelWriter('exports/q1_report.xlsx') as w:               │
│        df.to_excel(w, sheet_name='Raw Data', index=False)            │
│        pivot = df.pivot_table(values=['cost','roas'],                │
│                               index='platform', aggfunc='sum')       │
│        pivot.to_excel(w, sheet_name='Summary')                       │
│    print('Excel saved.')                                              │
│  """)                                                                 │
│  → Excel file returned to user as download                           │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 6. Data Layer

### 6.1 Data Warehouse Schema (Conceptual)

The agent needs a database with marketing data. Schema TBD, but conceptually:

```sql
campaigns          -- One row per campaign
  id, platform (google_ads | meta | linkedin | tiktok),
  name, type (search | display | video | social), status,
  budget_daily, start_date, end_date, labels[]

ad_groups          -- Nested under campaigns
  id, campaign_id, name, targeting_type, bid_strategy

ads                -- Creatives nested under ad groups
  id, ad_group_id, headline, description, creative_type,
  landing_page_url, status

daily_metrics      -- Fact table: one row per ad per day
  date, ad_id, impressions, clicks, ctr, cost,
  conversions, conversion_value, cpc, cpa, roas

audience_segments  -- Segment-level performance
  id, campaign_id, segment_name, impressions, clicks,
  conversions, cost, date
```

### 6.2 Data Ingestion (Out of Scope for POC)

For POC we'll seed the database with synthetic/sample data. In production,
data would come from ETL pipelines pulling from:
- Google Ads API, Meta Marketing API, LinkedIn Campaign Manager API
- Google Analytics / GA4
- CRM (Salesforce, HubSpot) for downstream conversions

### 6.3 Query Safety

Even in a POC, we should practice safe data access:

1. **Read-only DB user** — SELECT only, no mutations
2. **SQL validation** — reject DDL/DML keywords before execution
3. **Row limits** — cap at 10,000 rows per query
4. **Timeout** — 30 second query timeout
5. **Schema discovery** — agent uses `list_tables`/`describe_table`, not raw `information_schema`

---

## 7. Visualization & Report Generation

### 7.1 Chart Types

| Chart Type | Library | Use Case |
|-----------|---------|----------|
| Bar / horizontal bar | matplotlib | Spend comparison across platforms |
| Line chart | matplotlib | Trends over time (CTR, CPC, ROAS) |
| Pie / donut | matplotlib | Budget allocation breakdown |
| Scatter plot | matplotlib | Spend vs. conversions correlation |
| Heatmap | seaborn | Day-of-week / hour-of-day performance |
| Interactive charts | plotly | Multi-metric exploration (optional) |

### 7.2 Excel Generation

The agent writes openpyxl/pandas code to create multi-sheet workbooks:
- Raw data sheet
- Pivot table summaries
- Weekly/monthly trend sheets
- Charts embedded in sheets (openpyxl chart support)

### 7.3 Report Pipeline

```
Agent writes Markdown report in sandbox
      │
      ├──▶ HTML  (Jinja2 template + embedded chart images)
      │     └──▶ PDF  (weasyprint, all in sandbox)
      │
      ├──▶ Excel (data + pivots + embedded charts)
      │
      └──▶ Markdown (for inline chat display)
```

### 7.4 Example Report Structure

```markdown
# Q1 2026 Marketing Performance Report

## Executive Summary
- Total spend: $2.4M across 500 campaigns
- Blended ROAS: 3.2x (up from 2.8x in Q4)
- Top platform: Google Ads (42% of spend, 3.8x ROAS)

## Platform Performance
![Spend by Platform](charts/q1_spend.png)

| Platform | Spend   | Revenue | ROAS | CPA    |
|----------|---------|---------|------|--------|
| Google   | $1.01M  | $3.84M  | 3.8x | $12.40 |
| Meta     | $840K   | $2.52M  | 3.0x | $15.20 |
| LinkedIn | $550K   | $1.43M  | 2.6x | $28.50 |

## Recommendations
1. Shift 15% of LinkedIn budget to Google Search
2. Scale Meta retargeting (lowest CPA at $8.20)
3. Pause 12 campaigns with ROAS < 1.0
```

---

## 8. Subagent Patterns

### 8.1 Parallel Data Gathering

```
User: "Compare Google Ads vs Meta for Q1"

Lead Agent spawns:
  ├── Subagent A (background): Fetch Google Ads Q1 → saves google_q1.csv
  ├── Subagent B (background): Fetch Meta Q1 → saves meta_q1.csv
  └── (Lead waits for both)

Lead Agent:
  → python_exec: load both CSVs, compute comparison, generate charts
  → Write final report
```

### 8.2 Report Assembly

```
User: "Generate a full monthly marketing report"

Lead Agent:
  ├── Subagent A: Gather Google Ads data → CSV
  ├── Subagent B: Gather Meta data → CSV
  ├── Subagent C: Gather LinkedIn data → CSV
  └── (all parallel)

Lead Agent (after all complete):
  → python_exec: cross-platform analysis + charts + Excel + PDF
  → Deliver report with download links
```

---

## 9. Tech Stack (Planned)

| Component | Technology | Notes |
|-----------|-----------|-------|
| Agent framework | **LangGraph** (Python) | ReAct loop, subagents, checkpoints |
| API layer | **FastAPI** + SSE | Streaming responses to chat UI |
| LLM | **Claude Sonnet** or equivalent | Via LiteLLM for provider flexibility |
| Python sandbox | **Docker** (POC) or **E2B** | Full Python env with data/viz libs |
| Data warehouse | **PostgreSQL** (POC) | Seed with sample data. Could be Snowflake/BQ later |
| File storage | **Local filesystem** (POC) | Charts, exports. Could be S3 later |
| State/checkpoints | **PostgreSQL** or **SQLite** | LangGraph checkpoint persistence |
| Report rendering | **weasyprint + Jinja2** | In sandbox: Markdown → HTML → PDF |

Everything starts local/simple for POC and can be scaled up later.

---

## 10. Security Considerations

Even for a side project, these are worth thinking about early:

```
Sandbox Isolation
  ✗ No outbound network from sandbox
  ✗ No host filesystem access
  ✓ Resource limits (CPU, memory, timeout)
  ✓ Non-root execution

Data Access
  ✓ Read-only database user
  ✓ SQL keyword validation (block DROP, DELETE, etc.)
  ✓ Row and time limits on queries

Code Execution
  ✓ Timeout on all python_exec calls
  ✓ Sandbox environment is disposable (reset between sessions)
```

---

## 11. POC Milestones

### Phase 1: Agent + Data Tools (Week 1-2)
- [ ] Set up LangGraph ReAct graph (lead agent + router + tool executor)
- [ ] Set up Python sandbox (Docker container or E2B)
- [ ] Implement `query_data`, `list_tables`, `describe_table` tools
- [ ] Implement `python_exec` tool
- [ ] Seed PostgreSQL with sample marketing data (1 year, 3 platforms)
- [ ] Basic chat UI or CLI interface

### Phase 2: Visualization + Export (Week 3-4)
- [ ] Install pandas, matplotlib, openpyxl, seaborn in sandbox
- [ ] Chart generation flow (python_exec → save PNG → return to user)
- [ ] Excel export flow (python_exec → save .xlsx → download link)
- [ ] Test sandbox-as-memory pattern (data persists across turns)

### Phase 3: Subagents + Reports (Week 5-6)
- [ ] Subagent spawning for parallel data gathering
- [ ] Report generation pipeline (Markdown → HTML → PDF)
- [ ] System prompt tuning for marketing domain

### Phase 4: Polish + Demo (Week 7-8)
- [ ] Error handling (bad SQL, Python errors, timeouts)
- [ ] Demo scenarios: weekly report, campaign comparison, anomaly investigation
- [ ] Document learnings, decide whether to productionize

---

## 12. Open Questions

| # | Question | Notes |
|---|----------|-------|
| 1 | **Sandbox choice** — Docker (local) vs E2B (cloud) vs subprocess? Docker is simplest to start. | |
| 2 | **Data warehouse** — PostgreSQL for POC, but what's the production target? Snowflake? BigQuery? | |
| 3 | **Chat UI** — build a simple web UI, use a CLI, or integrate with an existing tool (Slack, etc.)? | |
| 4 | **LLM choice** — Claude, GPT-4, Gemini? Cost matters for a side project. LiteLLM gives flexibility. | |
| 5 | **Sample data** — generate synthetic data or use anonymized real data? | |
| 6 | **Chart delivery** — inline images in chat? Download links? Both? | |
| 7 | **Multi-user** — single user POC or multi-tenant from the start? | |

---

## 13. Example End-to-End Flow

```
User: "Create a weekly performance report for paid search"

─── Step 1: Parallel data gathering ─────────────────────────

Lead Agent spawns 2 subagents:
  → Subagent A: query_data → google_search_4w.csv (210 campaigns)
  → Subagent B: query_data → meta_search_4w.csv (95 campaigns)

─── Step 2: Analysis ────────────────────────────────────────

Lead Agent: python_exec →
  Load both CSVs with pandas
  Weekly aggregates: spend, CTR, CPC, ROAS
  Week-over-week changes
  Top/bottom performer identification

─── Step 3: Visualization ───────────────────────────────────

Lead Agent: python_exec →
  Line chart: weekly ROAS by platform
  Stacked bar: weekly spend by platform
  Horizontal bar: top 10 campaigns by conversions

─── Step 4: Export ──────────────────────────────────────────

Lead Agent: python_exec →
  Excel workbook (raw data + pivots + summary sheets)
  Markdown report → HTML → PDF via weasyprint

─── Step 5: Deliver ─────────────────────────────────────────

Agent: "Here's your weekly paid search report.

Key highlights:
- ROAS improved 12% WoW, driven by Google Shopping
- Meta CPA increased 8% — review audience targeting
- 3 campaigns at ROAS < 1.0 (wasting $12K/week)

[View Report] [Download Excel] [Download PDF]"
```

---

## Appendix: Tool Implementation Sketches

These are rough sketches to illustrate the idea, not final code.

### query_data

```python
async def query_data(sql: str, save_as: str = "results.csv") -> str:
    """Execute read-only SQL, save to sandbox, return summary to LLM."""
    if not is_read_only(sql):
        return "Error: Only SELECT queries allowed."

    rows = await db.execute(sql, timeout=30, row_limit=10_000)
    await sandbox.write_file(f"data/{save_as}", to_csv(rows))

    return (
        f"Saved {len(rows)} rows to data/{save_as}\n"
        f"Columns: {list(rows[0].keys())}\n"
        f"Use python_exec with pandas to analyze."
    )
```

### python_exec

```python
async def python_exec(code: str, timeout: int = 300) -> str:
    """Execute Python in sandbox. Full library access.
    Use this for ALL computation: data analysis, chart generation,
    Excel export, PDF reports. The sandbox has pandas, matplotlib,
    openpyxl, plotly, seaborn, weasyprint, jinja2 pre-installed."""
    result = await sandbox.run(code, timeout=timeout)

    if result.exit_code != 0:
        return f"Error:\n{result.stderr}"
    return result.stdout
```

---

## System Prompt Design

The system prompt is how we make the agent smart without adding more tools.
See [04-implementation-guide.md](04-implementation-guide.md) for the full prompt text.

### Lead Agent Prompt — Key Sections

| Section | Purpose |
|---------|---------|
| **Identity & role** | "You are a marketing analytics agent." Sets domain expertise and tone. |
| **Available tools** | What each tool does and when to use it (4 tools only). |
| **Sandbox environment** | Directories (`data/`, `charts/`, `exports/`), pre-installed libraries, how to use `open()` / `os.listdir()` / `pd.read_csv()` for file ops. This replaces file I/O tools. |
| **Sandbox-as-memory** | "Data lives on disk, not in context. Use python_exec to analyze. Don't re-fetch data that's already saved." |
| **Output standards** | Chart formatting rules (figsize, DPI, labels), Excel conventions (multiple sheets, headers), report structure (exec summary → tables → charts → recommendations). |
| **Workflow patterns** | Common flows: simple question (query → analyze → respond), investigation (query → drill down → root cause), report (query × N → charts → Excel → PDF). |
| **Subagent delegation** | When to spawn subagents, file naming conventions, how to combine results. |
| **Guardrails** | Read-only access, never fabricate data, interpret errors for the user. |

### Subagent Prompt — Leaner

| Section | Purpose |
|---------|---------|
| **Identity** | "You are a data research agent." Focused worker, not orchestrator. |
| **Tools** | Same 4 tools, but no subagent spawning. |
| **Instructions** | Fetch data, save as CSV, return brief summary. Max 10 tool calls. |
| **What NOT to do** | No charts, no reports, no user-facing formatting. Just data. |

### Key Insight

> The system prompt is where the "smart" in "smart agent, simple tools" comes from.
> Instead of building 10 specialized tools, we write one good prompt that teaches the
> agent how to use 4 generic tools effectively. Skills extend this further for
> specific workflows.
