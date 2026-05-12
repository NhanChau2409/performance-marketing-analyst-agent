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
