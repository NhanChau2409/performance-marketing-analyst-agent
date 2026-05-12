# Tools Reference — Marketing Analytics Agent

This is the complete reference for every tool in the marketing analytics agent. You have
read the [LangGraph Guide](03-langgraph-guide.md) (concepts) and the
[Implementation Guide](04-implementation-guide.md) (step-by-step build). Now you need to
understand each tool deeply: what it does, why it exists, how it works internally, and
how the LLM uses it.

**Why a separate tools reference?** Tools are the agent's hands. The LLM can reason all
day, but it cannot do anything useful without tools. Understanding tool design is one of
the most important skills in AI engineering because:

1. The tool's **description** determines when and how the LLM calls it (this is prompt engineering)
2. The tool's **return value** determines what the LLM knows afterward (this is context management)
3. The tool's **error messages** determine whether the LLM can self-correct (this is UX design)

Every design decision in this reference comes back to one question: **how does this help
the LLM make better decisions?**

---

## How to Read This Reference

Each tool follows the same structure:

- **Purpose** — what it does in one sentence
- **Why This Tool Exists** — design rationale (why not merge it into another tool?)
- **Parameters** — full parameter table
- **Returns** — what the LLM sees back (not raw data!)
- **Implementation** — complete code with comments explaining every decision
- **Example Usage** — realistic scenarios showing LLM input, internal behavior, and LLM output
- **Common Mistakes** — what goes wrong and how to fix it
- **Design Decisions** — teaching section on the "why" behind the design

---

## 1. list_tables

### Purpose

List all tables in the marketing database with their column names, types, and row counts.

### Why This Tool Exists

The LLM does not know what tables exist. If you give it `query_data` without `list_tables`,
it will guess table names — and guess wrong. `list_tables` is the starting point of every
data workflow because it answers the most basic question: "What data do I have?"

This is a **schema discovery** tool. It exists separately from `describe_table` because
discovery happens in two stages: first you learn what tables exist (broad), then you learn
what columns a specific table has (deep). Combining them into one tool would dump too much
information at once — the LLM's context window is finite, and irrelevant column details
for tables you will never query waste that space.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| *(none)* | — | — | This tool takes no parameters. It always lists all public tables. |

### Returns

A formatted text string listing each table name and its approximate row count:

```
Available tables:
  - campaigns: 156 rows
  - daily_metrics: 14,208 rows
  - platforms: 3 rows
  - ad_groups: 892 rows
```

### Implementation

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
    # We use pg_tables (PostgreSQL system catalog) to discover tables.
    # Filtering to 'public' schema excludes internal PostgreSQL tables.
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

        # For each table, get the row count. This helps the LLM understand
        # data volume — a table with 3 rows is a lookup table, a table with
        # 14,000 rows is the main data source.
        lines = ["Available tables:"]
        for table in tables:
            count_result = await session.execute(
                text(f"SELECT COUNT(*) FROM {table}")  # noqa: S608
            )
            count = count_result.scalar()
            lines.append(f"  - {table}: {count:,} rows")

        return "\n".join(lines)
```

### Example Usage

**Example 1: Starting a new analysis**

The user asks: "What was our ROAS last quarter?"

The LLM does not know the schema, so its first action is:

```
LLM calls: list_tables()

LLM sees back:
  "Available tables:
    - campaigns: 156 rows
    - daily_metrics: 14,208 rows
    - platforms: 3 rows
    - ad_groups: 892 rows"

LLM thinks: "daily_metrics looks like the right table for ROAS data — it has the most
rows and sounds like time-series metrics. Let me use describe_table to see its columns."
```

**Example 2: Verifying assumptions**

The user asks: "Show me LinkedIn campaign performance." The LLM might assume there is a
`linkedin_campaigns` table. By calling `list_tables` first, it discovers there is no such
table — there is only `campaigns` with a `platform` column. This prevents a SQL error.

### Common Mistakes

| Mistake | What Happens | Fix |
|---------|-------------|-----|
| Skipping `list_tables` and guessing table names | `query_data` returns "SQL ERROR: relation 'campaign_metrics' does not exist" | Always call `list_tables` first in a new session |
| Calling `list_tables` repeatedly in the same session | Wastes a tool call — the schema does not change between calls | Call it once, then remember the results |

### Design Decisions

**Why no parameters?** The marketing database is small enough (3-10 tables) that listing
all tables is always reasonable. If you had 500 tables, you would add a `schema` or
`filter` parameter. Design for your actual use case, not hypothetical scale.

**Why include row counts?** They help the LLM make two decisions: (1) which table is the
"main" data table (the one with the most rows), and (2) whether a full `SELECT *` is
reasonable (3 rows = yes, 14,000 rows = use LIMIT). Row counts are cheap metadata that
prevent expensive mistakes.

> **Think About It**: What would happen if `list_tables` also returned all column names
> and types for every table? The response would be much longer. For a database with 10
> tables averaging 15 columns each, that is 150 lines of schema info — most of which the
> LLM will never use. The two-step pattern (`list_tables` then `describe_table`) is more
> token-efficient. This is **progressive disclosure** applied to LLM context management.

---

## 2. describe_table

### Purpose

Show a table's columns, data types, nullability, and sample rows so the LLM can write
correct SQL queries.

### Why This Tool Exists

Knowing that `daily_metrics` exists (from `list_tables`) is not enough to query it. The
LLM needs to know: What are the column names? What types are they? What do actual values
look like? Without this, the LLM will guess column names like `ad_spend` when the actual
column is `spend`, or use string operations on a numeric column.

Sample rows are critical. They show the LLM what the data actually looks like — the format
of dates, the range of numeric values, the exact strings used for categorical fields (is it
"Google Ads" or "google_ads"?). This prevents an entire class of bugs.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_name` | `str` | Yes | The name of the table to describe (e.g., `"campaigns"`, `"daily_metrics"`). |

### Returns

A formatted text block with three sections: column definitions, sample rows, and value
distributions for categorical columns:

```
Table: daily_metrics

Columns:
  - id: integer (NOT NULL)
  - date: date (NOT NULL)
  - campaign_id: integer (NOT NULL)
  - platform: character varying (NOT NULL)
  - impressions: integer (NOT NULL)
  - clicks: integer (NOT NULL)
  - conversions: integer (NOT NULL)
  - spend: numeric (NOT NULL)
  - revenue: numeric (NOT NULL)

Sample rows (first 3):
  id | date | campaign_id | platform | impressions | clicks | conversions | spend | revenue
  ------------------------------------------------------------------------------------------
  1 | 2026-01-01 | 42 | google_ads | 15234 | 423 | 28 | 312.50 | 980.00
  2 | 2026-01-01 | 42 | meta | 8921 | 312 | 19 | 245.80 | 520.00
  3 | 2026-01-01 | 15 | linkedin | 3201 | 89 | 5 | 178.20 | 310.00
```

### Implementation

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
        # Step 1: Get column metadata from information_schema.
        # This is the standard SQL way to introspect table structure.
        cols_result = await session.execute(text("""
            SELECT column_name, data_type, is_nullable
            FROM information_schema.columns
            WHERE table_name = :table AND table_schema = 'public'
            ORDER BY ordinal_position
        """), {"table": table_name})
        columns = cols_result.fetchall()

        # If no columns found, the table doesn't exist. Return an error
        # message that tells the LLM what to do next — not just "not found".
        if not columns:
            return f"Table '{table_name}' not found. Use list_tables to see available tables."

        lines = [f"Table: {table_name}", "", "Columns:"]
        for col_name, data_type, nullable in columns:
            null_str = "NULL" if nullable == "YES" else "NOT NULL"
            lines.append(f"  - {col_name}: {data_type} ({null_str})")

        # Step 2: Show sample rows. These are worth their weight in gold —
        # they show the LLM actual data formats, value ranges, and string
        # conventions. 3 rows is enough to establish patterns without
        # consuming too many context tokens.
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

### Example Usage

**Example 1: Learning column names before querying**

