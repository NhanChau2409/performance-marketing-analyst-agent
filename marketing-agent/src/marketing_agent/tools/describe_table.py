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
