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
    openrouter_api_key: str = ""
    llm_model: str = "anthropic/claude-sonnet-4-5"

    # Database (used in Step 2)
    database_url: str = "postgresql+asyncpg://marketing:marketing_local@localhost:5432/marketing"

    # Sandbox (used in Step 3)
    sandbox_url: str = "http://localhost:8100"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


# Singleton — import this everywhere
settings = Settings()