```
LLM calls: describe_table(table_name="daily_metrics")

LLM sees back:
  "Table: daily_metrics
   Columns:
     - id: integer (NOT NULL)
     - date: date (NOT NULL)
     - platform: character varying (NOT NULL)
     - spend: numeric (NOT NULL)
     - revenue: numeric (NOT NULL)
   ...
   Sample rows (first 3):
     ... | platform | ... | spend | revenue
     ... | google_ads | ... | 312.50 | 980.00"

LLM thinks: "The platform column uses snake_case values like 'google_ads', not
'Google Ads'. I'll use that in my WHERE clause. Revenue and spend are numeric,
so I can calculate ROAS = revenue / spend directly."
```

**Example 2: Handling a bad table name**

```
LLM calls: describe_table(table_name="campaign_metrics")

LLM sees back:
  "Table 'campaign_metrics' not found. Use list_tables to see available tables."

LLM thinks: "That table doesn't exist. Let me call list_tables to find the right name."
```

The error message is an instruction — it tells the LLM exactly what to do next.

**Example 3: Understanding value distributions**

After seeing sample rows where `platform` values are `google_ads`, `meta`, and `linkedin`,
the LLM knows the exact string values to use in WHERE clauses. Without this, it might
try `WHERE platform = 'Google Ads'` and get zero rows.

### Common Mistakes

| Mistake | What Happens | Fix |
|---------|-------------|-----|
| Calling with a misspelled table name | Returns "not found" error | Copy-paste table names from `list_tables` output |
| Not reading sample rows carefully | LLM uses wrong string values in WHERE clauses | Sample rows show exact value formats — read them |
| Calling `describe_table` for every table before querying | Wastes context tokens | Only describe tables you actually need to query |

### Design Decisions

**Why only 3 sample rows?** More rows would consume LLM context tokens for diminishing
returns. 3 rows are enough to show data types, value formats, and string conventions. If
the LLM needs to see the full range of values in a categorical column, it can use
`query_data` with `SELECT DISTINCT platform FROM daily_metrics`.

**Why return text, not structured JSON?** LLMs read text more naturally than they parse
JSON. A formatted text table is easier for the model to reference when writing SQL. This
is not about what is technically cleaner — it is about what helps the LLM produce better
output.

**Why is the error message an instruction?** Compare these two error responses:
- Bad: `"Error: table not found"`
- Good: `"Table 'campaign_metrics' not found. Use list_tables to see available tables."`

The good version tells the LLM both what happened and what to do about it. The LLM
cannot read your documentation — the error message IS the documentation.

> **Think About It**: What if you added value distributions (e.g., "platform has 3 unique
> values: google_ads, meta, linkedin") to `describe_table`? This would help the LLM write
> correct WHERE clauses without needing sample rows. The tradeoff: more tokens per response,
> but fewer follow-up tool calls. When is this worth it? When the table has important
> categorical columns that the LLM needs to filter by. This is a judgment call — there is
> no universal right answer.

---

## 3. query_data

### Purpose

Execute a read-only SQL query against the marketing database, save the results as a CSV
in the sandbox, and return a text summary to the LLM.

### Why This Tool Exists

This is the core data access tool. Everything the agent knows about the marketing data
comes through `query_data`. It exists as a separate tool (rather than being part of
`python_exec`) for three reasons:

1. **Safety**: SQL validation rejects write operations. A general-purpose Python tool
   with database access cannot provide this guarantee.
2. **Efficiency**: The LLM writes SQL, not Python + SQL. SQL is a more compact, direct
   way to express data queries. The LLM generates better SQL than Python-with-SQL.
3. **Context management**: The tool returns a text summary (max 200 rows), not raw data.
   Large result sets go to the sandbox as CSV files, keeping the LLM's context window clean.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `sql` | `str` | Yes | A read-only SQL query. Must start with `SELECT` or `WITH`. No write operations allowed. |

### Returns

A formatted text table with column headers, data rows (max 200), and a truncation notice
if applicable. On error, returns an error message that tells the LLM what went wrong
and how to fix it.

Success example:
```
Query returned 12 rows.

platform | total_spend | total_revenue | roas
-------------------------------------------
google_ads | 45230.50 | 148920.00 | 3.29
meta | 31200.80 | 65520.00 | 2.10
linkedin | 12890.20 | 38670.00 | 3.00
...
```

Error example:
```
SQL ERROR: ProgrammingError: column "ad_spend" does not exist
HINT: Perhaps you meant to reference the column "daily_metrics.spend".
```

Truncation example:
```
Query returned 200+ (truncated) rows.

...

NOTE: Results truncated to 200 rows. Add a LIMIT clause or more specific WHERE conditions.
```

### Implementation

```python
"""Tool: execute read-only SQL queries against the marketing database."""

import re

from langchain_core.tools import tool
from sqlalchemy import text

from marketing_agent.db.connection import async_session


# Maximum rows to return to the LLM. This is a context window management
# decision, not a database limit. 200 rows formatted as text is roughly
# 4,000-8,000 tokens — significant but manageable. 10,000 rows would be
# 200,000+ tokens, which would blow the context window.
MAX_ROWS = 200


def _validate_sql(sql: str) -> str | None:
    """Check that the SQL is read-only. Returns an error message or None if valid.

    This is a safety net, not a SQL parser. A determined attacker could bypass
    this with creative SQL. But the agent is not an attacker — this catches
    the common case: the LLM accidentally generating INSERT/UPDATE/DELETE.

    Why regex instead of a SQL parser? Simplicity. A full SQL parser (like
    sqlparse or sqlglot) adds a dependency and complexity for a check that
    just needs to catch obvious cases. The database user should also be
    read-only (defense in depth), so this is the second line of defense.
    """
    normalized = sql.strip().upper()

    # Must start with SELECT or WITH (CTEs)
    if not (normalized.startswith("SELECT") or normalized.startswith("WITH")):
        return "Only SELECT queries are allowed. Query must start with SELECT or WITH."

    # Block write operations — match as standalone words to avoid
    # false positives on column names like "update_date"
    write_keywords = ["INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "CREATE", "TRUNCATE"]
    for keyword in write_keywords:
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
    # Step 1: Validate before executing. Fail fast with a helpful message.
    error = _validate_sql(sql)
    if error:
        return f"ERROR: {error}"

    try:
        async with async_session() as session:
            result = await session.execute(text(sql))
            # Fetch one extra row to detect whether we hit the limit.
            # This avoids a separate COUNT query.
            rows = result.fetchmany(MAX_ROWS + 1)
            col_names = list(result.keys())

            if not rows:
                return "Query returned 0 rows."

            truncated = len(rows) > MAX_ROWS
            if truncated:
                rows = rows[:MAX_ROWS]

            # Format as a readable text table. Why text and not JSON?
            # LLMs read formatted tables more accurately than they parse
            # JSON arrays. The text format also compresses better in the
            # context window (no repeated key names).
            lines = [
                f"Query returned {len(rows)}{'+ (truncated)' if truncated else ''} rows.",
                "",
            ]

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
        # Return the full error — PostgreSQL error messages are often
        # helpful enough for the LLM to self-correct. "column 'ad_spend'
        # does not exist" tells it exactly what to fix.
        return f"SQL ERROR: {type(e).__name__}: {e}"
```

### Example Usage

**Example 1: Basic aggregation query**

```
LLM calls: query_data(sql="""
    SELECT platform,
           SUM(spend) AS total_spend,
           ROUND(SUM(revenue) / NULLIF(SUM(spend), 0), 2) AS roas
    FROM daily_metrics
    WHERE date >= '2026-01-01'
    GROUP BY platform
    ORDER BY total_spend DESC
""")

LLM sees back:
  "Query returned 3 rows.

   platform | total_spend | roas
   ----------------------------
   google_ads | 45230.50 | 3.29
   meta | 31200.80 | 2.10
   linkedin | 12890.20 | 3.00"

LLM thinks: "Google Ads has the highest spend and ROAS. LinkedIn has surprisingly good
ROAS relative to its spend. I should report this finding."
```

**Example 2: Query with SQL error (self-correction)**

```
LLM calls: query_data(sql="SELECT ad_spend FROM daily_metrics LIMIT 5")

LLM sees back:
  "SQL ERROR: ProgrammingError: column 'ad_spend' does not exist"

LLM thinks: "The column is called 'spend', not 'ad_spend' — I saw this in the
describe_table output. Let me fix the query."

LLM calls: query_data(sql="SELECT spend FROM daily_metrics LIMIT 5")
(succeeds)
```

**Example 3: Large result set (truncation)**

```
LLM calls: query_data(sql="SELECT * FROM daily_metrics")

LLM sees back:
  "Query returned 200+ (truncated) rows.

   id | date | campaign_id | platform | ...
   ...
   (200 rows of data)

   NOTE: Results truncated to 200 rows. Add a LIMIT clause or more specific
   WHERE conditions."

LLM thinks: "I got truncated results. I should use GROUP BY to aggregate the data
or add a WHERE clause to narrow it down."
```

### Common Mistakes

| Mistake | What Happens | Fix |
|---------|-------------|-----|
| Selecting all rows without LIMIT or GROUP BY | Truncated results, wasted tokens | Use aggregations for summaries, LIMIT for samples |
| Using wrong column names | SQL error | Call `describe_table` first to see exact names |
| Trying to write data (INSERT/UPDATE) | "Write operations are not allowed" error | This tool is read-only by design |
| Not using NULLIF for division | Division by zero errors | `ROUND(SUM(revenue) / NULLIF(SUM(spend), 0), 2)` |
| Referencing the tool description hints wrong | Calculated metrics are wrong | CTR = clicks/impressions (not impressions/clicks) |

### Design Decisions

**Why return a text summary instead of raw data?**

This is the single most important design decision in the tool set. Consider what happens
if `query_data` returned all 14,000 rows from `daily_metrics`:

- At ~50 tokens per row, that is 700,000 tokens — well beyond most context windows
- The LLM cannot meaningfully reason about 14,000 rows anyway
- Most queries only need aggregated results (totals, averages, trends)

By capping at 200 rows and encouraging aggregations in the tool description, we keep the
LLM's context window clean. When the LLM needs to process raw data (for charts or
statistics), it uses `python_exec` to work with CSV files in the sandbox.

