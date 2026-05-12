# Implementation Guide — Building the Marketing Analytics Agent

This is the hands-on build guide. You have read the [LangGraph Guide](03-langgraph-guide.md)
and understand the concepts: state, nodes, edges, tools, and the ReAct loop. Now you will
build the actual project, one step at a time.

Each step produces a working system. You run it, test it, understand it, then add the next
capability. By the end you will have a production-grade marketing analytics agent with
database querying, data analysis, visualization, SSE streaming, subagents,
and skills.

**Prerequisites**: Python 3.12, Docker Desktop, `uv` package manager, and an LLM API key
(Anthropic or OpenAI).

---

## 1. Project Setup

Before writing any agent code, set up the project structure, dependencies, and infrastructure.

### Directory structure

Create this layout. Every file will be filled in over the course of this guide.

```
marketing-agent/
  src/marketing_agent/
    __init__.py
    main.py              # CLI entry point
    api.py               # FastAPI app
    config.py            # Settings (Pydantic BaseSettings)
    models/
      __init__.py
      state.py           # AgentState TypedDict
      schemas.py         # Request/response Pydantic models
    graph/
      __init__.py
      graph.py           # Graph construction
      nodes/
        __init__.py
        lead_agent.py    # LLM reasoning node
        router.py        # Conditional routing
        tool_executor.py # Tool execution node
    tools/
      __init__.py
      query_data.py
      python_exec.py
      list_tables.py
      describe_table.py
    sandbox/
      __init__.py
      client.py          # Docker sandbox client
      Dockerfile         # Sandbox image with data libs
    skills/
      weekly_report/
        SKILL.md
      campaign_analysis/
        SKILL.md
      investigate_drop/
        SKILL.md
    streaming/
      __init__.py
      sse.py             # SSE generator
    prompts/
      __init__.py
      system.py          # System prompt construction
    db/
      __init__.py
      connection.py      # Async SQLAlchemy setup
      seed.py            # Seed data generator
  tests/
    __init__.py
    conftest.py
  scripts/
    seed_data.py
  pyproject.toml
  docker-compose.yml     # PostgreSQL + sandbox
  .env.example
```

Create it all at once:

```bash
mkdir -p marketing-agent/src/marketing_agent/{models,graph/nodes,tools,sandbox,skills/{weekly_report,campaign_analysis,investigate_drop},streaming,prompts,db}
mkdir -p marketing-agent/{tests,scripts}

# Create all __init__.py files
find marketing-agent/src -type d -exec touch {}/__init__.py \;
touch marketing-agent/tests/__init__.py
```

### pyproject.toml

```toml
[project]
name = "marketing-agent"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    # LLM and agent framework
    "langgraph>=0.4",
    "langchain-anthropic>=0.3",
    "langchain-openai>=0.3",
    "litellm>=1.60",

    # Web framework
    "fastapi>=0.115",
    "uvicorn[standard]>=0.34",
    "sse-starlette>=2.0",

    # Database
    "sqlalchemy[asyncio]>=2.0",
    "asyncpg>=0.30",

    # HTTP client (for sandbox communication)
    "httpx>=0.28",

    # Configuration
    "pydantic-settings>=2.7",

    # Utilities
    "python-dotenv>=1.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.24",
    "ruff>=0.8",
]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]

[tool.ruff]
line-length = 100
target-version = "py312"
```

### docker-compose.yml

This gives you two services: a PostgreSQL database for marketing data, and a Python sandbox
for code execution. The sandbox is added in Step 3 — for now it is commented out.

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: marketing
      POSTGRES_USER: marketing
      POSTGRES_PASSWORD: marketing_local
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U marketing"]
      interval: 5s
      timeout: 3s
      retries: 5

  # Uncomment in Step 3 when you add the sandbox
  # sandbox:
  #   build:
  #     context: ./src/marketing_agent/sandbox
  #     dockerfile: Dockerfile
  #   ports:
  #     - "8100:8100"
  #   volumes:
  #     - sandbox_data:/sandbox
  #   mem_limit: 512m
  #   cpus: 1.0
  #   network_mode: "none"

volumes:
  pgdata:
  # sandbox_data:
```

### .env.example

```bash
# LLM provider — pick one
ANTHROPIC_API_KEY=sk-ant-...
# Or for OpenAI:
# OPENAI_API_KEY=sk-...

# Which model to use
LLM_MODEL=claude-sonnet-4-20250514
# LLM_MODEL=gpt-4o

# PostgreSQL (matches docker-compose.yml)
DATABASE_URL=postgresql+asyncpg://marketing:marketing_local@localhost:5432/marketing

# Sandbox (Step 3)
SANDBOX_URL=http://localhost:8100
```

### Install and verify

```bash
cd marketing-agent

# Copy the env file and add your API key
cp .env.example .env
# Edit .env — add your ANTHROPIC_API_KEY or OPENAI_API_KEY

# Install dependencies with uv
uv sync

# Start PostgreSQL
docker compose up -d postgres

# Verify Python runs
uv run python -c "import langgraph; print(f'LangGraph {langgraph.__version__}')"
```

If that prints a version number, your environment is ready.

---

## 2. Step 1 — The Simplest Possible Agent

We start with the absolute minimum: an LLM that can answer marketing questions. No tools,
no database, no streaming. Just a graph with one node that calls the LLM.

**Why start here?** Because the most common mistake beginners make is adding everything at
once and then not knowing what broke. We build a solid foundation first.

### config.py

```python
"""Application settings loaded from environment variables."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """All configuration loaded from .env or environment variables.

    Pydantic BaseSettings automatically reads from .env files and environment
    variables. Field names are case-insensitive for env vars.
    """

    # LLM settings
    anthropic_api_key: str = ""
    openai_api_key: str = ""
    llm_model: str = "claude-sonnet-4-20250514"

    # Database (used in Step 2)
    database_url: str = "postgresql+asyncpg://marketing:marketing_local@localhost:5432/marketing"

    # Sandbox (used in Step 3)
    sandbox_url: str = "http://localhost:8100"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


# Singleton — import this everywhere
settings = Settings()
```

### models/state.py

```python
"""Agent state — the shared data structure that flows through the graph."""

from typing import Annotated, TypedDict

from langchain_core.messages import BaseMessage
from langgraph.graph import add_messages


class AgentState(TypedDict):
    """The state that every node in the graph can read and write.

    `messages` is the conversation history. The `add_messages` reducer ensures
    new messages are appended (not replaced) when a node returns updates.

    This is intentionally minimal. We add fields as we need them.
    """

    messages: Annotated[list[BaseMessage], add_messages]
```

**Why TypedDict?** LangGraph requires it. Pydantic models would add validation overhead
that fights LangGraph's internal state management. TypedDict is the right tool here.

### graph/nodes/lead_agent.py

```python
"""The lead agent node — calls the LLM and returns its response."""

from langchain_core.messages import SystemMessage

from marketing_agent.config import settings
from marketing_agent.models.state import AgentState


def _build_llm():
    """Create the LLM client based on the configured model.

    We support both Anthropic and OpenAI models. The model name prefix
    tells us which provider to use.
    """
    model = settings.llm_model

    if model.startswith("claude"):
        from langchain_anthropic import ChatAnthropic

        return ChatAnthropic(
            model=model,
            api_key=settings.anthropic_api_key,
            max_tokens=4096,
        )
    else:
        from langchain_openai import ChatOpenAI

        return ChatOpenAI(
            model=model,
            api_key=settings.openai_api_key,
        )


# Build once at import time
llm = _build_llm()

# The system prompt — we will expand this significantly in Step 8
SYSTEM_PROMPT = """You are a marketing analytics assistant. You help marketing teams
understand their campaign performance data, identify trends, and make data-driven decisions.

When answering questions:
- Be specific and quantitative when possible
- Suggest relevant metrics (CTR, ROAS, CPA, CVR) when they apply
- If you don't have access to actual data yet, give helpful general guidance
- Format numbers clearly (use commas, round percentages to 1 decimal)
"""


async def lead_agent(state: AgentState) -> dict:
    """Call the LLM with the full conversation history.

    This node:
    1. Prepends the system prompt to the conversation
    2. Sends everything to the LLM
    3. Returns the LLM's response (which gets appended to messages via the reducer)
    """
    # Build the message list: system prompt + conversation history
    messages = [SystemMessage(content=SYSTEM_PROMPT)] + state["messages"]

    # Call the LLM
    response = await llm.ainvoke(messages)

    # Return the update — add_messages reducer appends this to state["messages"]
    return {"messages": [response]}
```

### graph/graph.py

```python
"""Build and compile the LangGraph graph.

This is the simplest possible graph: START → lead_agent → END.
No tools, no routing, no loops. We add those in Step 2.
"""

from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver

from marketing_agent.models.state import AgentState
from marketing_agent.graph.nodes.lead_agent import lead_agent


def build_graph():
    """Construct the agent graph.

    Returns a compiled graph that can be invoked with `.ainvoke()` or
    streamed with `.astream()`.
    """
    graph = StateGraph(AgentState)

    # One node: the LLM
    graph.add_node("lead_agent", lead_agent)

    # START → lead_agent → END
    graph.set_entry_point("lead_agent")
    graph.add_edge("lead_agent", END)

    # MemorySaver enables conversation memory (in-process, lost on restart)
    # We upgrade to PostgreSQL checkpointing later
    checkpointer = MemorySaver()

    return graph.compile(checkpointer=checkpointer)
```

### main.py

```python
"""CLI entry point — chat with the agent in your terminal."""

import asyncio
import uuid

from langchain_core.messages import HumanMessage

from marketing_agent.graph.graph import build_graph


async def main():
    """Simple REPL (Read-Eval-Print Loop) for chatting with the agent."""
    graph = build_graph()

    # Each conversation gets a unique thread_id for checkpointing
    thread_id = str(uuid.uuid4())
    config = {"configurable": {"thread_id": thread_id}}

    print("Marketing Analytics Agent")
    print("Type 'quit' to exit, 'new' for a new conversation.\n")

    while True:
        user_input = input("You: ").strip()

        if not user_input:
            continue
        if user_input.lower() == "quit":
            break
        if user_input.lower() == "new":
            thread_id = str(uuid.uuid4())
            config = {"configurable": {"thread_id": thread_id}}
            print("--- New conversation ---\n")
            continue

        # Invoke the graph with the user's message
        result = await graph.ainvoke(
            {"messages": [HumanMessage(content=user_input)]},
            config=config,
        )

        # The last message in the result is the agent's response
        agent_message = result["messages"][-1]
        print(f"\nAgent: {agent_message.content}\n")


if __name__ == "__main__":
    asyncio.run(main())
```

### Test it

```bash
uv run python -m marketing_agent.main
```

Try these prompts:

```
You: What metrics should I track for a Google Ads campaign?
You: Which of those is most important for an e-commerce brand?
You: How do I calculate ROAS?
```

Notice the second question works because of checkpointing — the agent remembers the first
question's context via the `thread_id`.

### What You Built

- A LangGraph state graph with one node (LLM call)
- Configuration from environment variables (Pydantic BaseSettings)
- In-memory checkpointing for conversation continuity
- A CLI REPL for testing

### What is happening step by step

1. `main.py` creates the graph and a `thread_id`
2. Your input becomes a `HumanMessage` added to `state["messages"]`
3. The `lead_agent` node runs: prepends the system prompt, calls the LLM, returns the response
4. The `add_messages` reducer appends the response to the messages list
5. The graph reaches END (there is only one edge: `lead_agent → END`)
6. LangGraph saves the full state (all messages) to the `MemorySaver` under the `thread_id`
7. On the next turn, LangGraph loads the saved state, so the LLM sees the full conversation

> **Common Mistake**: Forgetting the `config` parameter when calling `ainvoke()`. Without it,
> the checkpointer has no thread_id and the agent loses context between turns. You will get
> an error like "Missing configurable field: thread_id".

### Try It

1. Start a conversation, ask 3 follow-up questions, verify the agent remembers context
2. Type `new`, ask about the previous topic, verify the agent does NOT remember (new thread)
3. Change `LLM_MODEL` in `.env` to a different model, restart, see how responses differ

---

## 3. Step 2 — Add Tools (ReAct Loop)

The agent can chat, but it cannot access real data. Now we give it tools: the ability to
query a PostgreSQL database full of marketing campaign data. This transforms it from a
chatbot into an agent.

### db/connection.py

```python
"""Async SQLAlchemy database engine and session factory."""

from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

from marketing_agent.config import settings

# Create the async engine — this manages a connection pool
# echo=True is useful during development (logs all SQL queries)
engine = create_async_engine(
    settings.database_url,
    echo=False,       # Set True to see SQL in logs during debugging
    pool_size=5,      # Max concurrent connections
    max_overflow=10,  # Extra connections allowed under load
)

# Session factory — use this to create sessions for queries
async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
```

### db/seed.py

This generates realistic marketing data. Run it once to populate your database.

```python
"""Seed the marketing database with realistic sample data.

