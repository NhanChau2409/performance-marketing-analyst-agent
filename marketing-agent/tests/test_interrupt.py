"""Tests for improvement 6: human-in-the-loop interrupt behaviour.

Strategy
--------
The real lead_agent calls an LLM; the real tool_executor hits a database.
Both are patched with lightweight async stubs so tests run without any
external dependencies.

The stub_lead_agent is stateful: on the first call it returns a tool-call
AIMessage (triggering the interrupt); on the second call it returns a final
text answer (ending the graph). This mirrors realistic ReAct behaviour.
"""

import uuid
from unittest.mock import AsyncMock, patch, MagicMock

import pytest
from langchain_core.messages import AIMessage, HumanMessage, ToolMessage

from marketing_agent.graph.graph import build_graph


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _config() -> dict:
    return {"configurable": {"thread_id": str(uuid.uuid4())}}


def _tool_call(name: str = "list_tables", call_id: str = "call_1") -> dict:
    return {"id": call_id, "name": name, "args": {}, "type": "tool_call"}


def make_lead_agent_stub():
    """First invocation returns a tool call; second returns a final answer."""
    calls = 0

    async def _stub(state):
        nonlocal calls
        calls += 1
        if calls == 1:
            return {"messages": [AIMessage(content="", tool_calls=[_tool_call()])]}
        return {"messages": [AIMessage(content="Here are your tables: campaigns, daily_metrics.")]}

    return _stub


async def _tool_executor_stub(state):
    last_msg = state["messages"][-1]
    results = [
        ToolMessage(content="campaigns, daily_metrics", tool_call_id=tc["id"])
        for tc in last_msg.tool_calls
    ]
    return {"messages": results}


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def graph_with_stubs():
    """Build the real graph but replace LLM/DB nodes with deterministic stubs."""
    with (
        patch("marketing_agent.graph.graph.lead_agent", make_lead_agent_stub()),
        patch("marketing_agent.graph.graph.tool_executor", _tool_executor_stub),
    ):
        return build_graph()


# ---------------------------------------------------------------------------
# Test: graph pauses before tool_executor
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_graph_pauses_before_tool_executor(graph_with_stubs):
    config = _config()

    await graph_with_stubs.ainvoke(
        {"messages": [HumanMessage(content="List all tables")]},
        config=config,
    )

    state = await graph_with_stubs.aget_state(config)
    assert state.next == ("tool_executor",), (
        "Graph should be interrupted waiting for tool_executor approval"
    )


@pytest.mark.asyncio
async def test_interrupted_state_contains_pending_tool_calls(graph_with_stubs):
    config = _config()

    await graph_with_stubs.ainvoke(
        {"messages": [HumanMessage(content="List all tables")]},
        config=config,
    )

    state = await graph_with_stubs.aget_state(config)
    last_msg = state.values["messages"][-1]
    assert hasattr(last_msg, "tool_calls") and last_msg.tool_calls, (
        "Last message in interrupted state must carry the pending tool calls"
    )
    assert last_msg.tool_calls[0]["name"] == "list_tables"


# ---------------------------------------------------------------------------
# Test: graph completes after resume (approve)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_graph_completes_after_resume(graph_with_stubs):
    config = _config()

    # First invocation — hits interrupt
    await graph_with_stubs.ainvoke(
        {"messages": [HumanMessage(content="List all tables")]},
        config=config,
    )
    state = await graph_with_stubs.aget_state(config)
    assert state.next == ("tool_executor",)

    # Resume (user approved)
    await graph_with_stubs.ainvoke(None, config=config)

    state = await graph_with_stubs.aget_state(config)
    assert state.next == (), "Graph should have run to completion after resume"


@pytest.mark.asyncio
async def test_final_answer_present_after_resume(graph_with_stubs):
    config = _config()

    await graph_with_stubs.ainvoke(
        {"messages": [HumanMessage(content="List all tables")]},
        config=config,
    )
    result = await graph_with_stubs.ainvoke(None, config=config)

    last_msg = result["messages"][-1]
    assert isinstance(last_msg, AIMessage)
    assert last_msg.content, "Final message should contain a non-empty text answer"
    assert not last_msg.tool_calls, "Final message should have no pending tool calls"


# ---------------------------------------------------------------------------
# Test: tool results are present in message history after resume
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_tool_messages_in_history_after_resume(graph_with_stubs):
    config = _config()

    await graph_with_stubs.ainvoke(
        {"messages": [HumanMessage(content="List all tables")]},
        config=config,
    )
    result = await graph_with_stubs.ainvoke(None, config=config)

    tool_messages = [m for m in result["messages"] if isinstance(m, ToolMessage)]
    assert tool_messages, "ToolMessages from the executor should appear in message history"
    assert tool_messages[0].content == "campaigns, daily_metrics"


# ---------------------------------------------------------------------------
# Test: deny (do not resume) — checkpoint stays at interrupt
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_checkpoint_stays_interrupted_when_not_resumed(graph_with_stubs):
    config = _config()

    await graph_with_stubs.ainvoke(
        {"messages": [HumanMessage(content="List all tables")]},
        config=config,
    )

    # Simulate user denying — do NOT call ainvoke(None, ...)
    state = await graph_with_stubs.aget_state(config)
    assert state.next == ("tool_executor",), (
        "Checkpoint must remain at interrupt if user does not resume"
    )


# ---------------------------------------------------------------------------
# Test: API endpoint — /resume with action="deny" returns cancelled
# ---------------------------------------------------------------------------


def test_resume_deny_returns_cancelled():
    """The /resume endpoint with action='deny' must return immediately without streaming."""
    from fastapi.testclient import TestClient
    from marketing_agent.api.app import app

    # Patch the singleton graph so the endpoint doesn't hit real infra
    mock_graph = MagicMock()
    mock_graph.aget_state = AsyncMock(return_value=MagicMock(next=()))

    with patch("marketing_agent.api.routes.chat._graph", mock_graph):
        client = TestClient(app)
        response = client.post(
            "/api/resume",
            json={"thread_id": str(uuid.uuid4()), "action": "deny"},
        )

    assert response.status_code == 200
    assert response.json() == {"status": "cancelled"}


# ---------------------------------------------------------------------------
# Test: API endpoint — /resume with action="approve" streams events
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_resume_approve_returns_streaming_response():
    """The /resume endpoint with action='approve' must return a streaming SSE response."""
    import json
    from httpx import AsyncClient, ASGITransport
    from marketing_agent.api.app import app

    async def _fake_astream_events(input, config, version):
        # Yield nothing — simulates a graph that completes immediately
        return
        yield  # make it an async generator

    mock_graph = MagicMock()
    mock_graph.astream_events = _fake_astream_events
    mock_graph.aget_state = AsyncMock(return_value=MagicMock(next=()))

    with patch("marketing_agent.api.routes.chat._graph", mock_graph):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                "/api/resume",
                json={"thread_id": str(uuid.uuid4()), "action": "approve"},
            )

    assert response.status_code == 200
    assert "text/event-stream" in response.headers["content-type"]

    # The stream should end with a 'done' event
    lines = [line for line in response.text.splitlines() if line.startswith("data:")]
    last_event = json.loads(lines[-1].removeprefix("data: "))
    assert last_event["type"] == "done"