**Why is the tool description so detailed?**

Look at the description — it includes specific column names, metric formulas, and SQL
tips. This is **prompt engineering embedded in the tool**. The LLM reads this description
every time it considers calling the tool. By including `CTR = clicks/impressions` in the
description, we prevent the LLM from having to figure out the formula from scratch.

**Why regex validation instead of a real SQL parser?**

Three reasons: (1) simpler code with fewer dependencies, (2) the database user should
also be read-only (defense in depth), and (3) catching "the LLM accidentally wrote INSERT"
does not require a full parser. If you had untrusted human users writing SQL directly,
you would want a proper parser. But the LLM is not trying to be clever — it just
occasionally makes mistakes.

> **Think About It**: The tool description says "Use list_tables and describe_table first
> to learn the schema." This is a behavioral instruction embedded in a tool description.
> The LLM will follow this instruction more reliably than if it were in the system prompt
> alone, because the LLM re-reads tool descriptions at decision time. Where you put
> instructions matters as much as what the instructions say.

---

## 4. python_exec

### Purpose

Execute arbitrary Python code in an isolated Docker sandbox with pre-installed data
science libraries (pandas, numpy, matplotlib, seaborn, scipy, etc.), returning stdout
to the LLM.

### Why This Tool Exists

SQL is great for querying and aggregating data, but it cannot do everything. Statistical
tests, pivot tables with custom logic, data transformations, correlation analysis,
forecasting — these require Python. `python_exec` is the general-purpose computation tool
that bridges the gap between "I have data" and "I have insights."

It runs in a Docker sandbox (not in the agent process) for three critical reasons:

1. **Security**: The LLM generates code. You cannot trust LLM-generated code to run in
   your application process. The sandbox has no network access, limited CPU/memory, and
   runs as a non-root user. If the code does something destructive, only the sandbox
   is affected.
2. **Library access**: The sandbox image includes pandas, numpy, matplotlib, seaborn,
   openpyxl, scipy, plotly, weasyprint, and jinja2. Installing these in the agent process
   would bloat the image and create dependency conflicts.
3. **Isolation**: Each sandbox execution is independent. If one execution crashes or
   leaks memory, the next execution starts fresh (the process restarts, but the filesystem
   persists). The agent process is never affected.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `code` | `str` | Yes | Python code to execute. Use `print()` to return output to the LLM. Files persist in the sandbox filesystem between calls. |

### Returns

A string containing:
- stdout from the code (whatever was `print()`ed)
- Any error traceback if the code failed
- A list of newly created files in the sandbox

Example success:
```
Mean ROAS by platform:
  google_ads: 3.29
  meta: 2.10
  linkedin: 3.00

Correlation between spend and revenue: 0.87 (p < 0.001)

Files created: analysis_summary.csv
```

Example error:
```
ERROR:
Traceback (most recent call last):
  File "<string>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: 'data/spend_data.csv'
```

### Implementation

```python
"""Tool: execute Python code in the isolated sandbox."""

from langchain_core.tools import tool

from marketing_agent.sandbox.client import sandbox


@tool
async def python_exec(code: str) -> str:
    """Execute Python code in an isolated sandbox environment.

    The sandbox has pandas, matplotlib, seaborn, openpyxl, plotly, numpy, scipy,
    weasyprint, jinja2, and tabulate pre-installed.

    **This is your universal compute tool.** python_exec handles ALL computation:
    statistical analysis, chart generation, Excel workbooks, PDF reports, data
    transforms, forecasting — everything. The sandbox has every library you need.

    **Key pattern — sandbox-as-memory:**
    Data persists in the sandbox filesystem between calls. Use this to build up
    analysis step by step:

    1. query_data returns results; python_exec saves them as CSV with open()
    2. python_exec reads that CSV with pandas and computes analysis
    3. python_exec writes charts (matplotlib), Excel (openpyxl), or PDF (weasyprint)

    Use print() to return results to the conversation.

    IMPORTANT:
    - Always print() your results — the return value is stdout
    - For charts: plt.savefig('charts/chart.png', dpi=150, bbox_inches='tight'); plt.close()
    - For Excel: use pandas ExcelWriter with engine='openpyxl'
    - For PDF: use weasyprint — HTML(string=html).write_pdf('exports/report.pdf')
    - For DataFrames, use print(df.to_string()) or print(df.to_markdown())
    - The sandbox has NO network access — all data must come from files
    - For file I/O: use open(), os.listdir(), pd.read_csv() directly — no separate file tools needed

    Args:
        code: Python code to execute. Use print() to return output.
    """
    # Send the code to the sandbox for execution.
    # The sandbox returns a dict with stdout, stderr, success, and files_created.
    result = await sandbox.execute(code, timeout=30)

    parts = []

    # Include stdout — this is the primary return value.
    # Everything the LLM needs to know should be print()ed.
    if result["stdout"]:
        parts.append(result["stdout"])

    # Include stderr only on failure. On success, stderr often has
    # harmless warnings (e.g., matplotlib backend warnings) that
    # would confuse the LLM.
    if result["stderr"] and not result["success"]:
        parts.append(f"ERROR:\n{result['stderr']}")

    # Report newly created files — the LLM needs to know what files
    # are available in the sandbox for subsequent tool calls.
    if result["files_created"]:
        parts.append(f"Files created: {', '.join(result['files_created'])}")

    # If the code ran but produced no output, say so explicitly.
    # Silence is confusing — the LLM would not know if the tool
    # call worked or failed.
    if not parts:
        parts.append("Code executed successfully (no output).")

    return "\n\n".join(parts)
```

### Example Usage

**Example 1: Statistical analysis**

