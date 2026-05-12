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
