/** 04.typ — Chapter 4: Implementation
***/

#pdf.attach(
  "04.typ",
  relationship: "source",
  mime-type: "text/vnd.typst",
  description: "The Typst source code for Chapter 4 (Implementation) of this thesis.",
)

#import "../preamble.typ": *

= Implementation <implementation>
This chapter describes the step-by-step implementation of the marketing analytics
agent. Section @tech-stack lists the technology stack. Sections @db-schema through
@skills-impl cover each major component in the order they were built.

== Technology stack <tech-stack>
#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Component*], [*Technology*], [*Role*]),
    [Agent framework],   [LangGraph 0.4+],            [ReAct graph, state management, checkpointing],
    [LLM access],        [LiteLLM @litellm2024],      [Provider-agnostic LLM API (Anthropic, OpenAI, Google)],
    [API layer],         [FastAPI @fastapi2024],       [HTTP endpoint for agent interaction],
    [Database],          [PostgreSQL @postgresql2024], [Marketing data warehouse (read-only)],
    [ORM],               [SQLAlchemy @sqlalchemy2024], [Async database access],
    [Validation],        [Pydantic @pydantic2024],     [Request/response schema validation],
    [Language],          [Python 3.12],                [All backend code],
  ),
  caption: [Technology stack of the marketing analytics agent.],
) <tab-tech-stack>

Python 3.12 was chosen for its mature async support and the breadth of its data-science
ecosystem. LiteLLM provides a unified API across LLM providers, so the underlying model
can be swapped without changing application code.

== Database schema <db-schema>
=== Design rationale

A common approach for agent evaluation is to use a single normalised schema with a
`platform` column to distinguish data sources. This thesis takes a different approach:
the synthetic database uses _nine separate tables_ organised into three platform groups,
each modelled directly after the reporting API of the corresponding advertising
platform @google-ads-api-fields @meta-ads-insights @tiktok-ads-api. The motivation is
transferability. If the agent learns to write SQL against synthetic data that uses
platform-native column names, the same queries and prompt patterns will work against a
live integration without modification. Conversely, a schema that uses generic field
names (e.g., `spend` for Google, which calls the same metric `cost`) would require
prompt adjustments at integration time, masking a real design gap.

=== Google Ads tables

The Google tables follow the Google Ads API field reference @google-ads-api-fields.

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*Table*], [*Key Columns*]),
    [`google_campaigns`],
      [`id`, `name`, `campaign_type` (SEARCH / DISPLAY / SHOPPING / PERFORMANCE\_MAX),
       `bidding_strategy` (TARGET\_ROAS / TARGET\_CPA / MAXIMIZE\_CONVERSIONS / MANUAL\_CPC),
       `daily_budget`, `status` (ENABLED / PAUSED), `start_date`],
    [`google_ad_groups`],
      [`id`, `campaign_id`, `name`, `status`, `cpc_bid`],
    [`google_daily_metrics`],
      [`id`, `campaign_id`, `ad_group_id`, `date`, `impressions`, `clicks`,
       `cost` #footnote[Google Ads API uses the field name \`cost\`, not \`spend\`.],
       `conversions`, `conversion_value`, `avg_cpc`, `ctr`,
       `search_impression_share` #footnote[The fraction of eligible searches for which the ad was shown; a Google-specific signal.],
       `device` (MOBILE / DESKTOP / TABLET)],
  ),
  caption: [Google Ads tables modelled after the Google Ads API @google-ads-api-fields.],
) <tab-google-schema>

=== Meta Ads tables