```
LLM calls: python_exec(code="""
import pandas as pd
from scipy import stats

df = pd.read_csv('data/daily_metrics.csv')

# Calculate correlation between spend and revenue
corr, p_value = stats.pearsonr(df['spend'], df['revenue'])

# Weekly aggregation
df['date'] = pd.to_datetime(df['date'])
weekly = df.groupby([pd.Grouper(key='date', freq='W'), 'platform']).agg({
    'spend': 'sum',
    'revenue': 'sum',
    'clicks': 'sum',
    'impressions': 'sum'
}).reset_index()

weekly['roas'] = weekly['revenue'] / weekly['spend']
weekly['ctr'] = weekly['clicks'] / weekly['impressions'] * 100

print(f"Spend-Revenue Correlation: {corr:.3f} (p={p_value:.4f})")
print()
print("Weekly ROAS by Platform:")
print(weekly.pivot_table(values='roas', index='date', columns='platform').to_string())

weekly.to_csv('data/weekly_analysis.csv', index=False)
""")

LLM sees back:
  "Spend-Revenue Correlation: 0.872 (p=0.0000)

   Weekly ROAS by Platform:
   platform     google_ads  linkedin  meta
   date
   2026-01-05   3.41       2.95      2.08
   2026-01-12   3.22       3.10      2.15
   ...

   Files created: weekly_analysis.csv"
```

**Example 2: Debugging a failed execution**

```
LLM calls: python_exec(code="""
import pandas as pd
df = pd.read_csv('data/campaign_data.csv')
print(df.groupby('channel').mean())
""")

LLM sees back:
  "ERROR:
   Traceback (most recent call last):
     File '<string>', line 3, in <module>
   KeyError: 'channel'

   Available columns: ['platform', 'campaign_name', 'spend', 'revenue']"

LLM thinks: "The column is called 'platform', not 'channel'. Let me fix the code."
```

**Example 3: Chart generation (matplotlib/seaborn)**

```
LLM calls: python_exec(code="""
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
sns.set_theme(style="whitegrid")

df = pd.read_csv('data/platform_spend.csv')
fig, ax = plt.subplots(figsize=(10, 6))
sns.barplot(data=df, x='platform', y='total_spend', palette='viridis', ax=ax)
ax.set_title('Total Spend by Platform — Q1 2026', fontsize=14, fontweight='bold')
ax.set_ylabel('Total Spend ($)')
ax.set_xlabel('Platform')
for i, v in enumerate(df['total_spend']):
    ax.text(i, v + 500, f'${v:,.0f}', ha='center', fontsize=10)
plt.tight_layout()
plt.savefig('charts/spend_chart.png', dpi=150, bbox_inches='tight')
plt.close()
print("Chart saved to charts/spend_chart.png")
""")

LLM sees back:
  "Chart saved to charts/spend_chart.png

   Files created: spend_chart.png"
```

**Example 4: Excel workbook generation (openpyxl)**

```
LLM calls: python_exec(code="""
import pandas as pd
from openpyxl.styles import Font
from openpyxl.utils import get_column_letter

df = pd.read_csv('data/campaign_performance.csv')

with pd.ExcelWriter('exports/q1_report.xlsx', engine='openpyxl') as writer:
    df.to_excel(writer, sheet_name='Raw Data', index=False)

    platform_summary = df.groupby('platform').agg({
        'spend': 'sum', 'revenue': 'sum', 'clicks': 'sum'
    }).round(2)
    platform_summary['roas'] = (platform_summary['revenue'] / platform_summary['spend']).round(2)
    platform_summary.to_excel(writer, sheet_name='Platform Summary')

    for sheet_name in writer.sheets:
        ws = writer.sheets[sheet_name]
        for cell in ws[1]:
            cell.font = Font(bold=True)
        for col in range(1, ws.max_column + 1):
            ws.column_dimensions[get_column_letter(col)].width = 15

print("Excel workbook saved to exports/q1_report.xlsx with 2 sheets")
""")

LLM sees back:
  "Excel workbook saved to exports/q1_report.xlsx with 2 sheets

   Files created: q1_report.xlsx"
```

**Example 5: PDF report generation (weasyprint)**

```
LLM calls: python_exec(code="""
import markdown
from weasyprint import HTML
from jinja2 import Template
from datetime import date

md_content = '''
## Executive Summary
Total Q1 spend: **$89,321**, revenue: **$253,110**, ROAS: **2.84**

## Platform Breakdown
| Platform | Spend | Revenue | ROAS |
|----------|-------|---------|------|
| Google Ads | $45,230 | $148,920 | 3.29 |
| Meta | $31,200 | $65,520 | 2.10 |
| LinkedIn | $12,890 | $38,670 | 3.00 |

![Spend Trend](charts/spend_chart.png)
'''

html_body = markdown.markdown(md_content, extensions=["tables", "fenced_code"])

template = Template('''
<!DOCTYPE html>
<html><head><style>
  @page { size: A4; margin: 2cm; }
  body { font-family: Arial, sans-serif; font-size: 11pt; line-height: 1.6; }
  h1 { color: #1a1a2e; border-bottom: 2px solid #4a90d9; }
  table { border-collapse: collapse; width: 100%; margin: 16px 0; }
  th, td { border: 1px solid #ddd; padding: 8px; }
  th { background-color: #4a90d9; color: white; }
  img { max-width: 100%; }
</style></head>
<body>
  <h1>Q1 2026 Marketing Report</h1>
  <p>Generated on {{ today }}</p>
  {{ body }}
</body></html>
''')

html = template.render(body=html_body, today=date.today().strftime("%B %d, %Y"))
HTML(string=html, base_url="./").write_pdf("exports/q1_report.pdf")
print("PDF saved to exports/q1_report.pdf")
""")

LLM sees back:
  "PDF saved to exports/q1_report.pdf

   Files created: q1_report.pdf"
```

**Example 6: Building up analysis step by step**

```
# Step 1: Query data from database
LLM calls: query_data(sql="SELECT * FROM daily_metrics WHERE date >= '2026-01-01'")

# Step 2: Save data as CSV and analyze with pandas (all in one python_exec call)
LLM calls: python_exec(code="""
import pandas as pd

# Save query results to a file for reuse
data = "date,platform,spend,revenue\n..."
with open('data/q1_data.csv', 'w') as f:
    f.write(data)

# Analyze with full pandas power
df = pd.read_csv('data/q1_data.csv')
# ... complex analysis
print(df.describe())
""")
```

### Common Mistakes

| Mistake | What Happens | Fix |
|---------|-------------|-----|
| Forgetting `print()` | "Code executed successfully (no output)" — LLM learns nothing | Always `print()` results |
| Referencing a file that does not exist | `FileNotFoundError` | Run `query_data` or prior `python_exec` to create the file first |
| Trying to `pip install` packages | Fails (no network access) | Use only pre-installed libraries |
| Running code that takes > 30 seconds | Timeout error | Optimize the code or process smaller data subsets |
| Writing matplotlib code without `plt.close()` | Memory leak across multiple chart calls | Always call `plt.close()` after `plt.savefig()` |

### Design Decisions

**Why is `python_exec` the ONE tool for all computation?**

This follows the **"smart agent, simple tools"** philosophy. Instead of having separate
`export_chart`, `export_excel`, and `export_report` convenience wrappers, we give the
agent a single powerful compute tool and teach it HOW to use it through skills
(system prompt instructions).

The reasoning:

1. **Fewer tools = better decisions.** With 4 tools instead of 10, the LLM spends less
   time choosing between tools and more time executing. Tool selection errors drop
   significantly when the choice is clear: "need to compute something? use `python_exec`."

2. **Skills guide the agent, not tools.** The agent's skill system (system prompt templates)
   includes detailed instructions for chart generation, Excel creation, and PDF reports.
   These instructions are richer than any tool description because they can include
   multi-step workflows, brand guidelines, and quality standards. The tool just executes;
   the skill teaches.

3. **The sandbox has every library.** The Docker sandbox includes matplotlib, seaborn,
   plotly, openpyxl, weasyprint, jinja2, scipy, and more. `python_exec` can produce ANY
   output format. A convenience wrapper limits you to the patterns the wrapper supports.

4. **Maintenance simplicity.** One tool to test, one tool to debug, one tool to document.
   Convenience wrappers were thin wrappers around sandbox execution anyway — the real logic
   was always in the Python code the LLM generated.

**Why Docker sandbox instead of running Python in-process?**

Imagine the LLM generates this code: `import os; os.system('rm -rf /')`. In-process, this
would destroy your server. In a Docker sandbox with no network and limited permissions,
the damage is contained to the disposable sandbox filesystem.