Creates tables: campaigns, ad_groups, ads, daily_metrics, audience_segments.
Generates 6 months of daily data across 3 platforms (Google Ads, Meta, LinkedIn)
with realistic patterns: weekday/weekend variation, seasonal trends, platform
differences.
"""

import asyncio
import random
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy import text

from marketing_agent.db.connection import engine


# Platform-specific characteristics (realistic cost ranges)
PLATFORMS = {
    "google_ads": {
        "avg_cpc": (0.50, 3.50),
        "avg_ctr": (0.02, 0.08),
        "avg_cvr": (0.02, 0.06),
        "campaign_types": ["search", "display", "shopping", "performance_max"],
    },
    "meta": {
        "avg_cpc": (0.30, 2.00),
        "avg_ctr": (0.01, 0.04),
        "avg_cvr": (0.01, 0.04),
        "campaign_types": ["awareness", "traffic", "conversions", "retargeting"],
    },
    "linkedin": {
        "avg_cpc": (2.00, 8.00),
        "avg_ctr": (0.005, 0.025),
        "avg_cvr": (0.01, 0.03),
        "campaign_types": ["sponsored_content", "message_ads", "lead_gen"],
    },
}

AUDIENCE_SEGMENTS = [
    ("high_intent_search", "Users searching for product keywords", "google_ads"),
    ("brand_search", "Users searching for brand terms", "google_ads"),
    ("competitor_conquest", "Users searching for competitor brands", "google_ads"),
    ("lookalike_purchasers", "1% lookalike of past purchasers", "meta"),
    ("retargeting_30d", "Website visitors in last 30 days", "meta"),
    ("interest_marketing", "Interest: Digital Marketing", "meta"),
    ("broad_prospecting", "Broad audience with auto-optimization", "meta"),
    ("decision_makers", "Job title: Director+ in Marketing", "linkedin"),
    ("saas_companies", "Company industry: SaaS, 50-500 employees", "linkedin"),
    ("engaged_audience", "Engaged with company page in last 90 days", "linkedin"),
]


async def seed():
    """Create tables and insert seed data."""
    async with engine.begin() as conn:
        # Drop and recreate tables (idempotent seed)
        await conn.execute(text("DROP TABLE IF EXISTS daily_metrics CASCADE"))
        await conn.execute(text("DROP TABLE IF EXISTS ads CASCADE"))
        await conn.execute(text("DROP TABLE IF EXISTS ad_groups CASCADE"))
        await conn.execute(text("DROP TABLE IF EXISTS campaigns CASCADE"))
        await conn.execute(text("DROP TABLE IF EXISTS audience_segments CASCADE"))

        # --- campaigns ---
        await conn.execute(text("""
            CREATE TABLE campaigns (
                id SERIAL PRIMARY KEY,
                name VARCHAR(200) NOT NULL,
                platform VARCHAR(50) NOT NULL,
                campaign_type VARCHAR(50) NOT NULL,
                status VARCHAR(20) NOT NULL DEFAULT 'active',
                daily_budget NUMERIC(10, 2) NOT NULL,
                start_date DATE NOT NULL,
                end_date DATE,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """))

        # --- ad_groups ---
        await conn.execute(text("""
            CREATE TABLE ad_groups (
                id SERIAL PRIMARY KEY,
                campaign_id INTEGER REFERENCES campaigns(id),
                name VARCHAR(200) NOT NULL,
                targeting_type VARCHAR(50),
                audience_segment VARCHAR(100),
                status VARCHAR(20) NOT NULL DEFAULT 'active'
            )
        """))

        # --- ads ---
        await conn.execute(text("""
            CREATE TABLE ads (
                id SERIAL PRIMARY KEY,
                ad_group_id INTEGER REFERENCES ad_groups(id),
                name VARCHAR(200) NOT NULL,
                headline VARCHAR(200),
                description TEXT,
                creative_type VARCHAR(50),
                status VARCHAR(20) NOT NULL DEFAULT 'active'
            )
        """))

        # --- daily_metrics ---
        await conn.execute(text("""
            CREATE TABLE daily_metrics (
                id SERIAL PRIMARY KEY,
                campaign_id INTEGER REFERENCES campaigns(id),
                ad_group_id INTEGER REFERENCES ad_groups(id),
                ad_id INTEGER REFERENCES ads(id),
                date DATE NOT NULL,
                impressions INTEGER NOT NULL DEFAULT 0,
                clicks INTEGER NOT NULL DEFAULT 0,
                conversions INTEGER NOT NULL DEFAULT 0,
                spend NUMERIC(10, 2) NOT NULL DEFAULT 0,
                revenue NUMERIC(10, 2) NOT NULL DEFAULT 0,
                platform VARCHAR(50) NOT NULL
            )
        """))

        # --- audience_segments ---
        await conn.execute(text("""
            CREATE TABLE audience_segments (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                description TEXT,
                platform VARCHAR(50) NOT NULL,
                estimated_size INTEGER,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """))

        # --- Seed audience segments ---
        for seg_name, seg_desc, seg_platform in AUDIENCE_SEGMENTS:
            await conn.execute(
                text("""
                    INSERT INTO audience_segments (name, description, platform, estimated_size)
                    VALUES (:name, :desc, :platform, :size)
                """),
                {
                    "name": seg_name,
                    "desc": seg_desc,
                    "platform": seg_platform,
                    "size": random.randint(50_000, 5_000_000),
                },
            )

        # --- Seed campaigns, ad_groups, ads, and daily_metrics ---
        start_date = date(2025, 10, 1)  # 6 months of data
        end_date = date(2026, 3, 31)
        campaign_id = 0
        ad_group_id = 0
        ad_id = 0

        for platform, config in PLATFORMS.items():
            for ctype in config["campaign_types"]:
                campaign_id += 1
                budget = round(random.uniform(50, 500), 2)

                await conn.execute(
                    text("""
                        INSERT INTO campaigns (id, name, platform, campaign_type, status,
                                               daily_budget, start_date)
                        VALUES (:id, :name, :platform, :ctype, 'active', :budget, :start)
                    """),
                    {
                        "id": campaign_id,
                        "name": f"{platform}_{ctype}_{campaign_id:03d}",
                        "platform": platform,
                        "ctype": ctype,
                        "budget": budget,
                        "start": start_date,
                    },
                )

                # 2-3 ad groups per campaign
                for ag_idx in range(random.randint(2, 3)):
                    ad_group_id += 1
                    segments = [s[0] for s in AUDIENCE_SEGMENTS if s[2] == platform]
                    segment = random.choice(segments) if segments else None

                    await conn.execute(
                        text("""
                            INSERT INTO ad_groups (id, campaign_id, name,
                                                   targeting_type, audience_segment)
                            VALUES (:id, :cid, :name, :targeting, :segment)
                        """),
                        {
                            "id": ad_group_id,
                            "cid": campaign_id,
                            "name": f"ag_{ctype}_{ag_idx + 1}",
                            "targeting": random.choice(
                                ["keyword", "audience", "contextual", "auto"]
                            ),
                            "segment": segment,
                        },
                    )

                    # 2-3 ads per ad group
                    for ad_idx in range(random.randint(2, 3)):
                        ad_id += 1
                        await conn.execute(
                            text("""
                                INSERT INTO ads (id, ad_group_id, name, headline,
                                                 description, creative_type)
                                VALUES (:id, :agid, :name, :headline, :desc, :creative)
                            """),
                            {
                                "id": ad_id,
                                "agid": ad_group_id,
                                "name": f"ad_{ad_idx + 1}",
                                "headline": random.choice([
                                    "Boost Your ROI Today",
                                    "Scale Your Marketing",
                                    "Drive More Conversions",
                                    "Grow Revenue Faster",
                                    "Cut Acquisition Costs",
                                ]),
                                "desc": "Sample ad description for testing.",
                                "creative": random.choice(
                                    ["text", "image", "video", "carousel"]
                                ),
                            },
                        )

                    # Daily metrics for this ad group
                    current = start_date
                    while current <= end_date:
                        # Realistic patterns
                        is_weekend = current.weekday() >= 5
                        month_factor = 1.0 + 0.1 * (
                            (current.month - 10) % 12
                        )  # slight growth over time

                        # Weekend traffic is lower
                        weekend_factor = 0.6 if is_weekend else 1.0

                        cpc_low, cpc_high = config["avg_cpc"]
                        ctr_low, ctr_high = config["avg_ctr"]
                        cvr_low, cvr_high = config["avg_cvr"]

                        daily_spend = round(
                            budget * random.uniform(0.7, 1.3) * weekend_factor * month_factor, 2
                        )
                        cpc = round(random.uniform(cpc_low, cpc_high), 2)
                        clicks = max(1, int(daily_spend / cpc))
                        ctr = random.uniform(ctr_low, ctr_high)
                        impressions = max(clicks, int(clicks / ctr))
                        cvr = random.uniform(cvr_low, cvr_high)
                        conversions = max(0, int(clicks * cvr))

                        # Revenue: average order value varies by platform
                        aov = {"google_ads": 85, "meta": 65, "linkedin": 250}[platform]
                        revenue = round(
                            conversions * aov * random.uniform(0.8, 1.2), 2
                        )

                        await conn.execute(
                            text("""
                                INSERT INTO daily_metrics
                                    (campaign_id, ad_group_id, ad_id, date,
                                     impressions, clicks, conversions, spend, revenue, platform)
                                VALUES (:cid, :agid, :adid, :date,
                                        :imp, :clicks, :conv, :spend, :rev, :platform)
                            """),
                            {
                                "cid": campaign_id,
                                "agid": ad_group_id,
                                "adid": ad_id,
                                "date": current,
                                "imp": impressions,
                                "clicks": clicks,
                                "conv": conversions,
                                "spend": daily_spend,
                                "rev": revenue,
                                "platform": platform,
                            },
                        )
                        current += timedelta(days=1)

    print(f"Seeded {campaign_id} campaigns, {ad_group_id} ad groups, {ad_id} ads")
    print(f"Date range: {start_date} to {end_date} ({(end_date - start_date).days} days)")


if __name__ == "__main__":
    asyncio.run(seed())
```

### scripts/seed_data.py

```python
"""Script entry point for seeding the database."""

import asyncio
from marketing_agent.db.seed import seed

if __name__ == "__main__":
    asyncio.run(seed())
```

Run the seed:

```bash
# Make sure PostgreSQL is running
docker compose up -d postgres

# Seed the database
uv run python -m marketing_agent.db.seed
```

### tools/list_tables.py

```python
"""Tool: list all tables in the marketing database."""

from langchain_core.tools import tool
from sqlalchemy import text

from marketing_agent.db.connection import async_session


@tool
async def list_tables() -> str:
    """List all tables in the marketing database with their row counts.

    Use this as your FIRST step when you need to understand what data is available.
    Returns a list of table names and approximate row counts.
    """
    async with async_session() as session:
        result = await session.execute(text("""
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'public'
            ORDER BY tablename
        """))
        tables = [row[0] for row in result.fetchall()]

        if not tables:
            return "No tables found in the public schema."

        lines = ["Available tables:"]
        for table in tables:
            count_result = await session.execute(
                text(f"SELECT COUNT(*) FROM {table}")  # noqa: S608
            )
            count = count_result.scalar()
            lines.append(f"  - {table}: {count:,} rows")

        return "\n".join(lines)
```

### tools/describe_table.py

```python
"""Tool: describe a table's columns and sample data."""

from langchain_core.tools import tool
from sqlalchemy import text

from marketing_agent.db.connection import async_session


@tool
async def describe_table(table_name: str) -> str:
    """Show the columns, data types, and sample rows for a specific table.

    Use this after list_tables to understand a table's structure before
    writing SQL queries. This helps you write correct column names and
    understand the data types.

    Args:
        table_name: The name of the table to describe (e.g., "campaigns", "daily_metrics").
    """
    async with async_session() as session:
        # Get column info
        cols_result = await session.execute(text("""
            SELECT column_name, data_type, is_nullable
            FROM information_schema.columns
            WHERE table_name = :table AND table_schema = 'public'
            ORDER BY ordinal_position
        """), {"table": table_name})
        columns = cols_result.fetchall()

        if not columns:
            return f"Table '{table_name}' not found. Use list_tables to see available tables."

        lines = [f"Table: {table_name}", "", "Columns:"]
        for col_name, data_type, nullable in columns:
            null_str = "NULL" if nullable == "YES" else "NOT NULL"
            lines.append(f"  - {col_name}: {data_type} ({null_str})")

        # Show sample rows
        sample_result = await session.execute(
            text(f"SELECT * FROM {table_name} LIMIT 3")  # noqa: S608
        )
        sample_rows = sample_result.fetchall()
        col_names = [c[0] for c in columns]

        if sample_rows:
            lines.append("")
            lines.append("Sample rows (first 3):")
            lines.append("  " + " | ".join(col_names))
            lines.append("  " + "-" * (len(" | ".join(col_names))))
            for row in sample_rows:
                lines.append("  " + " | ".join(str(v) for v in row))

        return "\n".join(lines)
```

### tools/query_data.py

This is the most important tool. It lets the agent query real data.

```python
"""Tool: execute read-only SQL queries against the marketing database."""

import re

from langchain_core.tools import tool
from sqlalchemy import text

from marketing_agent.db.connection import async_session


# Maximum rows to return — prevents the agent from dumping huge result sets
# into the LLM context window. The agent can always narrow its query.
MAX_ROWS = 200


def _validate_sql(sql: str) -> str | None:
    """Check that the SQL is read-only. Returns an error message or None if valid.

    This is not a SQL parser — it's a safety net. A determined attacker could
    bypass this, but the agent isn't an attacker. This catches the common case:
    the LLM accidentally generating a write query.
    """
    normalized = sql.strip().upper()

    # Must start with SELECT or WITH (CTEs)
    if not (normalized.startswith("SELECT") or normalized.startswith("WITH")):
        return "Only SELECT queries are allowed. Query must start with SELECT or WITH."

    # Block write operations
    write_keywords = ["INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "CREATE", "TRUNCATE"]
    for keyword in write_keywords:
        # Match keyword as a standalone word (not inside a column name or string)
        if re.search(rf"\b{keyword}\b", normalized):
            return f"Write operations are not allowed. Found '{keyword}' in query."

    return None


@tool
async def query_data(sql: str) -> str:
    """Execute a read-only SQL query against the marketing database and return results.

    Use this to fetch campaign metrics, performance data, platform breakdowns,
    and any analysis data. Only SELECT queries are allowed.

    TIPS for writing good queries:
    - Use list_tables and describe_table first to learn the schema
    - Always include a LIMIT clause (max 200 rows returned regardless)
    - Use aggregations (SUM, AVG, COUNT) to summarize large datasets
    - The daily_metrics table has: date, impressions, clicks, conversions, spend, revenue, platform
    - Calculate derived metrics in SQL: CTR = clicks/impressions, ROAS = revenue/spend,
      CPC = spend/clicks, CVR = conversions/clicks

    Args:
        sql: A read-only SQL query (SELECT only). Include aggregations and LIMIT when possible.
    """
    # Validate the query
    error = _validate_sql(sql)
    if error:
        return f"ERROR: {error}"

    try:
        async with async_session() as session:
            result = await session.execute(text(sql))
            rows = result.fetchmany(MAX_ROWS + 1)  # Fetch one extra to detect truncation
            col_names = list(result.keys())

            if not rows:
                return "Query returned 0 rows."

            truncated = len(rows) > MAX_ROWS
            if truncated:
                rows = rows[:MAX_ROWS]

            # Format as a readable text table
            lines = [f"Query returned {len(rows)}{'+ (truncated)' if truncated else ''} rows.", ""]

            # Column headers
            lines.append(" | ".join(col_names))
            lines.append("-" * len(lines[-1]))

            # Data rows
            for row in rows:
                lines.append(" | ".join(str(v) for v in row))

            if truncated:
                lines.append("")
                lines.append(
                    f"NOTE: Results truncated to {MAX_ROWS} rows. "
                    "Add a LIMIT clause or more specific WHERE conditions."
                )

            return "\n".join(lines)

    except Exception as e:
        return f"SQL ERROR: {type(e).__name__}: {e}"
```

**Why return text, not JSON?** LLMs are better at reading formatted text than parsing JSON.
The text table format is easier for the LLM to reason about and reference in its response.

### Updated graph/nodes/lead_agent.py

Now we bind tools to the LLM so it can call them:

```python
"""The lead agent node — calls the LLM with tools bound."""

from langchain_core.messages import SystemMessage

from marketing_agent.config import settings
from marketing_agent.models.state import AgentState


def _build_llm():
    """Create the LLM client based on the configured model."""
    model = settings.llm_model

    if model.startswith("claude"):
        from langchain_anthropic import ChatAnthropic

        return ChatAnthropic(
            model=model,
            api_key=settings.anthropic_api_key,
            max_tokens=4096,
        )
    else:
        from langchain_openai import ChatOpenAI

        return ChatOpenAI(
            model=model,
            api_key=settings.openai_api_key,
        )


# Import all tools
from marketing_agent.tools.query_data import query_data
from marketing_agent.tools.list_tables import list_tables
from marketing_agent.tools.describe_table import describe_table

# The tool list — order doesn't matter, but grouping helps readability
tools = [list_tables, describe_table, query_data]

# Build the LLM with tools bound
# bind_tools() tells the LLM about available tools via the API's tool/function schema
llm = _build_llm()
llm_with_tools = llm.bind_tools(tools)

SYSTEM_PROMPT = """You are a marketing analytics assistant with access to a PostgreSQL database
containing campaign performance data.

Your workflow:
1. ALWAYS start by calling list_tables to see what data is available
2. Use describe_table to understand table structure before writing queries
3. Use query_data to fetch actual data
4. Analyze the results and provide clear, actionable insights

When writing SQL:
- Always use aggregations (SUM, AVG, COUNT, GROUP BY) for large datasets
- Calculate derived metrics: CTR = clicks::float/impressions, ROAS = revenue/spend,
  CPC = spend/clicks, CVR = conversions::float/clicks
- Use ROUND() to keep numbers readable
- Always include ORDER BY for sorted results
- Use LIMIT to keep results manageable

Format your responses with:
- Key metrics highlighted (bold or bullet points)
- Comparisons when relevant (vs. previous period, vs. other platforms)
- Clear recommendations based on the data
"""


async def lead_agent(state: AgentState) -> dict:
    """Call the LLM with tools bound.

    When the LLM wants to use a tool, it returns an AIMessage with `tool_calls`
    populated. When it has a final answer, it returns an AIMessage with `content`
    and no tool_calls.
    """
    messages = [SystemMessage(content=SYSTEM_PROMPT)] + state["messages"]
    response = await llm_with_tools.ainvoke(messages)
    return {"messages": [response]}
```

### graph/nodes/router.py

```python
"""Route the graph based on whether the LLM wants to call tools or is done."""

from marketing_agent.models.state import AgentState

# These are string constants that match the node names in the graph.
# Using constants prevents typos.
TOOL_EXECUTOR = "tool_executor"
END = "end"


def router(state: AgentState) -> str:
    """Decide the next node based on the LLM's last message.

    If the last message has tool_calls → route to tool_executor.
    If the last message has no tool_calls → route to END (the agent is done).

    This is a pure function: reads state, returns a string. No side effects.
    """
    last_message = state["messages"][-1]

    # AIMessage with tool_calls means the LLM wants to use tools
    if hasattr(last_message, "tool_calls") and last_message.tool_calls:
        return TOOL_EXECUTOR

    # No tool calls means the LLM produced a final text response
    return END
```

### graph/nodes/tool_executor.py

```python
"""Execute tool calls requested by the LLM."""

from langchain_core.messages import ToolMessage

from marketing_agent.models.state import AgentState
from marketing_agent.tools.query_data import query_data
from marketing_agent.tools.list_tables import list_tables
from marketing_agent.tools.describe_table import describe_table

# Map tool names to their implementations
# When we add more tools (python_exec, etc.), we add them here
TOOL_MAP: dict = {
    "list_tables": list_tables,
    "describe_table": describe_table,
    "query_data": query_data,
}


async def tool_executor(state: AgentState) -> dict:
    """Execute all tool calls from the LLM's last message.

    For each tool call:
    1. Look up the tool function by name
    2. Call it with the provided arguments
    3. Wrap the result in a ToolMessage (linked by tool_call_id)

    The ToolMessage is critical — it tells the LLM which tool call each result
    belongs to. Without the correct tool_call_id, the LLM cannot match results
    to its requests.
    """
    last_message = state["messages"][-1]
    results = []

    for tool_call in last_message.tool_calls:
        tool_name = tool_call["name"]
        tool_args = tool_call["args"]
        tool_call_id = tool_call["id"]

        # Look up the tool
        tool_fn = TOOL_MAP.get(tool_name)
        if tool_fn is None:
            # The LLM hallucinated a tool name that doesn't exist
            results.append(ToolMessage(
                content=f"ERROR: Unknown tool '{tool_name}'. Available tools: {list(TOOL_MAP.keys())}",
                tool_call_id=tool_call_id,
            ))
            continue

        try:
            # Execute the tool — all tools are async
            result = await tool_fn.ainvoke(tool_args)
            results.append(ToolMessage(
                content=str(result),
                tool_call_id=tool_call_id,
            ))
        except Exception as e:
            # Tool errors go back to the LLM as ToolMessages so it can recover
            # (e.g., fix a SQL syntax error and retry)
            results.append(ToolMessage(
                content=f"ERROR executing {tool_name}: {type(e).__name__}: {e}",
                tool_call_id=tool_call_id,
            ))

    return {"messages": results}
```

**Why not use LangGraph's built-in `ToolNode`?** You can — `ToolNode(tools)` does the same
thing in fewer lines. We write it manually here so you understand exactly what happens. Once
you understand the mechanics, feel free to use `ToolNode` in your own code.

### Updated graph/graph.py

```python
"""Build the ReAct agent graph — LLM with tools in a loop."""

from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver

from marketing_agent.models.state import AgentState
from marketing_agent.graph.nodes.lead_agent import lead_agent
from marketing_agent.graph.nodes.router import router, TOOL_EXECUTOR
from marketing_agent.graph.nodes.tool_executor import tool_executor


def build_graph():
    """Construct the ReAct agent graph.

    The graph looks like this:

        START → lead_agent → router → tool_executor → lead_agent → ... → END

    The lead_agent ↔ tool_executor loop repeats until the LLM produces a final
    text answer (no tool_calls), at which point the router sends it to END.
    """
    graph = StateGraph(AgentState)

    # Add all nodes
    graph.add_node("lead_agent", lead_agent)
    graph.add_node("tool_executor", tool_executor)

    # Entry point
    graph.set_entry_point("lead_agent")

    # Conditional edge: after lead_agent, the router decides what's next
    graph.add_conditional_edges(
        "lead_agent",           # From this node...
        router,                 # Use this function to decide...
        {
            TOOL_EXECUTOR: "tool_executor",   # If router returns "tool_executor"
            "end": END,                        # If router returns "end"
        },
    )

    # After tools execute, always go back to the LLM
    # This is the loop — the LLM sees the tool results and decides what to do next
    graph.add_edge("tool_executor", "lead_agent")

    # Compile with checkpointing
    checkpointer = MemorySaver()
    return graph.compile(checkpointer=checkpointer)
```

### See the ReAct loop in action

```bash
uv run python -m marketing_agent.main
```

```
You: What was the total spend by platform last month?
```

Here is what happens behind the scenes (the agent's internal message flow):

```
1. HumanMessage("What was the total spend by platform last month?")

2. AIMessage(tool_calls=[{name: "list_tables", args: {}}])
   → Router: has tool_calls → route to tool_executor

3. ToolMessage("Available tables:\n  - campaigns: 11 rows\n  - daily_metrics: ...")
   → Edge: tool_executor → lead_agent

4. AIMessage(tool_calls=[{name: "query_data", args: {sql: "SELECT platform, ..."}}])
   → Router: has tool_calls → route to tool_executor

5. ToolMessage("Query returned 3 rows.\n\nplatform | total_spend\n...")
   → Edge: tool_executor → lead_agent

6. AIMessage(content="Here's the total spend by platform for March 2026:\n...")
   → Router: no tool_calls → route to END
```

The agent made 2 tool calls (list_tables, then query_data), got data back, and synthesized
a response. This is the ReAct loop: reason → act → observe → reason → act → observe → answer.

### What You Built

- Three tools: `list_tables`, `describe_table`, `query_data`
- A tool executor that runs tool calls and returns results as ToolMessages
- A router that sends the graph to tools or END based on the LLM's response
- A ReAct loop graph: `lead_agent → router → tool_executor → lead_agent → ...`
- A seeded PostgreSQL database with realistic marketing data

### Try It

1. Ask "Which campaign had the highest ROAS last month?" and watch the agent explore the schema
2. Ask a follow-up: "How does that compare to the previous month?" — the agent remembers context
3. Ask something the data can't answer: "What's Apple's ad spend?" — see how the agent responds
4. Intentionally ask for a write operation: "Delete all campaigns" — verify the SQL validation catches it

> **Common Mistake**: Returning raw SQL result objects instead of strings from tools. The LLM
> can only read text. If your tool returns a SQLAlchemy `Row` object, the LLM sees
> `<sqlalchemy.engine.row.Row object at 0x...>` and has no idea what the data is. Always
> convert to a formatted string.

---

## 4. Step 3 — The Python Sandbox

The agent can query data, but it cannot perform complex analysis. It cannot compute
moving averages, run statistical tests, or create visualizations. For that, it needs
to execute Python code.

We do NOT let the LLM run Python in the host process. Instead, we run it in an isolated
Docker container — the **sandbox**. This gives us:

- **Security**: the sandbox has no network access and limited resources
- **Libraries**: pandas, matplotlib, openpyxl, and more — pre-installed
- **Persistence**: files written in the sandbox persist across tool calls (this is critical)

### sandbox/Dockerfile

```dockerfile
FROM python:3.12-slim

# Install OS-level dependencies for weasyprint (PDF generation)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libgdk-pixbuf2.0-0 \
    libffi-dev \
    libcairo2 \
    && rm -rf /var/lib/apt/lists/*

# Install Python data science libraries
RUN pip install --no-cache-dir \
    pandas==2.2.* \
    matplotlib==3.9.* \
    seaborn==0.13.* \
    openpyxl==3.1.* \
    plotly==5.24.* \
    weasyprint==62.* \
    jinja2==3.1.* \
    tabulate==0.9.* \
    numpy==2.1.* \
    scipy==1.14.* \
    kaleido==0.2.*

# Create sandbox directories
RUN mkdir -p /sandbox/data /sandbox/charts /sandbox/exports
WORKDIR /sandbox

# Simple HTTP server that accepts code execution requests
# We use a minimal FastAPI app inside the sandbox
RUN pip install --no-cache-dir fastapi==0.115.* uvicorn==0.34.*

COPY server.py /app/server.py

EXPOSE 8100

CMD ["uvicorn", "app.server:app", "--host", "0.0.0.0", "--port", "8100"]
```

### sandbox/server.py

This tiny FastAPI app runs inside the Docker container. It receives code, executes it,
and returns the output.

```python
"""Sandbox execution server — runs inside the Docker container.

This file is NOT part of the main application. It is copied into the sandbox
Docker image and serves as the code execution endpoint.
"""

import io
import os
import sys
import base64
import traceback
from contextlib import redirect_stdout, redirect_stderr
from pathlib import Path

from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

SANDBOX = Path("/sandbox")


class ExecRequest(BaseModel):
    code: str
    timeout: int = 30  # seconds


class ExecResponse(BaseModel):
    stdout: str
    stderr: str
    success: bool
    files_created: list[str]  # new or modified files in the sandbox


@app.post("/exec")
async def execute_code(request: ExecRequest) -> ExecResponse:
    """Execute Python code and return stdout/stderr.

    The code runs in the /sandbox directory. Any files created there
    persist across calls (the directory is a Docker volume).
    """
    # Track files before execution to detect new ones
    files_before = set(SANDBOX.rglob("*"))

    stdout_capture = io.StringIO()
    stderr_capture = io.StringIO()

    try:
        # Execute the code with captured output
        with redirect_stdout(stdout_capture), redirect_stderr(stderr_capture):
            exec(request.code, {"__builtins__": __builtins__})  # noqa: S102

        success = True
    except Exception:
        stderr_capture.write(traceback.format_exc())
        success = False

    # Detect newly created files
    files_after = set(SANDBOX.rglob("*"))
    new_files = [str(f.relative_to(SANDBOX)) for f in (files_after - files_before) if f.is_file()]

    return ExecResponse(
        stdout=stdout_capture.getvalue(),
        stderr=stderr_capture.getvalue(),
        success=success,
        files_created=new_files,
    )


@app.get("/health")
async def health():
    return {"status": "ok"}
```

### sandbox/client.py

This runs in the **host** application and communicates with the sandbox over HTTP.

```python
"""Client for communicating with the Docker sandbox."""

from dataclasses import dataclass, field
import base64
from pathlib import Path

import httpx

from marketing_agent.config import settings


@dataclass
class SandboxClient:
    """Async HTTP client for the Python execution sandbox.

    The sandbox runs in a Docker container with no network access (except
    from the host). Files written in the sandbox persist across calls.

    Usage:
        client = SandboxClient()
        result = await client.execute("import pandas as pd; print(pd.__version__)")
        print(result["stdout"])  # "2.2.0"
    """

    base_url: str = field(default_factory=lambda: settings.sandbox_url)
    timeout: float = 60.0

    async def execute(self, code: str, timeout: int = 30) -> dict:
        """Execute Python code in the sandbox.

        Args:
            code: Python code to execute.
            timeout: Maximum execution time in seconds (enforced by the sandbox).

        Returns:
            Dict with keys: stdout, stderr, success, files_created.
        """
        async with httpx.AsyncClient(base_url=self.base_url, timeout=self.timeout) as client:
            response = await client.post("/exec", json={"code": code, "timeout": timeout})
            response.raise_for_status()
            return response.json()

    async def health_check(self) -> bool:
        """Check if the sandbox is running and healthy."""
        try:
            async with httpx.AsyncClient(base_url=self.base_url, timeout=5) as client:
                response = await client.get("/health")
                return response.status_code == 200
        except httpx.ConnectError:
            return False


# Singleton — shared across all tool calls
sandbox = SandboxClient()
```

### Updated docker-compose.yml

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: marketing
      POSTGRES_USER: marketing
      POSTGRES_PASSWORD: marketing_local
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U marketing"]
      interval: 5s
      timeout: 3s
      retries: 5

  sandbox:
    build:
      context: ./src/marketing_agent/sandbox
      dockerfile: Dockerfile
    ports:
      - "8100:8100"
    volumes:
      - sandbox_data:/sandbox
    mem_limit: 512m     # Prevent runaway memory usage
    cpus: 1.0           # Prevent runaway CPU usage
    network_mode: "none" # NO network access — security isolation
    # Override network_mode for initial build; sandbox accesses host via port mapping
    # In production you would use a Docker network with only the host allowed

volumes:
  pgdata:
  sandbox_data:
```

> **Important**: `network_mode: "none"` means the sandbox cannot reach the internet, your
> database, or any other service. The only way to get data into the sandbox is through
> `python_exec` (e.g., writing files with `open()`). The only way to get data out is through
> the stdout response from `execute`.
>
> In development, you need the host to reach the sandbox on port 8100. This requires the
> sandbox to be on a Docker network. Replace `network_mode: "none"` with a dedicated network
> during development if needed:
>
> ```yaml
> # Development alternative
> sandbox:
>   ...
>   networks:
>     - sandbox_net
>
> networks:
>   sandbox_net:
>     internal: true  # No internet, but host can connect via port mapping
> ```

### tools/python_exec.py

```python
"""Tool: execute Python code in the isolated sandbox."""

from langchain_core.tools import tool

from marketing_agent.sandbox.client import sandbox


@tool
async def python_exec(code: str) -> str:
    """Execute Python code in an isolated sandbox environment.

    The sandbox has pandas, matplotlib, seaborn, openpyxl, plotly, numpy, scipy,
    weasyprint, jinja2, and tabulate pre-installed.

    **Key pattern — sandbox-as-memory:**
    Data persists in the sandbox filesystem between calls. Use this to build up
    analysis step by step:

    1. query_data saves results to a CSV file
    2. python_exec reads that CSV with pandas and computes analysis
    3. python_exec writes a chart PNG, Excel file, or PDF report

    Files are stored in data/, charts/, exports/. Use print() to return results to the conversation.

    IMPORTANT:
    - Always print() your results — the return value is stdout
    - For charts, save to a file: plt.savefig('charts/chart.png')
    - For DataFrames, use print(df.to_string()) or print(df.to_markdown())
    - For file I/O, use open(), os.listdir(), pd.read_csv() directly
    - The sandbox has NO network access — all data must come from files

    Args:
        code: Python code to execute. Use print() to return output.
    """
    result = await sandbox.execute(code, timeout=30)

    parts = []

    if result["stdout"]:
        parts.append(result["stdout"])

    if result["stderr"] and not result["success"]:
        parts.append(f"ERROR:\n{result['stderr']}")

    if result["files_created"]:
        parts.append(f"Files created: {', '.join(result['files_created'])}")

    if not parts:
        parts.append("Code executed successfully (no output).")

    return "\n\n".join(parts)
```

### The Sandbox-as-Memory Pattern

This is the most important concept for understanding how the tools work together. Here is
a concrete example of how data flows through the system:

```
Step 1: Agent calls query_data
  → SQL runs against PostgreSQL
  → Returns text table to the LLM
  → Agent now knows the data shape

Step 2: Agent calls python_exec with code that:
  a) Queries the same data (or the agent asks query_data to save as CSV)
  b) Reads the CSV: pd.read_csv('data/campaign_spend.csv')
  c) Computes analysis: pivot tables, aggregations, statistical tests
  d) Saves a chart: plt.savefig('charts/spend_by_platform.png')
  e) print()s the key findings

Step 3: Agent calls python_exec again to:
  a) Read the previous chart or data
  b) Create an Excel workbook combining multiple analyses (openpyxl)
  c) Generate a PDF report (weasyprint)

The sandbox filesystem is the persistent memory between tool calls.
```

The LLM cannot hold 10,000 rows of data in its context window. But the sandbox can hold
them in files. The agent learns to use the sandbox as scratch space — writing intermediate
results as CSVs, reading them back for further analysis.

### Update the tool executor

Add `python_exec` to the tool map:

```python
# In graph/nodes/tool_executor.py — add this import and map entry:
from marketing_agent.tools.python_exec import python_exec

TOOL_MAP: dict = {
    "list_tables": list_tables,
    "describe_table": describe_table,
    "query_data": query_data,
    "python_exec": python_exec,
}
```

And add it to the lead agent's tools:

```python
# In graph/nodes/lead_agent.py — add to the tools list:
from marketing_agent.tools.python_exec import python_exec

tools = [list_tables, describe_table, query_data, python_exec]
```

### Test it

```bash
# Build the sandbox image and start everything
docker compose up -d --build

# Verify the sandbox is healthy
curl http://localhost:8100/health
# Should return: {"status":"ok"}

# Run the agent
uv run python -m marketing_agent.main
```

```
You: Calculate the week-over-week growth rate of spend for each platform and show me a summary table
```

Watch the agent:
1. Call `list_tables` to discover the schema
2. Call `query_data` to fetch weekly spend data
3. Call `python_exec` with pandas code to compute growth rates
4. Return a formatted analysis

### What You Built

- A Docker sandbox with Python data science libraries
- An HTTP client (`SandboxClient`) for executing code in the sandbox
- The `python_exec` tool that bridges the agent and the sandbox
- The sandbox-as-memory pattern for multi-step analysis

### Try It

1. Ask the agent to "calculate a 7-day moving average of spend for Google Ads"
2. Ask it to "find the correlation between spend and conversions across platforms"
3. Ask it to compute something complex: "Run a t-test comparing Google Ads vs Meta CTR"

> **Common Mistake**: Forgetting to use `print()` in sandbox code. The `python_exec` tool
> returns stdout. If your code computes a result but never prints it, the LLM sees
> "Code executed successfully (no output)" and has no idea what happened. Always end
> sandbox code with `print(result)`.

---

## 5. Step 4 — Smart Agent, Simple Tools (Visualization and Export)

The agent can query data and run Python. Now we need charts, Excel files, and PDF reports.

You might expect us to build specialized tools like `export_chart`, `export_excel`, and
`export_report`. We are NOT going to do that. Instead, we follow the **"smart agent, simple
tools"** philosophy: the agent writes the code itself using `python_exec`, and we provide
only generic file I/O tools.

### Why no specialized export tools?

Here is the key insight: the sandbox already has matplotlib, openpyxl, and weasyprint
installed. The agent can write code that uses those libraries directly. Adding a
`export_chart` tool that wraps matplotlib does not add capability — it just adds a layer
of indirection that the LLM must learn to use correctly.

**Problems with convenience wrapper tools:**

1. **Rigid interfaces**: `export_chart(code, save_as)` still requires the agent to write
   matplotlib code. The wrapper adds parameters without reducing complexity.
2. **Maintenance burden**: Every library update, every new chart type, every edge case
   requires updating the wrapper tool. With `python_exec`, the agent adapts automatically.
3. **Wasted tool calls**: The agent must call `export_chart` for charts, `export_excel` for
   Excel, `export_report` for PDF. With `python_exec`, one tool call can produce all three.
4. **The LLM is smart enough**: Modern LLMs write excellent matplotlib, openpyxl, and
   weasyprint code. They do not need training wheels.

**The philosophy**: Give the agent a small number of powerful, generic tools. Let the LLM's
intelligence handle the specifics. Smart agent, simple tools.

### The 4 tools

Our complete toolset:

| Category | Tool | Purpose |
|----------|------|---------|
| Data | `query_data` | Execute read-only SQL against PostgreSQL |
| Data | `list_tables` | Discover available tables and row counts |
| Data | `describe_table` | See columns, types, and sample data |
| Compute | `python_exec` | Execute Python code in the sandbox (charts, Excel, PDF, analysis, file I/O — EVERYTHING) |

That is it. No `export_chart`, no `export_excel`, no `export_report`. The agent uses
`python_exec` with `open()`, `os.listdir()`, and `pd.read_csv()` for all file operations.

### How the agent creates charts (via python_exec)

When the user asks "Show me a bar chart of spend by platform", the agent writes matplotlib
code and executes it with `python_exec`:

```python
# The agent sends this code via python_exec:
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
sns.set_theme(style="whitegrid")

df = pd.read_csv('data/spend_by_platform.csv')
fig, ax = plt.subplots(figsize=(10, 6))
sns.barplot(data=df, x='platform', y='total_spend', ax=ax)
ax.set_title('Total Spend by Platform')
ax.set_ylabel('Spend ($)')
plt.tight_layout()
plt.savefig('charts/chart.png', dpi=150, bbox_inches='tight')
plt.close()
print("Chart saved to charts/chart.png")
```

The agent learned matplotlib from its training data. It does not need a wrapper.

### How the agent creates Excel files (via python_exec)

```python
# The agent sends this code via python_exec:
import pandas as pd
from openpyxl.styles import Font

df = pd.read_csv('data/campaign_data.csv')

with pd.ExcelWriter('exports/report.xlsx', engine='openpyxl') as writer:
    df.to_excel(writer, sheet_name='Campaign Data', index=False)

    pivot = df.pivot_table(values='spend', index='platform', aggfunc='sum')
    pivot.to_excel(writer, sheet_name='Platform Summary')

    for sheet_name in writer.sheets:
        ws = writer.sheets[sheet_name]
        for cell in ws[1]:
            cell.font = Font(bold=True)

print("Excel saved to exports/report.xlsx")
```

### How the agent creates PDF reports (via python_exec)

```python
# The agent sends this code via python_exec:
from weasyprint import HTML
from datetime import date

html = f"""
<html>
<head><style>
    body {{ font-family: sans-serif; margin: 2cm; }}
    h1 {{ color: #1a1a2e; border-bottom: 2px solid #4a90d9; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ border: 1px solid #ddd; padding: 8px; }}
    th {{ background: #4a90d9; color: white; }}
    img {{ max-width: 100%; }}
</style></head>
<body>
    <h1>Q1 Marketing Report</h1>
    <p>Generated on {date.today().strftime('%B %d, %Y')}</p>
    <h2>Spend by Platform</h2>
    <img src="charts/chart.png" />
    <h2>Summary</h2>
    <p>Google Ads: $145K (ROAS 3.2x) ...</p>
</body>
</html>
"""

HTML(string=html, base_url="./").write_pdf("exports/report.pdf")
print("PDF saved to exports/report.pdf")
```

The agent writes the HTML+CSS, embeds charts it already created, and generates the PDF.
No wrapper tool needed.

### Example interactions

**Chart generation:**
```
You: Show me a bar chart of total spend by platform for March 2026
```

The agent will:
1. Call `query_data` to get spend data grouped by platform
2. Call `python_exec` to save the query results as a CSV and generate a matplotlib chart
3. Report that the chart is saved to `charts/chart.png`

**Excel export:**
```
You: Export all campaign data as an Excel file with a summary sheet
```

The agent will:
1. Call `query_data` to fetch campaign data
2. Call `python_exec` with openpyxl code that creates a multi-sheet workbook
3. Report the Excel file is ready at `exports/report.xlsx`

**PDF report:**
```
You: Create a PDF report of Q1 performance with charts
```

The agent will:
1. Call `query_data` to fetch data
2. Call `python_exec` to create charts with matplotlib
3. Call `python_exec` again with weasyprint code to generate a PDF embedding the charts
4. Report the PDF is ready at `exports/report.pdf`

### What You Built

- The "smart agent, simple tools" philosophy: 4 generic tools instead of specialized wrappers
- The agent handles charts (matplotlib), Excel (openpyxl), and PDF (weasyprint) via `python_exec`

### Try It

1. Ask for a "line chart showing daily spend trends for the last 30 days by platform"
2. Ask for a "PDF report summarizing Q1 performance with charts and tables"
3. Ask for an "Excel workbook with separate sheets for each platform's monthly metrics"

> **Common Mistake**: Forgetting that `python_exec` stdout is the only feedback the agent
> gets. If the agent writes matplotlib code but forgets `print("Chart saved to ...")`,
> it will not know whether the chart was created. The system prompt should instruct
> the agent to always print confirmation messages after saving files.

---

## 6. Step 5 — SSE Streaming (FastAPI)

Right now the agent runs in a terminal. To build a real application, you need a web API
that streams progress in real time. When the agent takes 30 seconds to analyze data, the
user should see what is happening — not stare at a loading spinner.

### What is SSE?

**Server-Sent Events (SSE)** is a simple protocol for streaming data from server to client
over HTTP. Unlike WebSocket (which is bidirectional), SSE is one-way: the server pushes
events, the client listens. This is exactly what we need — the agent sends progress
updates, the client displays them.

SSE uses a plain HTTP response with `Content-Type: text/event-stream`. Each event is a
text block:

```
event: agent_thinking
data: {"content": "Let me check the campaign data..."}

event: tool_started
data: {"tool": "query_data", "args": {"sql": "SELECT ..."}}

event: token
data: {"content": "Your"}

event: token
data: {"content": " ROAS"}

event: done
data: {}
```

**Why SSE over WebSocket?** SSE is simpler — it works over regular HTTP, requires no
special server setup, and reconnection is built into the browser's `EventSource` API. For
an agent that sends updates and receives one message at a time, SSE is the right choice.

### models/schemas.py

```python
"""Request and response models for the API."""

from pydantic import BaseModel


class StreamRequest(BaseModel):
    """Request body for the /stream endpoint."""

    message: str                    # User's message
    thread_id: str | None = None   # Conversation ID (None = new conversation)


class StreamEvent(BaseModel):
    """A single SSE event sent to the client.

    Event types:
    - agent_thinking: The LLM is processing (content = partial reasoning)
    - tool_started: A tool call has started (tool = name, args = arguments)
    - tool_completed: A tool call finished (tool = name, result = summary)
    - token: A streaming token from the LLM's final response
    - done: The agent has finished (includes the full response)
    - error: Something went wrong
    """

    event: str
    data: dict
```

### streaming/sse.py

```python
"""Convert LangGraph stream events to SSE format."""

import json
from collections.abc import AsyncIterator

from langchain_core.messages import AIMessage, HumanMessage, ToolMessage
from langgraph.graph.graph import CompiledGraph


async def stream_agent(
    graph: CompiledGraph,
    message: str,
    thread_id: str,
) -> AsyncIterator[str]:
    """Stream agent execution as SSE events.

    LangGraph's `astream_events` emits fine-grained events for every step
    of the graph. We filter and convert them into a simpler event protocol
    for the frontend.

    Yields:
        SSE-formatted strings: "event: <type>\\ndata: <json>\\n\\n"
    """
    config = {"configurable": {"thread_id": thread_id}}
    input_data = {"messages": [HumanMessage(content=message)]}

    # astream_events gives us a stream of everything happening in the graph
    async for event in graph.astream_events(input_data, config=config, version="v2"):
        kind = event["event"]

        # LLM starts generating a response
        if kind == "on_chat_model_start":
            yield _sse("agent_thinking", {"status": "reasoning"})

        # LLM streams tokens (the partial response as it generates)
        elif kind == "on_chat_model_stream":
            chunk = event["data"]["chunk"]
            if hasattr(chunk, "content") and chunk.content:
                # Stream each token to the client for real-time display
                yield _sse("token", {"content": chunk.content})

        # LLM finished generating (check for tool calls)
        elif kind == "on_chat_model_end":
            message = event["data"]["output"]
            if hasattr(message, "tool_calls") and message.tool_calls:
                for tc in message.tool_calls:
                    yield _sse("tool_started", {
                        "tool": tc["name"],
                        "args": tc["args"],
                    })

        # A tool finished executing
        elif kind == "on_tool_end":
            yield _sse("tool_completed", {
                "tool": event["name"],
                "result": _truncate(str(event["data"].get("output", "")), max_len=500),
            })

    # Signal completion
    yield _sse("done", {})


def _sse(event_type: str, data: dict) -> str:
    """Format a single SSE event.

    SSE format:
        event: <type>
        data: <json>
        <blank line>
    """
    return f"event: {event_type}\ndata: {json.dumps(data)}\n\n"


def _truncate(text: str, max_len: int = 500) -> str:
    """Truncate text for SSE events (tool results can be very long)."""
    if len(text) <= max_len:
        return text
    return text[:max_len] + f"... ({len(text) - max_len} more chars)"
```

### api.py

```python
"""FastAPI application with SSE streaming endpoint."""

import uuid

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

from marketing_agent.graph.graph import build_graph
from marketing_agent.models.schemas import StreamRequest
from marketing_agent.streaming.sse import stream_agent

app = FastAPI(title="Marketing Analytics Agent")

# Allow CORS for local development (the test HTML page needs this)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict in production
    allow_methods=["*"],
    allow_headers=["*"],
)

# Build the graph once at startup
graph = build_graph()


@app.post("/stream")
async def stream(request: StreamRequest):
    """Stream agent responses as Server-Sent Events.

    Send a message, get back a stream of events showing the agent's progress:
    thinking, tool calls, tokens, and the final response.

    The thread_id enables multi-turn conversations. Omit it for a new conversation;
    include it to continue an existing one.
    """
    thread_id = request.thread_id or str(uuid.uuid4())

    return StreamingResponse(
        stream_agent(graph, request.message, thread_id),
        media_type="text/event-stream",
        headers={
            # Prevent proxy/CDN buffering — SSE needs unbuffered delivery
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Thread-Id": thread_id,  # Return the thread_id so the client can reuse it
        },
    )


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok"}
```

### Consuming SSE from a frontend

Here is a minimal HTML page that connects to the agent's SSE endpoint. Save this as
`test_client.html` in the project root:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Marketing Agent</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; }
        #messages { border: 1px solid #ddd; padding: 16px; min-height: 300px; margin-bottom: 16px;
                    max-height: 600px; overflow-y: auto; white-space: pre-wrap; }
        .tool-event { color: #666; font-size: 0.9em; }
        .agent-text { color: #1a1a2e; }
        .error { color: red; }
        input { width: 70%; padding: 8px; }
        button { padding: 8px 16px; }
    </style>
</head>
<body>
    <h1>Marketing Analytics Agent</h1>
    <div id="messages"></div>
    <input type="text" id="input" placeholder="Ask a question..." />
    <button onclick="send()">Send</button>

    <script>
        let threadId = null;
        const messagesDiv = document.getElementById('messages');

        async function send() {
            const input = document.getElementById('input');
            const message = input.value.trim();
            if (!message) return;

            // Show user message
            appendMessage('You: ' + message, 'user');
            input.value = '';

            // Stream the response using fetch (EventSource doesn't support POST)
            const response = await fetch('/stream', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ message, thread_id: threadId }),
            });

            // Save thread_id for follow-up messages
            threadId = response.headers.get('X-Thread-Id');

            // Read the SSE stream
            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let agentText = '';
            let buffer = '';

            while (true) {
                const { value, done } = await reader.read();
                if (done) break;

                buffer += decoder.decode(value, { stream: true });

                // Parse SSE events from the buffer
                const events = buffer.split('\n\n');
                buffer = events.pop(); // Keep incomplete event in buffer

                for (const event of events) {
                    const lines = event.split('\n');
                    let eventType = '';
                    let data = '';

                    for (const line of lines) {
                        if (line.startsWith('event: ')) eventType = line.slice(7);
                        if (line.startsWith('data: ')) data = line.slice(6);
                    }

                    if (!eventType || !data) continue;

                    const parsed = JSON.parse(data);

                    switch (eventType) {
                        case 'tool_started':
                            appendMessage(`  [Tool: ${parsed.tool}]`, 'tool-event');
                            break;
                        case 'tool_completed':
                            appendMessage(`  [Done: ${parsed.tool}]`, 'tool-event');
                            break;
                        case 'token':
                            agentText += parsed.content;
                            updateLastAgent(agentText);
                            break;
                        case 'done':
                            if (agentText) appendMessage('Agent: ' + agentText, 'agent-text');
                            agentText = '';
                            break;
                        case 'error':
                            appendMessage('Error: ' + JSON.stringify(parsed), 'error');
                            break;
                    }
                }
            }
        }

        function appendMessage(text, className) {
            const div = document.createElement('div');
            div.className = className;
            div.textContent = text;
            messagesDiv.appendChild(div);
            messagesDiv.scrollTop = messagesDiv.scrollHeight;
        }

        function updateLastAgent(text) {
            // Update the streaming text in-place
            let el = messagesDiv.querySelector('.streaming');
            if (!el) {
                el = document.createElement('div');
                el.className = 'agent-text streaming';
                messagesDiv.appendChild(el);
            }
            el.textContent = 'Agent: ' + text;
            messagesDiv.scrollTop = messagesDiv.scrollHeight;
        }

        // Allow Enter key to send
        document.getElementById('input').addEventListener('keypress', (e) => {
            if (e.key === 'Enter') send();
        });
    </script>
</body>
</html>
```

### Run the API

```bash
# Start everything
docker compose up -d

# Seed the database (if not done already)
uv run python -m marketing_agent.db.seed

# Start the API server
uv run uvicorn marketing_agent.api:app --reload --port 8000

# Open the test page in your browser
open test_client.html
# (Or serve it: python -m http.server 3000, then open http://localhost:3000/test_client.html)
```

### What You Built

- A FastAPI endpoint (`POST /stream`) that returns SSE events
- An SSE converter that transforms LangGraph events into a simple protocol
- Five event types: `agent_thinking`, `tool_started`, `tool_completed`, `token`, `done`
- A test HTML page that consumes the stream in real time

### Try It

1. Open the test page, ask "What was the total spend by platform last month?"
2. Watch the tool events appear in real time as the agent works
3. Ask a follow-up question — verify the thread_id maintains context
4. Open browser DevTools → Network tab → look at the SSE stream to see raw events

> **Common Mistake**: Using `EventSource` for POST requests. The browser's built-in
> `EventSource` API only supports GET. For POST (which we need to send the message body),
> use `fetch()` with `response.body.getReader()` as shown above.

---

## 7. Step 6 — Subagents

Sometimes one agent is not enough. If a user asks "Compare Google Ads vs Meta vs LinkedIn
Q1 performance", the agent needs to analyze three platforms. It could do this sequentially
(slow) or spawn three subagents that work in parallel (fast).

### The concept

A subagent is another graph instance — the same ReAct loop, but with a narrower focus.
The lead agent spawns subagents as tool calls. Each subagent gets its own system prompt
scoped to a specific task.

```
Lead Agent: "Compare Q1 across all platforms"
  │
  ├── Subagent A: "Analyze Google Ads Q1 performance" (writes google_q1.csv)
  ├── Subagent B: "Analyze Meta Q1 performance" (writes meta_q1.csv)
  └── Subagent C: "Analyze LinkedIn Q1 performance" (writes linkedin_q1.csv)
  │
  └── Lead reads all CSVs, generates comparison
```

The subagents share the sandbox filesystem. They each write their results as CSV files,
and the lead agent reads all of them to produce the comparison.

### Building a subagent graph

A subagent uses the same graph structure as the lead agent but with a restricted tool set
and a focused system prompt.

```python
# graph/subagent.py
"""Subagent graph builder — creates focused analysis agents."""

from langchain_core.messages import SystemMessage, HumanMessage
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver

from marketing_agent.models.state import AgentState
from marketing_agent.graph.nodes.lead_agent import _build_llm
from marketing_agent.graph.nodes.tool_executor import tool_executor
from marketing_agent.graph.nodes.router import router, TOOL_EXECUTOR

# Subagents get fewer tools — they don't need file I/O tools or subagent spawning
from marketing_agent.tools.query_data import query_data
from marketing_agent.tools.list_tables import list_tables
from marketing_agent.tools.describe_table import describe_table
from marketing_agent.tools.python_exec import python_exec


def build_subagent_graph():
    """Build a subagent graph with a focused tool set.

    Subagents have the same ReAct structure as the lead agent but with:
    - Fewer tools (no file I/O tools, no subagent spawning — prevents infinite recursion)
    - A system prompt that will be provided at invocation time
    """
    # Subagent uses the same LLM with a subset of tools
    subagent_tools = [list_tables, describe_table, query_data, python_exec]
    subagent_llm = _build_llm().bind_tools(subagent_tools)

    async def subagent_node(state: AgentState) -> dict:
        """The subagent's LLM node — same as lead_agent but with fewer tools."""
        messages = state["messages"]
        response = await subagent_llm.ainvoke(messages)
        return {"messages": [response]}

    graph = StateGraph(AgentState)
    graph.add_node("subagent", subagent_node)
    graph.add_node("tool_executor", tool_executor)
    graph.set_entry_point("subagent")

    graph.add_conditional_edges(
        "subagent",
        router,
        {TOOL_EXECUTOR: "tool_executor", "end": END},
    )
    graph.add_edge("tool_executor", "subagent")

    return graph.compile(checkpointer=MemorySaver())
```

### tools/research_agent.py

The lead agent uses this tool to spawn subagents.

```python
"""Tool: spawn a subagent for focused research tasks."""

import uuid
import asyncio

from langchain_core.tools import tool
from langchain_core.messages import SystemMessage, HumanMessage

from marketing_agent.graph.subagent import build_subagent_graph


@tool
async def research_agent(tasks: list[dict]) -> str:
    """Spawn one or more research subagents to work on focused analysis tasks.

    Each task runs as an independent subagent with its own ReAct loop. All
    subagents share the sandbox filesystem — they can write CSV files that
    you (the lead agent) can read afterward.

    Use this when you need to analyze multiple segments, platforms, or time
    periods independently. Each subagent works in parallel for speed.

    Each task dict has:
    - "prompt": The research question for the subagent
    - "output_file": Where the subagent should save its results (e.g., "google_q1.csv")

    EXAMPLE:
    research_agent(tasks=[
        {"prompt": "Analyze Google Ads Q1 2026 spend, clicks, and ROAS. Save to data/google_q1.csv",
         "output_file": "google_q1.csv"},
        {"prompt": "Analyze Meta Q1 2026 spend, clicks, and ROAS. Save to data/meta_q1.csv",
         "output_file": "meta_q1.csv"},
    ])

    After the subagents finish, use python_exec to read their output files
    and produce a combined analysis.

    Args:
        tasks: List of task dicts, each with "prompt" and "output_file" keys.
    """
    subagent_graph = build_subagent_graph()

    async def run_one(task: dict) -> str:
        """Run a single subagent to completion."""
        prompt = task["prompt"]
        output_file = task.get("output_file", "result.csv")
        thread_id = str(uuid.uuid4())

        # Build the subagent's system prompt
        system_prompt = f"""You are a research analyst subagent. Your job is to complete
ONE specific research task and save your results to a file.

YOUR TASK: {prompt}

INSTRUCTIONS:
1. Use list_tables and describe_table to understand the data
2. Use query_data to fetch the specific data needed
3. Use python_exec to process the data and save it to data/{output_file}
4. Your final response should summarize what you found and saved

IMPORTANT:
- Save structured data (CSV or JSON) to data/{output_file}
- The lead agent will read this file to combine results
- Be thorough but focused — only analyze what was asked
"""
        config = {"configurable": {"thread_id": thread_id}}
        result = await subagent_graph.ainvoke(
            {"messages": [
                SystemMessage(content=system_prompt),
                HumanMessage(content=prompt),
            ]},
            config=config,
        )

        # Return the last message (the subagent's summary)
        last_msg = result["messages"][-1]
        return f"[{output_file}] {last_msg.content}"

    # Run all subagents concurrently
    results = await asyncio.gather(*[run_one(task) for task in tasks])

    return "\n\n---\n\n".join(results)
```

### Add the research_agent tool

```python
# In graph/nodes/lead_agent.py — add import:
from marketing_agent.tools.research_agent import research_agent

# Add to tools list:
tools = [
    list_tables, describe_table, query_data, python_exec,
    research_agent,
]
```

```python
# In graph/nodes/tool_executor.py — add import and map entry:
from marketing_agent.tools.research_agent import research_agent

TOOL_MAP["research_agent"] = research_agent
```

### Walking through the parallel pattern

```
User: "Compare Google Ads vs Meta Q1 performance — spend, ROAS, and top campaigns"

Lead Agent thinks: This requires analyzing two platforms independently. I'll use
research_agent to run them in parallel.

Lead Agent calls: research_agent(tasks=[
    {
        "prompt": "Analyze Google Ads Q1 2026: total spend, ROAS trend by month,
                   and top 5 campaigns by ROAS. Save all data to data/google_q1.csv",
        "output_file": "google_q1.csv"
    },
    {
        "prompt": "Analyze Meta Q1 2026: total spend, ROAS trend by month,
                   and top 5 campaigns by ROAS. Save all data to data/meta_q1.csv",
        "output_file": "meta_q1.csv"
    }
])

  ┌─── Subagent A (Google): list_tables → query_data → python_exec (writes google_q1.csv)
  │    Returns: "Google Ads Q1: $145K spend, ROAS 3.2 avg, top campaign: search_001"
  │
  └─── Subagent B (Meta): list_tables → query_data → python_exec (writes meta_q1.csv)
       Returns: "Meta Q1: $98K spend, ROAS 2.1 avg, top campaign: retargeting_003"

  (Both run concurrently via asyncio.gather)

Lead Agent reads results, then calls python_exec:
  "Read data/google_q1.csv and data/meta_q1.csv, create a comparison table"

Lead Agent provides final answer:
  "Google Ads outperformed Meta in Q1: higher ROAS (3.2 vs 2.1), though Meta had
   lower CPC. Top performers: Google's search_001 (ROAS 4.8) and Meta's
   retargeting_003 (ROAS 3.5). Recommendation: ..."
```

### Foreground vs. background subagents

The implementation above is **foreground** — the lead agent waits for all subagents to
complete before continuing. This is the simpler and more common pattern.

A **background** pattern would let the lead agent continue working while subagents run
in the background, checking on their results later. This is useful for very long-running
tasks but adds significant complexity (polling, state management, error handling). Start
with foreground; add background only if you need it.

### What You Built

- A subagent graph builder (same ReAct structure, restricted tools)
- The `research_agent` tool that spawns parallel subagents
- Concurrent execution via `asyncio.gather`
- Shared state through the sandbox filesystem

### Try It

1. Ask "Compare all three platforms' performance in Q1 — I want spend, ROAS, CTR, and CPA"
2. Ask "Research the top 3 campaigns from each platform and compare them"
3. Try a complex request: "Generate a Q1 executive report with per-platform analysis and
   a comparison chart" — watch the agent coordinate subagents and visualization tools

> **Common Mistake**: Allowing subagents to spawn more subagents. This creates infinite
> recursion. The subagent's tool list deliberately excludes `research_agent`. Always
> restrict subagent capabilities to prevent this.

---

## 8. Step 7 — Skills (Prompt Templates)

Skills are structured workflows for common tasks. Instead of the agent figuring out how to
generate a weekly report from scratch every time, a skill provides step-by-step instructions.

### The problem skills solve

Without a skill, the agent must reason about the entire workflow:

```
User: "Generate a weekly performance report"
Agent: (thinks) What should go in a weekly report? What metrics? What format?
       Let me try... *makes inconsistent decisions each time*
```

With a skill:

```
User: "/weekly-report google-ads last 4 weeks"
Agent: (reads skill instructions) I need to: fetch weekly metrics, compare to prior
       period, flag anomalies, generate charts, build a PDF. Let me follow these steps.
       *produces consistent, high-quality output every time*
```

Skills do not add new capabilities — the tools are the same. Skills add **structured
guidance** that makes the agent more reliable and consistent.

### Skill file format

Each skill is a Markdown file with YAML frontmatter:

```
skills/
  weekly_report/
    SKILL.md
  campaign_analysis/
    SKILL.md
  investigate_drop/
    SKILL.md
```

### skills/weekly_report/SKILL.md

```markdown
---
name: weekly-report
description: Generate a weekly performance report for a platform or all platforms.
trigger: /weekly-report
args:
  - name: platform
    description: Platform to report on (google_ads, meta, linkedin, or "all")
    default: all
  - name: period
    description: Number of weeks to include
    default: "4"
---

# Weekly Performance Report

You are generating a structured weekly performance report. Follow these steps exactly.

## Step 1: Fetch Data

Query weekly metrics for the specified platform(s) over the requested period:

```sql
SELECT
    DATE_TRUNC('week', date) AS week,
    platform,
    SUM(impressions) AS impressions,
    SUM(clicks) AS clicks,
    SUM(conversions) AS conversions,
    ROUND(SUM(spend)::numeric, 2) AS spend,
    ROUND(SUM(revenue)::numeric, 2) AS revenue,
    ROUND(SUM(clicks)::numeric / NULLIF(SUM(impressions), 0) * 100, 2) AS ctr,
    ROUND(SUM(revenue)::numeric / NULLIF(SUM(spend), 0), 2) AS roas,
    ROUND(SUM(spend)::numeric / NULLIF(SUM(conversions), 0), 2) AS cpa
FROM daily_metrics
WHERE date >= CURRENT_DATE - INTERVAL '{period} weeks'
  {platform_filter}
GROUP BY week, platform
ORDER BY week DESC, platform
```

## Step 2: Compute Week-over-Week Changes

Use python_exec to calculate WoW changes for key metrics:
- Spend, clicks, conversions, revenue (absolute and percentage change)
- CTR, ROAS, CPA (percentage change)
- Flag any metric that changed more than 15% as an **anomaly**

Save the processed data to `data/weekly_report_data.csv`.

## Step 3: Generate Charts

Use `python_exec` to create these charts with matplotlib:
1. **Spend trend**: Line chart of weekly spend by platform
2. **ROAS trend**: Line chart of weekly ROAS by platform
3. **Conversion volume**: Bar chart of weekly conversions by platform

Save as `charts/weekly_spend.png`, `charts/weekly_roas.png`,
`charts/weekly_conversions.png`.

## Step 4: Generate Report

Use `python_exec` to create a PDF with weasyprint using this structure:

```markdown
# Weekly Performance Report
## Period: {date_range}

## Executive Summary
- Top-line numbers: total spend, total revenue, blended ROAS
- Key changes from prior week (biggest movers)
- Anomalies flagged (anything > 15% change)

## Platform Performance
### {Platform Name}
- Key metrics table (this week vs last week, with % change)
- Notable changes

![Spend Trend](charts/weekly_spend.png)
![ROAS Trend](charts/weekly_roas.png)
![Conversions](charts/weekly_conversions.png)

## Recommendations
- Based on the data, what should the team focus on?
- Any campaigns to pause, scale, or investigate?
```

## Output
Deliver the PDF report and summarize key findings in your chat response.
```

### skills/campaign_analysis/SKILL.md

```markdown
---
name: campaign-analysis
description: Deep analysis of a specific campaign or campaign type.
trigger: /campaign-analysis
args:
  - name: campaign
    description: Campaign name, ID, or type to analyze
    required: true
  - name: period
    description: Time period for analysis (e.g., "last 30 days", "Q1 2026")
    default: last 30 days
---

# Campaign Deep Analysis

You are performing a deep analysis of a specific campaign. Follow these steps.

## Step 1: Identify the Campaign

Search for the campaign using the provided name, ID, or type:

```sql
SELECT id, name, platform, campaign_type, status, daily_budget, start_date
FROM campaigns
WHERE name ILIKE '%{campaign}%' OR campaign_type ILIKE '%{campaign}%'
```

If multiple campaigns match, analyze all of them as a group.

## Step 2: Fetch Performance Metrics

Get daily metrics for the campaign over the specified period:
- Daily: impressions, clicks, conversions, spend, revenue
- Derived: CTR, CVR, CPC, CPA, ROAS

Save raw data to `data/campaign_daily.csv`.

## Step 3: Statistical Analysis

Use python_exec to compute:
- **Trend analysis**: Is performance improving, declining, or flat? (7-day moving average)
- **Day-of-week patterns**: Which days perform best/worst?
- **Spend efficiency**: Diminishing returns? (plot spend vs. conversions)
- **Audience performance**: Which ad groups / segments perform best?

Save analysis to `data/campaign_analysis.csv`.

## Step 4: Visualize

Create these charts:
1. **Daily performance**: Line chart of spend and revenue (dual axis)
2. **Efficiency curve**: Scatter plot of daily spend vs. ROAS
3. **Day-of-week heatmap**: Average performance by day

## Step 5: Synthesize

Provide:
- Performance summary (is this campaign healthy?)
- Key insights (what's working, what's not)
- Specific recommendations (scale, optimize, pause, restructure)
- Comparison to account averages where relevant
```

### skills/investigate_drop/SKILL.md

```markdown
---
name: investigate-drop
description: Investigate why a specific metric dropped.
trigger: /investigate-drop
args:
  - name: metric
    description: The metric that dropped (e.g., "ROAS", "CTR", "conversions")
    required: true
  - name: platform
    description: Platform where the drop occurred (or "all")
    default: all
  - name: period
    description: When the drop was noticed
    default: last 7 days
---

# Investigate Metric Drop

You are investigating why a specific metric dropped. Follow this diagnostic framework.

## Step 1: Confirm the Drop

Quantify the drop precisely:
- What is the current value vs. the prior period?
- How severe is the drop (percentage change)?
- Is this outside normal variation? (compare to 4-week average)

## Step 2: Isolate the Cause

Break down the metric by dimensions to find where the drop is concentrated:

1. **By platform**: Did all platforms drop or just one?
2. **By campaign type**: Search vs. display vs. retargeting?
3. **By campaign**: Which specific campaigns are affected?
4. **By ad group/audience**: Which targeting segments declined?
5. **By day**: Was it sudden (one day) or gradual (trend)?

Use query_data for each breakdown. Save results to `data/drop_investigation.csv`.

## Step 3: Identify Root Cause

Based on the isolation:
- **Spend increase without proportional conversions** → audience saturation
- **CTR drop** → ad fatigue or audience mismatch
- **CVR drop** → landing page issue or audience quality
- **CPC increase** → increased competition or quality score drop
- **Single campaign responsible** → campaign-specific issue
- **All campaigns affected** → market or seasonal change

## Step 4: Recommend Actions

Based on the root cause:
- Immediate actions (next 24-48 hours)
- Medium-term optimizations (next 1-2 weeks)
- Things to monitor going forward

## Output
Summarize your investigation in a structured format:
1. Confirmed drop: [metric] dropped [X]% from [A] to [B]
2. Root cause: [specific finding]
3. Evidence: [data points that support the diagnosis]
4. Recommended actions: [specific steps]
```

### Skill loader

```python
# prompts/system.py
"""System prompt construction — base prompt + optional skill injection."""

import re
from pathlib import Path

import yaml


SKILLS_DIR = Path(__file__).parent.parent / "skills"

# Base system prompt — always included
BASE_SYSTEM_PROMPT = """You are a marketing analytics assistant with access to a PostgreSQL
database containing campaign performance data across Google Ads, Meta, and LinkedIn.

{tools_section}

{skill_section}

{guardrails}
"""

TOOLS_SECTION = """## Available Tools

- **list_tables**: Discover what tables exist and their row counts. Start here.
- **describe_table**: See columns, types, and sample data for a table.
- **query_data**: Run read-only SQL queries. Use aggregations and LIMIT.
- **python_exec**: Execute Python in the sandbox (pandas, matplotlib, openpyxl, weasyprint, etc.). Always print() results. Use this for charts, Excel, PDF, file I/O, and all analysis. Use open(), os.listdir(), pd.read_csv() for file operations.
- **research_agent**: Spawn subagents for parallel research tasks.

## Data Schema Summary

Tables: campaigns, ad_groups, ads, daily_metrics, audience_segments
Key columns in daily_metrics: date, campaign_id, ad_group_id, platform,
impressions, clicks, conversions, spend, revenue

Derived metrics (calculate in SQL):
- CTR = clicks::float / NULLIF(impressions, 0)
- ROAS = revenue / NULLIF(spend, 0)
- CPC = spend / NULLIF(clicks, 0)
- CVR = conversions::float / NULLIF(clicks, 0)
- CPA = spend / NULLIF(conversions, 0)

## Sandbox-as-Memory Pattern

The sandbox filesystem persists between tool calls. Use it as scratch space:
1. query_data fetches data
2. python_exec saves processed data to CSV in data/
3. python_exec generates charts in charts/, exports in exports/
4. Files written by subagents are also in the sandbox — you can read them with python_exec
"""

GUARDRAILS = """## Rules

- ONLY execute SELECT queries. Never INSERT, UPDATE, DELETE, DROP, or ALTER.
- NEVER hallucinate data. If a query returns no results, say so.
- Always verify table/column names with list_tables and describe_table before querying.
- Round percentages to 1 decimal place, currency to 2 decimal places.
- When showing data, prefer tables (Markdown format) over prose.
- If uncertain about a metric definition, ask the user to clarify.
"""


def load_skill(skill_name: str, args: dict[str, str] | None = None) -> str | None:
    """Load a skill's SKILL.md and return the instruction content.

    Parses YAML frontmatter for metadata, then returns the Markdown body
    with any argument placeholders filled in.

    Args:
        skill_name: The skill directory name (e.g., "weekly_report").
        args: Optional arguments to substitute into the skill template.

    Returns:
        The skill instructions as a string, or None if not found.
    """
    skill_path = SKILLS_DIR / skill_name / "SKILL.md"
    if not skill_path.exists():
        return None

    content = skill_path.read_text()

    # Split frontmatter from body
    match = re.match(r"^---\n(.*?)\n---\n(.*)", content, re.DOTALL)
    if not match:
        return content  # No frontmatter, return as-is

    frontmatter_str, body = match.groups()
    frontmatter = yaml.safe_load(frontmatter_str)

    # Fill in argument placeholders
    if args:
        for key, value in args.items():
            body = body.replace(f"{{{key}}}", value)

    # Fill in defaults for any remaining placeholders
    if "args" in frontmatter:
        for arg_def in frontmatter["args"]:
            placeholder = f"{{{arg_def['name']}}}"
            if placeholder in body and "default" in arg_def:
                body = body.replace(placeholder, str(arg_def["default"]))

    return body


def build_system_prompt(skill_name: str | None = None, skill_args: dict | None = None) -> str:
    """Construct the full system prompt, optionally with a skill injected.

    Args:
        skill_name: If provided, load and inject this skill's instructions.
        skill_args: Arguments to pass to the skill template.

    Returns:
        The complete system prompt string.
    """
    skill_section = ""
    if skill_name:
        skill_content = load_skill(skill_name, skill_args)
        if skill_content:
            skill_section = f"## Active Skill: {skill_name}\n\n{skill_content}"

    return BASE_SYSTEM_PROMPT.format(
        tools_section=TOOLS_SECTION,
        skill_section=skill_section,
        guardrails=GUARDRAILS,
    )
```

### How a user triggers a skill

Update `main.py` to detect skill triggers:

```python
# In main.py — update the input handling:

import re
from marketing_agent.prompts.system import build_system_prompt

# Parse skill invocation: /skill-name arg1 arg2 ...
SKILL_PATTERN = re.compile(r"^/(\S+)\s*(.*)")

# In the while loop, before calling graph.ainvoke:
skill_match = SKILL_PATTERN.match(user_input)
if skill_match:
    skill_name = skill_match.group(1).replace("-", "_")
    skill_raw_args = skill_match.group(2).strip()

    # Parse positional args (simple: split by space)
    # A more robust implementation would use argparse
    args_list = skill_raw_args.split() if skill_raw_args else []

    # Map positional args to skill argument names
    # (In a real implementation, you'd read the skill's frontmatter to know arg names)
    skill_args = {}
    if args_list:
        skill_args["platform"] = args_list[0]
    if len(args_list) > 1:
        skill_args["period"] = " ".join(args_list[1:])

    # Build system prompt with skill injected
    system_prompt = build_system_prompt(skill_name, skill_args)

    # Prepend skill context to the user's message
    user_input = f"[Skill: {skill_name}] {skill_raw_args or 'Execute the skill with defaults.'}"
```

### How skills modify agent behavior

**Without skill** (generic prompt):
```
User: Generate a weekly report
Agent: (thinking) What should go in a weekly report? Let me figure it out...
  - Queries random metrics
  - Might miss important comparisons
  - Inconsistent format each time
  - May forget to generate charts
```

**With skill** (structured instructions):
```
User: /weekly-report google_ads 4
Agent: (reads skill instructions) I have a 4-step plan:
  Step 1: Fetch weekly metrics (the skill gives me the exact SQL template)
  Step 2: Compute WoW changes (the skill tells me to flag >15% changes)
  Step 3: Generate 3 specific charts
  Step 4: Build a PDF with a defined structure
  - Follows the plan reliably
  - Consistent output every time
  - No missing sections
```

### What You Built

- A skill loader that reads SKILL.md files with YAML frontmatter
- Three example skills: weekly-report, campaign-analysis, investigate-drop
- Argument substitution in skill templates
- Skill-aware system prompt construction
- Slash-command trigger syntax (`/weekly-report google_ads 4`)

### Try It

1. Run `/weekly-report all 4` — watch the agent follow the structured steps
2. Run `/campaign-analysis search` — see it perform a deep campaign analysis
3. Run `/investigate-drop ROAS meta last 7 days` — see the diagnostic framework in action
4. Compare: ask "generate a weekly report" without the slash command — notice the difference

> **Common Mistake**: Putting implementation logic in skills. Skills should contain
> instructions (tell the agent what to do), not code (do it for the agent). The agent
> still uses tools — the skill just structures its decision-making.

---

## 9. Step 8 — System Prompt Engineering

The system prompt is the most important piece of the entire agent. It determines how the
LLM uses tools, formats responses, handles edge cases, and produces reliable output.
Every section exists because of a real failure we observed during testing.

### The complete system prompt

This is the full production system prompt with annotations explaining each section.

```python
# prompts/system.py — replace the BASE_SYSTEM_PROMPT and sections with this:

PRODUCTION_SYSTEM_PROMPT = """You are a senior marketing analytics assistant. You help
marketing teams analyze campaign performance, identify trends, diagnose problems, and
generate reports using real data from a PostgreSQL database.

You have access to campaign data from three platforms: Google Ads, Meta, and LinkedIn.
The data includes campaigns, ad groups, individual ads, and daily performance metrics
spanning 6 months.

## Your Capabilities

1. **Data Querying**: Run SQL queries against the marketing database (read-only)
2. **Data Analysis**: Execute Python code (pandas, scipy, numpy) in a sandboxed environment
3. **Visualization**: Generate charts via python_exec (matplotlib, seaborn, plotly)
4. **Export**: Create Excel workbooks (openpyxl) and PDF reports (weasyprint) via python_exec
5. **Parallel Research**: Delegate sub-tasks to research agents for concurrent analysis

## Available Tools

### Data Access
- **list_tables()**: Discover available tables and row counts. ALWAYS call this first
  when you haven't seen the schema yet.
- **describe_table(table_name)**: Get column names, types, and sample rows.
  Call this before writing queries to avoid column name mistakes.
- **query_data(sql)**: Execute read-only SQL. Returns formatted text results (max 200 rows).

### Computation
- **python_exec(code)**: Run Python in the sandbox. Pre-installed: pandas, numpy, scipy,
  matplotlib, seaborn, openpyxl, plotly, weasyprint, jinja2.
  Use this for EVERYTHING: analysis, charts, Excel, PDF.
  ALWAYS use print() to return results — stdout is all the agent sees.

### Parallel Work
- **research_agent(tasks)**: Spawn focused subagents for parallel analysis.
  Use for multi-platform comparisons or multi-campaign analysis.

## Database Schema

### Tables
- **campaigns**: id, name, platform, campaign_type, status, daily_budget, start_date, end_date
- **ad_groups**: id, campaign_id, name, targeting_type, audience_segment, status
- **ads**: id, ad_group_id, name, headline, description, creative_type, status
- **daily_metrics**: id, campaign_id, ad_group_id, ad_id, date, impressions, clicks,
  conversions, spend, revenue, platform
- **audience_segments**: id, name, description, platform, estimated_size

### Platform Values
- platform: 'google_ads', 'meta', 'linkedin'

### Key Derived Metrics (calculate in SQL or Python)
- **CTR** (Click-Through Rate) = clicks::float / NULLIF(impressions, 0)
- **CVR** (Conversion Rate) = conversions::float / NULLIF(clicks, 0)
- **CPC** (Cost Per Click) = spend / NULLIF(clicks, 0)
- **CPA** (Cost Per Acquisition) = spend / NULLIF(conversions, 0)
- **ROAS** (Return On Ad Spend) = revenue / NULLIF(spend, 0)
- Always use NULLIF to prevent division by zero.
- Always ROUND() results for readability.

## Working with the Sandbox

The sandbox filesystem is your persistent scratch space across tool calls:

1. **Save intermediate data**: After querying, use python_exec to save CSVs
   ```python
   # In python_exec:
   import pandas as pd
   # ... process data ...
   df.to_csv('data/processed.csv', index=False)
   print(f"Saved {len(df)} rows to data/processed.csv")
   ```

2. **Build on previous results**: Charts and exports read from the sandbox
   ```python
   df = pd.read_csv('data/processed.csv')
   ```

3. **Subagent coordination**: Subagents write to the sandbox too. After research_agent
   completes, read the output files with python_exec.

## Response Formatting

- **Tables**: Use Markdown tables for structured data. Align numbers right.
- **Metrics**: Always include the metric name and value: "CTR: 3.2%", not just "3.2%"
- **Comparisons**: Show absolute change AND percentage: "Spend: $12K → $18.5K (+54%)"
- **Currency**: Use $ prefix, comma separators, 2 decimals: "$12,345.67"
- **Percentages**: 1 decimal place: "3.2%", not "3.24158%"
- **Large numbers**: Use K/M suffixes for readability: "$12.3K", "$1.2M"
- **Time periods**: Be explicit: "Week of March 24, 2026", not "last week"

## Guardrails

1. **Read-only queries only.** Never INSERT, UPDATE, DELETE, DROP, ALTER, or TRUNCATE.
2. **Never hallucinate data.** If a query returns no results, say "No data found for..."
   Do not make up numbers.
3. **Verify before querying.** Always check table/column names with list_tables and
   describe_table before writing SQL. Column name mistakes waste a tool call.
4. **Explain your reasoning.** When you find something interesting in the data, explain
   WHY it matters for marketing decisions, not just WHAT the numbers are.
5. **Acknowledge uncertainty.** If the data is ambiguous or incomplete, say so. Don't
   over-interpret small sample sizes or single-day anomalies.
6. **Stay in scope.** You analyze marketing data. If asked about unrelated topics,
   politely redirect to marketing analytics.

{skill_section}
"""
```

### Why each section matters

| Section | What it does | What goes wrong without it |
|---------|-------------|--------------------------|
| Role definition | Sets the persona and expertise level | Agent gives generic answers, not marketing-specific |
| Capabilities list | Tells the LLM what it can do | Agent tries things it can't do, or doesn't use tools it has |
| Tool descriptions | Explains when and how to use each tool | Agent misuses tools or calls them in wrong order |
| Database schema | Lists tables and columns | Agent hallucinates column names, wastes tool calls on schema discovery |
| Derived metrics | Defines CTR, ROAS, CPA formulas | Agent calculates metrics wrong or inconsistently |
| Sandbox pattern | Explains the file persistence model | Agent tries to pass data between tools through messages (fails for large datasets) |
| Response formatting | Specifies number formats, table styles | Inconsistent formatting, hard-to-read numbers |
| Guardrails | Prevents harmful or misleading behavior | Agent runs write queries, makes up data, or goes off-topic |

### Dynamic prompt assembly

The system prompt is assembled at runtime from three pieces:

```
Final prompt = Base prompt + Skill instructions (if active) + Dynamic context

Base prompt:     Always included. Role, tools, schema, guardrails.
Skill section:   Only when a skill is triggered. Step-by-step instructions.
Dynamic context: Date, user preferences, recent conversation summary (future enhancement).
```

### What You Built

- A comprehensive system prompt covering role, tools, schema, patterns, formatting, and guardrails
- Understanding of why each section exists (tracing back to observed failures)
- Dynamic assembly with skill injection

### Try It

1. Ask the agent a question, then modify the system prompt — remove the guardrails section.
   Ask "Delete the campaigns table." See what happens.
2. Remove the "Database Schema" section. Ask "What's the total spend by platform?" Watch
   the agent need extra tool calls to discover the schema.
3. Add a new guardrail: "Always end your response with a confidence score (1-10)." See how
   the agent adapts.

> **Common Mistake**: Writing the system prompt once and never iterating. The system prompt
> is prompt engineering — it needs testing and refinement like any code. Every time the agent
> produces bad output, ask: "What instruction in the system prompt would have prevented this?"

---

## 10. Testing

Testing an agent system has unique challenges. The LLM is non-deterministic — the same input
can produce different tool call sequences and different text. You cannot test for exact
output. Instead, test the boundaries: tools, routing, and integration.

### Strategy

| Component | What to test | How to test |
|-----------|-------------|-------------|
| Tools | SQL validation, output format, error handling | Unit tests with mock DB |
| Router | Correct routing based on message type | Unit tests with synthetic messages |
| Graph | Correct flow (LLM → tools → LLM → END) | Integration test with mock LLM |
| API | SSE format, request handling | HTTP test with `httpx.AsyncClient(app=)` |
| End-to-end | Full agent produces reasonable output | Integration test with real LLM + test DB |

### tests/conftest.py

```python
"""Shared test fixtures.

Tests must pass without a .env file. This fixture provides defaults
for all required environment variables.
"""

import os
import pytest


@pytest.fixture(autouse=True)
def env_defaults(monkeypatch):
    """Set environment variable defaults for tests."""
    defaults = {
        "ANTHROPIC_API_KEY": "test-key-not-real",
        "OPENAI_API_KEY": "test-key-not-real",
        "LLM_MODEL": "claude-sonnet-4-20250514",
        "DATABASE_URL": "postgresql+asyncpg://test:test@localhost:5432/test",
        "SANDBOX_URL": "http://localhost:8100",
    }
    for key, value in defaults.items():
        if key not in os.environ:
            monkeypatch.setenv(key, value)
```

### Test 1: SQL validation in query_data

```python
# tests/test_query_data.py
"""Test the SQL validation logic in the query_data tool."""

import pytest

from marketing_agent.tools.query_data import _validate_sql


@pytest.mark.parametrize(
    "sql, expected_error",
    [
        # Valid queries
        ("SELECT * FROM campaigns", None),
        ("SELECT COUNT(*) FROM daily_metrics WHERE platform = 'google_ads'", None),
        ("WITH cte AS (SELECT 1) SELECT * FROM cte", None),
        ("  SELECT id FROM campaigns  ", None),  # leading/trailing whitespace

        # Invalid queries
        ("INSERT INTO campaigns VALUES (1, 'test')", "Only SELECT queries are allowed"),
        ("DELETE FROM campaigns WHERE id = 1", "Only SELECT queries are allowed"),
        ("DROP TABLE campaigns", "Only SELECT queries are allowed"),
        ("UPDATE campaigns SET status = 'paused'", "Only SELECT queries are allowed"),
        ("SELECT 1; DROP TABLE campaigns", "Write operations are not allowed"),
        ("ALTER TABLE campaigns ADD COLUMN foo TEXT", "Only SELECT queries are allowed"),
    ],
    ids=[
        "simple_select",
        "select_with_where",
        "cte_query",
        "whitespace",
        "insert",
        "delete",
        "drop",
        "update",
        "injection_attempt",
        "alter",
    ],
)
def test_sql_validation(sql: str, expected_error: str | None):
    """Verify that _validate_sql correctly allows reads and blocks writes."""
    result = _validate_sql(sql)

    if expected_error is None:
        assert result is None, f"Expected valid SQL but got error: {result}"
    else:
        assert result is not None, "Expected error but SQL was accepted"
        assert expected_error in result
```

### Test 2: Router logic

```python
# tests/test_router.py
"""Test the graph router — correct routing based on message content."""

import pytest

from langchain_core.messages import AIMessage, HumanMessage

from marketing_agent.graph.nodes.router import router, TOOL_EXECUTOR, END


@pytest.mark.parametrize(
    "last_message, expected_route",
    [
        # AIMessage with tool_calls → route to tool executor
        (
            AIMessage(
                content="",
                tool_calls=[{"name": "query_data", "args": {"sql": "SELECT 1"}, "id": "call_1"}],
            ),
            TOOL_EXECUTOR,
        ),
        # AIMessage with text content (no tool_calls) → route to END
        (
            AIMessage(content="Here are your results..."),
            END,
        ),
        # AIMessage with empty tool_calls list → route to END
        (
            AIMessage(content="Done", tool_calls=[]),
            END,
        ),
    ],
    ids=["with_tool_calls", "text_response", "empty_tool_calls"],
)
def test_router(last_message, expected_route):
    """Verify router sends tool calls to executor and final answers to END."""
    state = {"messages": [HumanMessage(content="test"), last_message]}
    assert router(state) == expected_route
```

### Test 3: SSE event format

```python
# tests/test_sse.py
"""Test SSE event formatting."""

import json

from marketing_agent.streaming.sse import _sse, _truncate


class TestSseFormat:
    def test_sse_format(self):
        """SSE events must follow the event/data/blank-line format."""
        result = _sse("tool_started", {"tool": "query_data"})
        lines = result.split("\n")

        assert lines[0] == "event: tool_started"
        assert lines[1].startswith("data: ")
        assert lines[2] == ""  # blank line separator

        # Data must be valid JSON
        data = json.loads(lines[1].removeprefix("data: "))
        assert data["tool"] == "query_data"

    def test_sse_done_event(self):
        """The done event should have empty data."""
        result = _sse("done", {})
        assert "event: done" in result
        assert "data: {}" in result


class TestTruncate:
    def test_short_text_unchanged(self):
        assert _truncate("hello", max_len=10) == "hello"

    def test_long_text_truncated(self):
        result = _truncate("a" * 1000, max_len=100)
        assert len(result) < 1000
        assert "900 more chars" in result
```

### Running tests

```bash
# Run all tests
uv run pytest

# Run with verbose output
uv run pytest -v

# Run a specific test file
uv run pytest tests/test_query_data.py

# Run tests matching a pattern
uv run pytest -k "router"
```

### Testing philosophy for agents

**Test the tools thoroughly** — tools are deterministic (given the same input, they produce
the same output). SQL validation, output formatting, error handling — these are all testable.

**Test the graph flow** — verify that the router sends tool calls to the executor and text
responses to END. Use synthetic messages (not real LLM calls) to test routing logic.

**Trust the LLM** — do not try to test that the LLM produces specific text. Instead, test
that the system handles whatever the LLM produces: tool calls get executed, errors get
caught, results get formatted. The LLM is a black box — test the box it's in.

### What You Built

- Test fixtures that work without a .env file
- Parametrized tests for SQL validation (10 cases in one test function)
- Router logic tests with synthetic messages
- SSE format tests
- A testing strategy tailored to agent systems

---

## 11. Running the Complete Agent

You have built every piece. Here is how to run the complete system end to end.

### Start the infrastructure

```bash
cd marketing-agent

# Start PostgreSQL + sandbox
docker compose up -d --build

# Verify both are healthy
docker compose ps
# Both should show "healthy" or "running"

# Verify sandbox
curl http://localhost:8100/health
# {"status":"ok"}
```

### Seed the database

```bash
uv run python -m marketing_agent.db.seed
# Should print: "Seeded 11 campaigns, 28 ad groups, 70 ads"
```

### Start the API server

```bash
uv run uvicorn marketing_agent.api:app --reload --port 8000
```

### Example interactions

**Simple query:**
```
POST /stream
{"message": "What's the total spend by platform this quarter?"}
```

**Chart generation:**
```
POST /stream
{"message": "Show me a line chart of weekly ROAS trends by platform for Q1"}
```

**Skill invocation:**
```
POST /stream
{"message": "/weekly-report google_ads 4"}
```

**Complex multi-platform analysis:**
```
POST /stream
{"message": "Compare Google Ads vs Meta Q1 performance. I want spend, ROAS, CTR, and the top 3 campaigns from each. Include charts and export as a PDF report."}
```

For this last request, the agent will typically:
1. Spawn subagents via `research_agent` for parallel platform analysis
2. Use `python_exec` to combine and compare results
3. Use `python_exec` to generate comparison charts with matplotlib
4. Use `python_exec` to create a PDF with weasyprint embedding the charts
5. Return a summary in chat

### CLI mode (for quick testing)

```bash
uv run python -m marketing_agent.main
```

### Common issues and debugging

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| `ConnectionRefusedError` on DB | PostgreSQL not running | `docker compose up -d postgres` |
| `ConnectionRefusedError` on sandbox | Sandbox container not running | `docker compose up -d sandbox` |
| `AuthenticationError` from LLM | Invalid API key | Check `.env` — `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` |
| Agent says "No tables found" | Database not seeded | Run `uv run python -m marketing_agent.db.seed` |
| `python_exec` returns "no output" | Missing `print()` in sandbox code | Agent needs to learn to use `print()` — improve system prompt |
| Sandbox timeout | Code too slow or infinite loop | Check the code, increase timeout, add resource limits |
| LLM hallucinates column names | Missing `describe_table` step | System prompt should instruct "always check schema first" |
| SSE events not appearing | Proxy buffering | Add `Cache-Control: no-cache` header (already in api.py) |

### Debugging tool calls

Add logging to see what the agent is doing:

```python
# In graph/nodes/tool_executor.py — add at the top of tool_executor():
import logging
logger = logging.getLogger("marketing_agent")

async def tool_executor(state: AgentState) -> dict:
    last_message = state["messages"][-1]
    for tc in last_message.tool_calls:
        logger.info(f"Tool call: {tc['name']}({tc['args']})")
    # ... rest of the function
```

```bash
# Run with debug logging
LOG_LEVEL=DEBUG uv run uvicorn marketing_agent.api:app --reload --port 8000
```

---

## What You Built (Complete Summary)

Over 8 steps, you built a production-grade marketing analytics agent:

| Step | What was added | Key concepts |
|------|---------------|-------------|
| 1 | Simplest agent (LLM only) | State, graph, checkpointing |
| 2 | Database tools + ReAct loop | Tools, router, message flow |
| 3 | Python sandbox | Code execution, sandbox-as-memory |
| 4 | Smart agent philosophy | Smart agent, simple tools, python_exec for everything |
| 5 | SSE streaming API | FastAPI, real-time progress |
| 6 | Subagents | Parallel execution, shared filesystem |
| 7 | Skills (prompt templates) | Structured workflows, YAML frontmatter |
| 8 | System prompt engineering | Role, schema, guardrails, formatting |

The complete tool chain:

```
User message
  → FastAPI SSE endpoint
    → LangGraph ReAct loop
      → LLM (Claude/GPT) decides what to do
        → Tools: query_data, list_tables, describe_table, python_exec
        → Subagents: parallel research with shared sandbox
        → Skills: structured step-by-step workflows
      → LLM synthesizes results
    → SSE events streamed to client
  → Final response + downloadable files (charts, Excel, PDF)
```

Every piece is modular. You can swap the LLM (change one line in config), add new tools
(add a function + register it), create new skills (add a SKILL.md file), or change the
database schema (update the seed script). The architecture grows with your needs.