The Meta tables follow the Meta Ads Insights API reference @meta-ads-insights. Meta
uses the term _ad set_ instead of _ad group_, and _spend_ instead of _cost_.

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*Table*], [*Key Columns*]),
    [`meta_campaigns`],
      [`id`, `name`, `objective` (OUTCOME\_TRAFFIC / OUTCOME\_CONVERSIONS /
       OUTCOME\_AWARENESS / OUTCOME\_LEADS), `daily_budget`, `status`, `start_date`],
    [`meta_ad_sets`],
      [`id`, `campaign_id`, `name`, `optimization_goal`, `billing_event`,
       `age_min`, `age_max`, `placement` (FEED / STORIES / REELS / AUDIENCE\_NETWORK), `status`],
    [`meta_daily_metrics`],
      [`id`, `campaign_id`, `ad_set_id`, `date`, `impressions`,
       `reach` #footnote[Unique users exposed to the ad; distinct from impressions.],
       `frequency` #footnote[Average number of times each user saw the ad: impressions ÷ reach.],
       `clicks`, `link_clicks`, `spend`, `conversions`, `conversion_value`,
       `video_views`, `cpm`],
  ),
  caption: [Meta Ads tables modelled after the Meta Ads Insights API @meta-ads-insights.],
) <tab-meta-schema>

=== TikTok Ads tables

The TikTok tables follow the TikTok Ads API reporting specification @tiktok-ads-api.
TikTok is a video-first platform; its metrics table captures the full video engagement
funnel alongside standard click-and-conversion fields.

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*Table*], [*Key Columns*]),
    [`tiktok_campaigns`],
      [`id`, `name`, `objective` (TRAFFIC / CONVERSIONS / APP\_PROMOTION /
       VIDEO\_VIEWS / REACH), `daily_budget`, `status`, `start_date`],
    [`tiktok_ad_groups`],
      [`id`, `campaign_id`, `name`, `placement` (TIKTOK / PANGLE),
       `optimization_goal`, `age_group`, `status`],
    [`tiktok_daily_metrics`],
      [`id`, `campaign_id`, `ad_group_id`, `date`, `impressions`, `clicks`,
       `spend`, `conversions`, `conversion_value`, `cpm`, `ctr`,
       `video_views`, `video_watched_2s`, `video_watched_6s`, `video_completions`,
       `likes`, `comments`, `shares`],
  ),
  caption: [TikTok Ads tables modelled after the TikTok Ads API @tiktok-ads-api.],
) <tab-tiktok-schema>

=== Synthetic data generation

The seed script generates 181 days of daily metrics (2025-10-01 to 2026-03-31) using
platform-specific performance envelopes informed by published industry benchmarks.
Google Ads search campaigns target a CTR of 3–8\% with CPC \$0.80–\$3.50 and a
conversion rate of 3–6\%. Meta campaigns operate at CPM \$8–\$18 with reach set to
60–85\% of impressions and frequency capped between 1.2 and 2.5. TikTok campaigns
use CPM \$5–\$12 with video completion rates of 15–35\%, reflecting the platform's
higher organic engagement relative to its lower direct-response conversion rate of
0.5–2\%. All platforms apply a weekday multiplier (weekend volume at 60\% of
weekday) and a 10\% per-month growth trend to simulate campaign ramp-up over the
observation period.

== LangGraph ReAct graph <langgraph-impl>
The ReAct graph is the central control structure of the agent. It consists of three
nodes and one conditional edge:

```python
from langgraph.graph import StateGraph, END
from typing import TypedDict, Annotated
from langchain_core.messages import BaseMessage
import operator

class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], operator.add]

graph = StateGraph(AgentState)
graph.add_node("lead_agent", lead_agent_node)
graph.add_node("tool_executor", tool_executor_node)
graph.set_entry_point("lead_agent")
graph.add_conditional_edges(
    "lead_agent",
    router,
    {"tools": "tool_executor", END: END},
)
graph.add_edge("tool_executor", "lead_agent")
```

The `lead_agent` node calls the LLM with the current message history. The `router`
function inspects the last message: if it contains tool calls, execution routes to
`tool_executor`; otherwise the graph terminates and the final answer is returned to
the caller.

The `tool_executor` node iterates over all tool calls in the last message, executes
each one concurrently using `asyncio.gather()`, and appends the results as
`ToolMessage` objects to the state. Because LangGraph uses the `operator.add` reducer
on the `messages` field, appending new messages never overwrites the existing history.