Beyond security, the sandbox provides **dependency isolation**. Your agent runs on a lean
Python image. The sandbox has pandas, scipy, matplotlib, openpyxl, weasyprint, and more.
These libraries have heavy native dependencies (C extensions, system fonts, etc.) that
you do not want in your agent image.

**Why does `python_exec` return stdout instead of the execution result?**

Python's `exec()` does not return a value — it runs statements. The only way to get data
out of `exec()` is through side effects: printing to stdout, writing to files, or raising
exceptions. `print()` is the simplest and most natural way for the LLM to communicate
results back. The LLM understands `print()` intuitively because it has seen millions of
Python examples that use `print()` for output.

**Why suppress stderr on success?**

Many libraries emit warnings to stderr that are irrelevant to the LLM:
- matplotlib: "UserWarning: Matplotlib is currently using agg..."
- pandas: "FutureWarning: DataFrame.groupby with axis=1..."
- seaborn: "UserWarning: The figure layout has changed..."

These warnings confuse the LLM into thinking something went wrong. By only showing stderr
on failure, we give the LLM clean signal: either the code worked (here is the output) or
it failed (here is the traceback).

> **Think About It**: The sandbox-as-memory pattern (data persists in the sandbox filesystem
> between calls) is a key architectural decision. An alternative would be to pass data directly
> between tools via the agent state. Why is the filesystem approach better? Because
> data can be large (10,000+ rows of CSV), and you do not want that data in the LLM's
> context window or LangGraph's state checkpoints. The filesystem is an out-of-band
> data store — the LLM only sees summaries and file paths.

---

## 5. research_agent (Future/Optional)

> **Note**: `research_agent` is not part of the core 4-tool set. It is documented here as
> a future addition for when the agent needs parallel research capabilities. The current
> agent uses only: `list_tables`, `describe_table`, `query_data`, and `python_exec`.

### Purpose

Spawn one or more research subagents that work in parallel on focused data-gathering
tasks, each producing output files in the shared sandbox.

### Why This Tool Exists

Some analysis tasks are naturally parallelizable. "Compare Google Ads vs Meta vs LinkedIn
Q1 performance" requires three independent analyses that can run simultaneously. Without
`research_agent`, the lead agent would query each platform sequentially — three full
ReAct loops in series.

`research_agent` solves this by:
1. Spawning a subagent for each task (each with its own ReAct loop)
2. Running all subagents concurrently via `asyncio.gather`
3. Having each subagent write results to a file in the shared sandbox
4. Returning summaries of all subagent findings to the lead agent

The lead agent then combines the results using `python_exec`.

This is the **fan-out / fan-in** pattern: decompose a complex task into parallel subtasks,
execute them concurrently, then synthesize the results.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `tasks` | `list[dict]` | Yes | List of task objects. Each task has `"prompt"` (the research question) and `"output_file"` (where to save results in the sandbox). |

Each task dict:

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `prompt` | `str` | Yes | The specific research question for the subagent. Be detailed — the subagent knows nothing about the broader context. |
| `output_file` | `str` | Yes | Filename in the sandbox where the subagent should save structured output (CSV or JSON). |

### Returns

A summary of all subagent results, separated by `---`:

```
[google_q1.csv] Google Ads Q1 2026: Total spend $45,230, average ROAS 3.29,
top campaign "search_brand_001" with ROAS 4.8. Data saved to data/google_q1.csv
with columns: week, spend, revenue, roas, clicks, conversions.

---

[meta_q1.csv] Meta Q1 2026: Total spend $31,200, average ROAS 2.10,
top campaign "retargeting_003" with ROAS 3.5. Data saved to data/meta_q1.csv
with columns: week, spend, revenue, roas, clicks, conversions.
```

### Implementation

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
    # Build the subagent graph once — it will be invoked multiple times
    # with different thread IDs for isolation.
    subagent_graph = build_subagent_graph()

    async def run_one(task: dict) -> str:
        """Run a single subagent to completion.

        Each subagent gets:
        - Its own thread_id (isolated conversation state)
        - A system prompt that focuses it on the specific task
        - Access to query, compute, but NOT export or subagent tools
        """
        prompt = task["prompt"]
        output_file = task.get("output_file", "result.csv")

        # Unique thread_id ensures each subagent has its own conversation
        # state and does not interfere with others.
        thread_id = str(uuid.uuid4())

        # The system prompt scopes the subagent to a single task.
        # It includes the output file path so the subagent knows
        # where to save results.
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
            {
                "messages": [
                    SystemMessage(content=system_prompt),
                    HumanMessage(content=prompt),
                ]
            },
            config=config,
        )

        # Return the subagent's final message — this is its summary
        # of what it found and where it saved the data.
        last_msg = result["messages"][-1]
        return f"[{output_file}] {last_msg.content}"

    # Run ALL subagents concurrently. asyncio.gather runs them in parallel
    # (they're all I/O-bound — waiting on LLM API calls and database queries).
    # This is the key performance advantage: 3 platforms analyzed in the
    # time it takes to analyze 1.
    results = await asyncio.gather(*[run_one(task) for task in tasks])

    return "\n\n---\n\n".join(results)
```

### Example Usage

**Example 1: Parallel platform comparison**

```
LLM calls: research_agent(tasks=[
    {
        "prompt": "Analyze Google Ads Q1 2026: total spend, weekly ROAS trend, "
                  "top 5 campaigns by ROAS, and CTR trend. Save detailed data to "
                  "data/google_q1.csv",
        "output_file": "google_q1.csv"
    },
    {
        "prompt": "Analyze Meta Q1 2026: total spend, weekly ROAS trend, "
                  "top 5 campaigns by ROAS, and CTR trend. Save detailed data to "
                  "data/meta_q1.csv",
        "output_file": "meta_q1.csv"
    },
    {
        "prompt": "Analyze LinkedIn Q1 2026: total spend, weekly ROAS trend, "
                  "top 5 campaigns by ROAS, and CTR trend. Save detailed data to "
                  "data/linkedin_q1.csv",
        "output_file": "linkedin_q1.csv"
    }
])

# Three subagents run concurrently, each completing their own ReAct loop:
#   Subagent A: list_tables → describe_table → query_data (Google) → python_exec → done
#   Subagent B: list_tables → describe_table → query_data (Meta) → python_exec → done
#   Subagent C: list_tables → describe_table → query_data (LinkedIn) → python_exec → done

LLM sees back:
  "[google_q1.csv] Google Ads Q1: $45,230 total spend, ROAS ranged from
   2.9 to 3.6, top campaign 'search_brand_001' (ROAS 4.8). Data saved with
   columns: week, spend, revenue, roas, clicks, conversions, ctr.

   ---

   [meta_q1.csv] Meta Q1: $31,200 total spend, ROAS ranged from 1.8 to 2.4,
   top campaign 'retargeting_003' (ROAS 3.5). Data saved.

   ---

   [linkedin_q1.csv] LinkedIn Q1: $12,890 total spend, ROAS ranged from 2.5 to 3.3,
   top campaign 'sponsored_content_007' (ROAS 3.8). Data saved."

