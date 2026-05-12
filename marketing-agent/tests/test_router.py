"""Tests for improvement 4: router Literal return type and routing logic."""

import pytest
from langchain_core.messages import AIMessage, HumanMessage
from langgraph.graph import END

from marketing_agent.graph.nodes.router import router, TOOL_EXECUTOR
from marketing_agent.models.state import AgentState


def _state(*messages) -> AgentState:
    return {"messages": list(messages)}


def _tool_call(name: str = "list_tables", call_id: str = "call_1") -> dict:
    return {"id": call_id, "name": name, "args": {}, "type": "tool_call"}


# --- routing decisions ---


def test_routes_to_tool_executor_when_tool_calls_present():
    state = _state(AIMessage(content="", tool_calls=[_tool_call()]))
    assert router(state) == TOOL_EXECUTOR


def test_routes_to_end_when_no_tool_calls():
    state = _state(AIMessage(content="Here is your answer."))
    assert router(state) == END


def test_routes_to_end_when_tool_calls_is_empty_list():
    state = _state(AIMessage(content="Done.", tool_calls=[]))
    assert router(state) == END


# --- return value matches the Literal contract ---


def test_tool_executor_return_value_is_correct_string():
    state = _state(AIMessage(content="", tool_calls=[_tool_call()]))
    assert router(state) == "tool_executor"


def test_end_return_value_is_langgraph_end_sentinel():
    # END == "__end__" in LangGraph — the Literal annotation documents this
    state = _state(AIMessage(content="Done."))
    assert router(state) == "__end__"


# --- reads only the last message ---


def test_router_reads_last_message_not_first():
    # First message has tool calls, last message does not → should go to END
    state = _state(
        AIMessage(content="", tool_calls=[_tool_call("list_tables", "call_1")]),
        AIMessage(content="Final answer."),
    )
    assert router(state) == END


def test_router_reads_last_message_with_tool_calls():
    # First message is plain, last message has tool calls → should go to tool_executor
    state = _state(
        AIMessage(content="Thinking..."),
        AIMessage(content="", tool_calls=[_tool_call()]),
    )
    assert router(state) == TOOL_EXECUTOR


# --- non-AI messages are handled gracefully ---


def test_human_message_has_no_tool_calls_routes_to_end():
    state = _state(HumanMessage(content="What are my top campaigns?"))
    assert router(state) == END