== The three tools <tools-impl>
=== List_tables <list-tables-impl>
`list_tables` takes no parameters. It queries the database's `information_schema` for
all user tables and their approximate row counts, then formats the result as a
human-readable string. The return value is intentionally text rather than JSON, because
LLMs parse formatted text more reliably than structured objects when the content is
meant to be read and reasoned about rather than parsed programmatically.

=== Describe_table <describe-table-impl>
`describe_table` accepts a table name and returns the column names, types,
nullability flags, and the first three rows as a sample. It also computes value
distributions for categorical columns (e.g., the distinct values of `platform`). This
gives the model enough information to write correct SQL without guessing column names.

=== Query_data <query-data-impl>
`query_data` accepts a SQL string. Before execution, it validates the query with a
regular expression that rejects any statement containing DDL or DML keywords
(`INSERT`, `UPDATE`, `DELETE`, `DROP`, `ALTER`, `CREATE`, `TRUNCATE`). The query is
then executed with a 30-second timeout and a 10,000-row cap. Results are formatted as
a text table and returned directly to the model.

```python
FORBIDDEN = re.compile(
    r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE)\b",
    re.IGNORECASE,
)

async def query_data(sql: str) -> str:
    if FORBIDDEN.search(sql):
        return "Error: Only SELECT queries are allowed."
    rows = await db.fetch(sql, timeout=30, limit=10_000)
    return format_as_table(rows)
```

The `format_as_table` function renders the rows as a human-readable Markdown table
truncated to a configurable maximum, followed by a summary line stating the total row
count if results were truncated. The model uses this formatted output for analysis
and to inform follow-up tool calls.

== Subagent implementation <subagents-impl>
The `research_agent` tool is implemented as a function that accepts a list of task
descriptions and executes each as an independent LangGraph graph:

```python
async def research_agent(tasks: list[dict]) -> str:
    coroutines = [run_subagent(task) for task in tasks]
    results = await asyncio.gather(*coroutines)
    return "\n\n".join(results)

async def run_subagent(task: dict) -> str:
    graph = build_subagent_graph()  # same ReAct graph, restricted tools
    state = {"messages": [HumanMessage(content=task["prompt"])]}
    result = await graph.ainvoke(state)
    return result["messages"][-1].content
```

Each subagent runs the full ReAct loop with the same tool set as the lead agent, minus
`research_agent` itself (preventing recursive spawning). Subagents return their query
results as structured text in their final response; `asyncio.gather()` collects all
responses and the lead agent synthesises them into a unified analysis.

The subagent system prompt is deliberately lean (~500 tokens, versus ~2,000 for the
lead agent). It instructs the subagent to: discover the schema if needed, fetch the
requested data, and return a concise structured summary. The lead agent is responsible
for the final synthesis and report.

== Skills implementation <skills-impl>
Skills are stored as Markdown files in the `skills/` directory. Each file follows
the structure shown below:

```
---
trigger: /weekly-report
data:
  tables: [daily_metrics, campaigns]
  lookback: 7 days
---

# Weekly Performance Report

Follow these steps exactly:

1. Query the last 7 days of `daily_metrics` joined with `campaigns`,
   grouped by day and platform.
2. Compute week-over-week changes for: spend, clicks, CTR, CPC, ROAS.
3. Identify the top 5 and bottom 5 campaigns by ROAS.
4. Present results as: an executive summary (3–5 bullets), a per-platform
   metrics table, a top/bottom campaigns table, and a written trend analysis.
```

At runtime, the skill loader parses the Markdown file and injects the body (the
numbered steps) into the session context as an "Active Skill" section. This extends
the lead agent's behaviour for this specific workflow without modifying the static
system prompt or the tool layer.

Three skills were implemented for the proof-of-concept:

- `weekly-report` — routine weekly performance summary with structured tables and
  trend analysis.
- `campaign-analysis` — deep dive into a single campaign's performance by ad group
  and audience segment.
- `investigate-drop` — structured root-cause analysis for a metric that has declined,
  narrowing the scope from platform to campaign to ad group level.