LLM then calls: python_exec(code="""
import pandas as pd
google = pd.read_csv('data/google_q1.csv')
meta = pd.read_csv('data/meta_q1.csv')
linkedin = pd.read_csv('data/linkedin_q1.csv')
# ... combine and compare ...
""")
```

**Example 2: Time period analysis**

```
LLM calls: research_agent(tasks=[
    {"prompt": "Analyze all platforms' performance in January 2026",
     "output_file": "january_2026.csv"},
    {"prompt": "Analyze all platforms' performance in February 2026",
     "output_file": "february_2026.csv"},
    {"prompt": "Analyze all platforms' performance in March 2026",
     "output_file": "march_2026.csv"},
])
```

### Common Mistakes

| Mistake | What Happens | Fix |
|---------|-------------|-----|
| Vague prompts | Subagent produces incomplete or wrong analysis | Be specific: include metrics, time periods, and output format |
| Not specifying output file in the prompt | Subagent may not save to the expected location | Include the full path in both `prompt` and `output_file` |
| Too many tasks (10+) | High LLM API costs, potential rate limiting | Limit to 3-5 parallel tasks |
| Expecting subagents to generate charts | Subagents only have data tools, not python_exec | The lead agent should generate charts from subagent CSV output using python_exec |

### Design Decisions

**Why can't subagents spawn more subagents?**

Infinite recursion. If subagent A could call `research_agent`, it could spawn subagent B,
which could spawn subagent C, and so on. The subagent graph deliberately excludes
`research_agent` from its tool set. This is a hard constraint, not a suggestion — the tool
is simply not available to subagents.

**Why foreground execution (wait for all) instead of background?**

Simplicity. The lead agent calls `research_agent`, waits for all subagents to complete,
then reads their results and continues. A background pattern would let the lead agent
do other work while subagents run, but it would need polling ("are the subagents done
yet?"), error handling for partial failures, and state management. Start simple; add
complexity only when you measure a need for it.

**Why do subagents share the sandbox filesystem?**

The sandbox filesystem is shared across all subagents and the lead agent.
This is the communication channel: subagents write CSVs, the lead
agent reads them. No message passing, no shared memory, no databases — just files. This
is the simplest possible inter-agent communication mechanism.

**Why give subagents a detailed system prompt?**

Subagents know nothing about the user's original question. They only know their specific
task. The system prompt must include:
- What to analyze (the prompt)
- Where to save results (the output file)
- What format to use (CSV/JSON)
- What tools are available (data tools only)

Without this context, the subagent would waste tool calls trying to figure out what it
should do.

> **Think About It**: What happens if two subagents try to write to the same file
> simultaneously? In the current implementation, the last writer wins — there is no file
> locking. This is why each task has a unique `output_file`. What would you do if you
> needed subagents to append to a shared file? You would need either file locking or a
> different communication pattern (e.g., each subagent writes to its own file, and the
> lead agent merges them).

---

## Tool Design Patterns

These patterns recur across all 4 core tools. Understanding them will help you design tools
for any agent, not just this marketing analytics agent.

### Pattern 1: Data Tools Return Summaries, Not Raw Data

**The pattern**: `query_data` returns formatted text tables (max 200 rows), not raw result
sets. `python_exec` returns stdout, not Python objects. `describe_table` returns formatted
column info, not a JSON schema.

**Why**: The LLM's context window is finite and expensive. Returning 14,000 rows of CSV
data would consume the entire context window and the LLM cannot meaningfully reason about
that much data anyway. Summaries give the LLM enough information to make decisions without
drowning in data.

**The sandbox-as-memory escape hatch**: When the LLM needs to process large datasets, it
uses `python_exec` to work with files in the sandbox. The full data lives in the sandbox
filesystem, not in the LLM's context. The LLM sees summaries and file paths — enough to
orchestrate the analysis without holding all the data.

**When to break this pattern**: If your data is always small (under 50 rows), returning
raw data is fine. The summary pattern is for tools that might return unbounded amounts
of data.

### Pattern 2: One Compute Tool, Many Outputs

**The pattern**: `python_exec` is a single tool that produces charts (matplotlib), Excel
workbooks (openpyxl), PDF reports (weasyprint), statistical analyses (scipy), and any other
computed output. There are no separate `export_chart`, `export_excel`, or `export_report`
tools.

**Why**: Fewer tools means fewer decision points for the LLM. With 4 tools instead of 10+,
the LLM spends less time choosing and more time executing. Tool selection errors drop when
the choice is obvious: "need to compute or create something? use `python_exec`."

**How the agent learns patterns**: Instead of encoding chart/Excel/PDF generation into
separate tool wrappers, the agent's skill system (system prompt templates) provides detailed
instructions for each output type. Skills are richer than tool descriptions — they can
include multi-step workflows, brand guidelines, and quality standards. The tool just
executes; the skill teaches.

**The tradeoff**: The agent must write more code per call (matplotlib boilerplate, openpyxl
formatting, etc.). But modern LLMs handle this well, and the flexibility is worth it — the
agent is not limited to the patterns a wrapper supports.

**When to break this pattern**: If a specific output format has a very high error rate
through `python_exec` (e.g., the LLM consistently forgets `plt.close()`), AND the format
is requested frequently, consider a convenience wrapper. But try fixing the skill
instructions first — it is cheaper and more flexible.

### Pattern 2b: Skills Guide the Agent, Not Tools

**The pattern**: The agent's behavior for complex tasks (chart generation, report formatting,
Excel workbook creation) is guided by the skill system (system prompt templates), not by
specialized tools. Tools provide capabilities; skills provide recipes.

**Why**: A tool description is limited to ~300 words and is sent on every LLM call. A skill
template can be thousands of words, loaded only when relevant, and can include multi-step
workflows, brand color palettes, formatting standards, and quality checklists.

**Example**: The "weekly report" skill includes instructions like "use the company color
palette (#4a90d9 for primary, #2ecc71 for positive trends)", "include a ROAS trend chart
and a spend-by-platform bar chart", and "format the PDF with A4 page size and 2cm margins."
None of this belongs in a tool description — it would bloat every LLM call even when the
user is not generating a report.

**How to decide**: If the instruction is about WHEN to use a tool or HOW to call it
correctly, put it in the tool description. If the instruction is about what to produce
or how to format the output, put it in a skill.

### Pattern 3: Schema Discovery Before Data Queries

**The pattern**: `list_tables` -> `describe_table` -> `query_data`. The LLM discovers the
schema progressively — first what tables exist, then what columns a specific table has,
then it writes SQL.

**Why**: LLMs do not know your database schema. If you skip discovery and go straight to
`query_data`, the LLM will guess column names, table names, and data types — and get them
wrong. The discovery flow is two extra tool calls that save many more error-and-retry
cycles.

**Progressive disclosure**: This is a UX concept applied to LLM tool design. Rather than
dumping the entire schema upfront (which wastes context), you let the LLM request exactly
the information it needs, when it needs it.

**How to encode this pattern**: The tool descriptions do the work. `list_tables` says
"Use this as your FIRST step." `describe_table` says "Use this after list_tables."
`query_data` says "Use list_tables and describe_table first." These instructions create
a behavioral chain that the LLM follows.

### Pattern 4: Error Messages Are Instructions

**The pattern**: Every error message tells the LLM what happened AND what to do about it.

Compare:
- Bad: `"Error: table not found"`
- Good: `"Table 'campaign_metrics' not found. Use list_tables to see available tables."`

- Bad: `"Error: write operation not allowed"`
- Good: `"Write operations are not allowed. Found 'INSERT' in query. Only SELECT queries are allowed. Query must start with SELECT or WITH."`

**Why**: The LLM cannot look at documentation, read source code, or ask a human for help.
The error message is the only information it gets. If the error message says what to do
next, the LLM can self-correct. If it just says "error," the LLM is stuck.

**How to write good error messages for LLMs**:
1. Say what happened: "Column 'ad_spend' does not exist"
2. Say what the LLM probably meant: "Perhaps you meant 'spend'"
3. Say how to fix it: "Use describe_table to see available columns"

### Pattern 5: Tool Descriptions Are Prompt Engineering

**The pattern**: The tool description (the docstring) is the most important part of a tool.
It determines when the LLM calls the tool, what arguments it passes, and how it interprets
the results.

**Example — the `query_data` description includes**:
- When to use it: "Use this to fetch campaign metrics..."
- Prerequisites: "Use list_tables and describe_table first"
- Usage tips: "Always include a LIMIT clause"
- Schema hints: "The daily_metrics table has: date, impressions, clicks..."
- Formula reference: "CTR = clicks/impressions, ROAS = revenue/spend"

Each of these lines is prompt engineering. The LLM reads this description every time it
considers calling `query_data`. Without the schema hints, the LLM would need to call
`describe_table` more often. Without the formula reference, it would sometimes get the
formulas wrong. The description is not documentation for humans — it is instructions
for the LLM.

**How to iterate tool descriptions**:
1. Write a first draft
2. Run the agent against 10 diverse prompts
3. Note where the LLM makes mistakes (wrong tool, wrong arguments, wrong interpretation)
4. Update the description to prevent those mistakes
5. Repeat

This is the same feedback loop you would use for system prompts — because tool descriptions
are system prompts in disguise.

---

## How to Add a New Tool

This section walks through adding a new tool from scratch. We will use a hypothetical
`upload_file` tool as an example — this tool would let the agent upload sandbox files to an
external storage service for sharing with stakeholders. (This is a future/optional tool,
not part of the core 4-tool set.)

### Step 1: Define the function with @tool decorator

```python
"""Tool: upload a sandbox file to external storage for sharing."""

