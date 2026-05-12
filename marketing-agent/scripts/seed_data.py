"""Script entry point for seeding the database."""

import asyncio
from marketing_agent.db.seed import seed

if __name__ == "__main__":
    asyncio.run(seed())
