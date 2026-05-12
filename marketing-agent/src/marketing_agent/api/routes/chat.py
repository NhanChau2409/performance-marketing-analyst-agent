import json
import uuid

from fastapi import APIRouter
from langchain_core.messages import AIMessage, HumanMessage, ToolMessage
from pydantic import BaseModel

from marketing_agent.graph.graph import build_graph

router = APIRouter()

_graph = build_graph()


class ChatRequest(BaseModel):
    message: str
    thread_id: str = ""


def _extract_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(
            item.get("text", "") if isinstance(item, dict) else str(item)
            for item in content
            if not isinstance(item, dict) or item.get("type") == "text"
        )
    return ""


def _build_response(thread_id: str, messages: list) -> dict:
    last_human = max(
        (i for i, m in enumerate(messages) if isinstance(m, HumanMessage)),
        default=0,
    )
    turn = messages[last_human + 1:]

    text = ""
    for msg in reversed(turn):
        if isinstance(msg, AIMessage) and not msg.tool_calls:
            text = _extract_text(msg.content)
            break

    results = {
        msg.tool_call_id: msg.content
        for msg in turn
        if isinstance(msg, ToolMessage)
    }

    tool_calls = []
    chart_ids: set[str] = set()
    for msg in turn:
        if isinstance(msg, AIMessage) and msg.tool_calls:
            for tc in msg.tool_calls:
                if tc["name"] == "render_chart":
                    chart_ids.add(tc["id"])
                tool_calls.append({
                    "tool": tc["name"],
                    "input": json.dumps(tc["args"]),
                    "output": results.get(tc["id"], ""),
                })

    charts = []
    for msg in turn:
        if isinstance(msg, ToolMessage) and msg.tool_call_id in chart_ids:
            try:
                charts.append(json.loads(msg.content))
            except Exception:
                pass

    return {
        "thread_id": thread_id,
        "text": text,
        "charts": charts,
        "tool_calls": tool_calls,
    }


@router.post("/chat")
async def chat(req: ChatRequest):
    thread_id = req.thread_id or str(uuid.uuid4())
    config = {"configurable": {"thread_id": thread_id}}
    result = await _graph.ainvoke(
        {"messages": [HumanMessage(content=req.message)]},
        config=config,
    )
    return _build_response(thread_id, result["messages"])
