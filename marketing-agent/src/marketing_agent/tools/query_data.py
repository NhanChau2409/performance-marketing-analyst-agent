"""Tool: execute read-only SQL queries against the marketing database."""

import sqlglot
import sqlglot.expressions as exp

from langchain_core.tools import tool
from sqlalchemy import text

from marketing_agent.db.connection import async_session


# Maximum rows to return — prevents the agent from dumping huge result sets
# into the LLM context window. The agent can always narrow its query.
MAX_ROWS = 200

_WRITE_TYPES = (
    exp.Insert,
    exp.Update,
    exp.Delete,
    exp.Drop,
    exp.Create,
    exp.Alter,
    exp.TruncateTable,
)


def _validate_sql(sql: str) -> str | None:
    """Check that the SQL is read-only using sqlglot's AST parser.

    Returns an error message or None if valid. Using a real parser (sqlglot)
    instead of regex avoids false positives (e.g. a column named 'update_time')
    and catches write operations hidden inside CTEs.
    """
    try:
        statements = sqlglot.parse(sql, dialect="postgres")
    except sqlglot.errors.ParseError as e:
        return f"Invalid SQL: {e}"

    if len(statements) != 1:
        return "Only a single SQL statement is allowed."

    stmt = statements[0]

    if isinstance(stmt, _WRITE_TYPES):
        return f"Only SELECT queries are allowed. Got: {type(stmt).__name__}."

    if not isinstance(stmt, (exp.Select, exp.Union, exp.Subquery)):
        return f"Only SELECT queries are allowed. Got: {type(stmt).__name__}."

    # Walk the full AST — catches write ops nested inside CTEs
    for node in stmt.walk():
        if isinstance(node, _WRITE_TYPES):
            return f"Write operations are not allowed inside CTEs or subqueries."

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
    - Calculate derived metrics in SQL: CTR = clicks::float/impressions, ROAS = revenue/spend,
      CPC = spend/clicks, CVR = conversions::float/clicks

    Args:
        sql: A read-only SQL query (SELECT only). Include aggregations and LIMIT when possible.
    """
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