from langchain_core.tools import tool


@tool
async def upload_file(path: str, description: str = "") -> str:
    """Upload a file from the sandbox to external storage and return a shareable link.

    Use this AFTER generating a file (chart, Excel, PDF) with python_exec:
    - Upload a chart PNG so the user can share it in Slack or email
    - Upload an Excel workbook for stakeholder distribution
    - Upload a PDF report for archival or sharing

    DO NOT use this for:
    - Intermediate data files (CSVs used only by python_exec) — no need to share these
    - Files that have not been created yet — generate them first with python_exec

    Args:
        path: Relative path in the sandbox (e.g., "q1_report.pdf", "spend_chart.png").
        description: Optional human-readable description for the upload.
    """
    pass  # Implementation in Step 3
```

### Step 2: Write the description (this is prompt engineering!)

The description above was carefully crafted. Let's break down why each section matters:

```python
# Line: "Upload a file from the sandbox to external storage..."
# Purpose: Tells the LLM WHAT this tool does in one sentence.

# Lines: "Use this AFTER generating a file..."
# Purpose: Tells the LLM WHEN to use it (positive examples).
# The bullet points cover the three most common use cases.

# Lines: "DO NOT use this for..."
# Purpose: Tells the LLM when NOT to use it (negative examples).
# Without this, the LLM might upload intermediate CSVs that
# nobody needs to see — wasting time and cluttering storage.

# Lines: "Args: path: Relative path in the sandbox..."
# Purpose: Tells the LLM HOW to format the input.
# The examples ("q1_report.pdf", "spend_chart.png") teach the LLM
# to reference actual generated files, not abstract paths.
```

**Bad version of the same description** (for comparison):

```python
"""Upload a file.

Args:
    path: File to upload.
    description: Description.
"""
```

This bad version would cause the LLM to:
- Upload intermediate data files that nobody needs (wasting API calls)
- Not know when to use this tool vs. just saving files with `python_exec`
- Not realize it should generate the file first with `python_exec`

### Step 3: Implement the logic

```python
@tool
async def upload_file(path: str, description: str = "") -> str:
    """Upload a file from the sandbox to external storage and return a shareable link.

    Use this AFTER generating a file (chart, Excel, PDF) with python_exec:
    - Upload a chart PNG so the user can share it in Slack or email
    - Upload an Excel workbook for stakeholder distribution
    - Upload a PDF report for archival or sharing

    DO NOT use this for:
    - Intermediate data files (CSVs used only by python_exec) — no need to share these
    - Files that have not been created yet — generate them first with python_exec

    Args:
        path: Relative path in the sandbox (e.g., "q1_report.pdf", "spend_chart.png").
        description: Optional human-readable description for the upload.
    """
    from marketing_agent.sandbox.client import sandbox

    # Normalize the path
    if not path.startswith("/"):
        full_path = path
    else:
        full_path = path

    try:
        # Read the file from the sandbox
        file_bytes = await sandbox.read_file(path)

        if not file_bytes:
            return f"ERROR: File '{path}' does not exist or is empty. Generate it with python_exec first."

        # Upload to external storage (e.g., S3, GCS)
        import httpx

        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{settings.storage_url}/upload",
                files={"file": (path.split("/")[-1], file_bytes)},
                data={"description": description} if description else {},
                headers={"Authorization": f"Bearer {settings.storage_api_key}"},
            )
            response.raise_for_status()
            data = response.json()

        url = data.get("url", "")
        return f"File uploaded: {path}\nShareable link: {url}"

    except Exception as e:
        return f"ERROR uploading '{path}': {e}. Verify the file exists with python_exec and os.listdir()."
```

### Step 4: Register it in the graph

```python
# In graph/nodes/lead_agent.py — add to imports and tools list:
from marketing_agent.tools.upload_file import upload_file

tools = [
    list_tables, describe_table, query_data, python_exec,
    upload_file,  # New tool
]
```

```python
# In graph/nodes/tool_executor.py — add to the tool map:
from marketing_agent.tools.upload_file import upload_file

TOOL_MAP["upload_file"] = upload_file
```

### Step 5: Test it

```python
"""Tests for upload_file tool."""

import pytest
import httpx

from marketing_agent.tools.upload_file import upload_file


@pytest.mark.parametrize(
    "path,expected_substring",
    [
        ("q1_report.pdf", "File uploaded"),
        ("spend_chart.png", "Shareable link"),
    ],
)
async def test_upload_file_returns_link(path, expected_substring):
    """upload_file should return a shareable link on success."""
    # In a real test, you would use httpx.MockTransport to mock the HTTP call
    # and sandbox.read_file to return fake file bytes.
    result = await upload_file.ainvoke({"path": path})
    assert expected_substring in result


async def test_upload_file_missing_file():
    """upload_file with a nonexistent file should return a helpful error."""
    result = await upload_file.ainvoke({"path": "nonexistent.pdf"})
    assert "does not exist" in result or "ERROR" in result


async def test_upload_file_with_description():
    """upload_file should accept an optional description."""
    result = await upload_file.ainvoke({"path": "report.pdf", "description": "Q1 marketing report"})
    assert isinstance(result, str)  # Should not error
```

### The Complete Checklist

When adding any new tool, verify:

- [ ] The `@tool` decorator is applied
- [ ] The function is `async` (all tools should be async for non-blocking execution)
- [ ] The description explains WHEN to use the tool (positive examples)
- [ ] The description explains when NOT to use the tool (negative examples)
- [ ] The description includes an example of good input
- [ ] Parameters have clear types and descriptions
- [ ] The return value is formatted text, not raw data structures
- [ ] Error messages tell the LLM what happened and how to fix it
- [ ] The tool is added to both the tools list (lead_agent.py) and the tool map (tool_executor.py)
- [ ] Tests cover: happy path, error case, edge cases
- [ ] If the tool should NOT be available to subagents, it is excluded from the subagent tool list

---

## Tool Interaction Patterns

Tools are most powerful in combination. These patterns show the common multi-tool workflows
that emerge in marketing analytics.

### Pattern 1: Schema Discovery Flow

```
list_tables → describe_table → query_data
```

**When**: Every new analysis session, or when the LLM encounters a table it has not seen.

```
Step 1: list_tables()
  → "campaigns: 156 rows, daily_metrics: 14,208 rows, platforms: 3 rows"

Step 2: describe_table("daily_metrics")
  → columns: date, platform, spend, revenue, clicks, impressions, conversions
  → sample rows showing data format

Step 3: query_data("SELECT platform, SUM(spend) FROM daily_metrics GROUP BY platform")
  → actual results
```

**Why this order matters**: Skipping steps 1-2 means the LLM guesses table and column
names. On a first attempt, it gets them wrong ~50% of the time. With discovery, it gets
them right ~95% of the time. Two extra tool calls save three error-retry cycles.

### Pattern 2: Analysis Flow

```
query_data → python_exec (save + analyze) → python_exec (chart)
```

**When**: The user asks for a visualization or statistical analysis.

```
Step 1: query_data("SELECT date, platform, spend, revenue FROM daily_metrics WHERE ...")
  → text table of results (LLM sees the data shape)

Step 2: python_exec("""
import pandas as pd

# Save query results as CSV for reuse
with open('data/metrics.csv', 'w') as f:
    f.write("date,platform,spend,revenue\n...")

df = pd.read_csv('data/metrics.csv')
# ... compute weekly aggregations, ROAS trends, etc.
df_weekly.to_csv('data/weekly_data.csv', index=False)
print(df_weekly.describe())
""")
  → summary statistics, file saved

Step 3: python_exec("""
import pandas as pd
import matplotlib.pyplot as plt
df = pd.read_csv('data/weekly_data.csv')
# ... create visualization
plt.savefig('charts/trend_chart.png', dpi=150, bbox_inches='tight')
plt.close()
print("Chart saved to charts/trend_chart.png")
""")
  → "Chart saved to charts/trend_chart.png"
