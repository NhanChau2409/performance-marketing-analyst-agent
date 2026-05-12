from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from marketing_agent.api.routes import chat, health

app = FastAPI(title="Marketing Analytics Agent", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(chat.router, prefix="/api")