```

### Pattern 3: Report Generation Flow

```
query_data (x N) → python_exec (process) → python_exec (charts) → python_exec (PDF)
```

**When**: The user asks for a comprehensive report (weekly report, quarterly review, etc.).

```
Step 1-2: Multiple query_data calls to gather different data slices
  → platform summaries, weekly trends, campaign rankings

Step 3: python_exec to process and save data as CSVs

Step 4-5: python_exec calls to generate different visualizations
  → spend_trend.png, roas_comparison.png, ctr_breakdown.png

Step 6: python_exec("""
from weasyprint import HTML
from jinja2 import Template

# Build HTML with embedded charts and data tables
html = Template('''...''').render(...)
HTML(string=html, base_url='./').write_pdf('exports/q1_report.pdf')
print("PDF report saved to exports/q1_report.pdf")
""")
  → "PDF report saved to exports/q1_report.pdf"
```

### Pattern 4: Parallel Research Flow (Future — requires research_agent)

```
research_agent (parallel) → python_exec (combine + chart)
```

**When**: The user asks to compare multiple segments that can be analyzed independently.

```
Step 1: research_agent(tasks=[
    {"prompt": "Analyze Google Ads Q1...", "output_file": "google.csv"},
    {"prompt": "Analyze Meta Q1...", "output_file": "meta.csv"},
    {"prompt": "Analyze LinkedIn Q1...", "output_file": "linkedin.csv"},
])
  → Three subagents run in parallel, each producing a CSV

Step 2: python_exec("""
import pandas as pd
import matplotlib.pyplot as plt

google = pd.read_csv('data/google.csv')
meta = pd.read_csv('data/meta.csv')
linkedin = pd.read_csv('data/linkedin.csv')
combined = pd.concat([google, meta, linkedin])
# ... compute cross-platform comparisons
combined.to_csv('data/comparison.csv', index=False)
print(combined.pivot_table(...))

# Generate comparison chart
fig, ax = plt.subplots(figsize=(10, 6))
# ... create visualization
plt.savefig('charts/comparison_chart.png', dpi=150, bbox_inches='tight')
plt.close()
print("Chart saved to charts/comparison_chart.png")
""")
  → Combined analysis + cross-platform comparison visualization
```

### Pattern 5: Iterative Debugging Flow

```
query_data (error) → describe_table → query_data (fixed) → python_exec (error) → python_exec (fixed)
```

**When**: The LLM makes a mistake and self-corrects using error messages.

```
Step 1: query_data("SELECT ad_spend FROM daily_metrics")
  → "SQL ERROR: column 'ad_spend' does not exist"

Step 2: describe_table("daily_metrics")
  → shows columns including "spend" (not "ad_spend")

Step 3: query_data("SELECT spend FROM daily_metrics LIMIT 5")
  → success

Step 4: python_exec("df = pd.read_csv('data/data.csv'); print(df.groupby('channel').sum())")
  → "ERROR: KeyError: 'channel'"

Step 5: python_exec("df = pd.read_csv('data/data.csv'); print(df.groupby('platform').sum())")
  → success
```

This flow works because every error message tells the LLM what went wrong. The LLM's
ability to self-correct depends entirely on the quality of error messages.

---

## The Tool Description Is Everything

This section deserves its own heading because tool descriptions are the single most
impactful lever you have over agent behavior. Changing a description changes what the
agent does — without changing any code.

### A/B Test: Bad vs Good Description

Here is the same tool with two different descriptions. Watch how the LLM's behavior changes.

**Bad description:**

```python
@tool
async def query_data(sql: str) -> str:
    """Run a SQL query and return results.

    Args:
        sql: SQL query to execute.
    """
```

**LLM behavior with bad description:**
- Calls `query_data` without calling `list_tables` first (guesses table names)
- Writes `SELECT * FROM data` (wrong table name, no LIMIT)
- Does not know column names (uses `ad_spend` instead of `spend`)
- Does not know metric formulas (computes CTR as impressions/clicks — inverted)
- Tries to run `INSERT INTO` queries (no mention of read-only constraint)
- Returns 14,000 rows into the context window (no hint about LIMIT)

**Good description:**

```python
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
```

**LLM behavior with good description:**
- Calls `list_tables` first (the description says to)
- Writes `SELECT platform, SUM(spend)... GROUP BY platform LIMIT 50` (aggregated, limited)
- Uses correct column names (the description lists them)
- Computes CTR correctly as `clicks/impressions` (the description has the formula)
- Never tries write operations (the description says "read-only" and "SELECT only")
- Handles large datasets with aggregations (the description says to)

**Same tool. Same code. Completely different agent behavior.** The only change was the
description.

### Tips for Writing Effective Tool Descriptions

1. **Start with WHAT and WHEN**: First sentence says what the tool does. Second sentence
   (or section) says when to use it.

2. **Include positive and negative examples**: "Use this FOR data queries. DO NOT use
   this for file generation (use python_exec instead)."

3. **Embed domain knowledge**: Column names, metric formulas, table relationships.
   The LLM cannot look these up — the description is its only reference.

4. **Include behavioral instructions**: "Use list_tables first." "Always include LIMIT."
   "Print your results." These are not suggestions — they are instructions the LLM follows.

5. **Add concrete examples**: A code example in the description acts as a one-shot prompt.
   The LLM will follow the example's patterns.

6. **Mention constraints**: "Read-only." "Max 200 rows." "No network access." Constraints
   prevent the LLM from attempting impossible things.

7. **Keep it under ~300 words**: The description is sent with every LLM call. If you have
   10 tools with 500-word descriptions each, that is 5,000 tokens of tool descriptions
   alone. Be concise.

### Common Description Pitfalls

**Too vague**: `"Execute code."` — The LLM does not know what language, what libraries
are available, or what the constraints are.

**Too detailed**: A 1,000-word description with every edge case documented. The LLM has
limited attention — the important instructions get lost in the noise.

**Missing constraints**: Not mentioning that `query_data` is read-only. The LLM will
try write operations and fail with a confusing error.

**Wrong audience**: Writing the description for a human developer instead of an LLM.
Humans read documentation differently than LLMs. LLMs need explicit behavioral
instructions ("use this FIRST", "always include X") that humans would find patronizing.

**No examples**: The most powerful tool descriptions include a concrete example. The
LLM learns by example more effectively than by instruction. A single good example
in the description is worth 50 words of explanation.

> **Think About It**: You are a prompt engineer, and the tool description is your prompt.
> Every word in it costs tokens on every LLM call. Every missing instruction is a potential
> agent failure. How would you test whether a tool description is effective? One approach:
> run the same 20 user queries with two different descriptions and measure success rate,
> tool calls per query, and error rate. This is A/B testing applied to AI engineering.

---

## Summary

The 4 core tools in this agent form a complete analytics workflow:

| Tool | Category | Purpose |
|------|----------|---------|
| `list_tables` | Data | Find available tables |
| `describe_table` | Data | Learn table structure |
| `query_data` | Data | Fetch data via SQL |
| `python_exec` | Compute | Run arbitrary Python — charts (matplotlib), Excel (openpyxl), PDF (weasyprint), statistics (scipy), file I/O (open(), os.listdir(), pd.read_csv()), and any other computation |

File operations (reading, writing, listing files) are handled directly through `python_exec`
using standard Python: `open()`, `os.listdir()`, `pd.read_csv()`, etc. No separate file I/O
tools are needed.

The patterns that make them work:
1. **Summaries, not raw data** — protect the context window
2. **One compute tool, many outputs** — `python_exec` handles all generation; skills guide the agent
3. **Progressive discovery** — let the LLM learn the schema step by step
4. **Instructive errors** — every error message is a recovery instruction
5. **Description as prompt** — tool descriptions are the most impactful prompt engineering surface

The most important lesson: **tools are not just code — they are an interface between an
LLM and the real world.** The description matters as much as the implementation. The return
value matters as much as the logic. The error messages matter as much as the happy path.
Design tools for the LLM, not for a human developer.
