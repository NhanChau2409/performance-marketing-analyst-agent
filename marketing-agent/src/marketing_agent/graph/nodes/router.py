"""Route the graph based on whether the LLM wants to call tools or is done."""

from typing import Literal

from langgraph.graph import END

from marketing_agent.models.state import AgentState

TOOL_EXECUTOR = "tool_executor"


def router(state: AgentState) -> Literal["tool_executor", "__end__"]:
    """Decide the next node based on the LLM's last message.

    If the last message has tool_calls → route to tool_executor.
    If the last message has no tool_calls → route to END (the agent is done).

    This is a pure function: reads state, returns a string. No side effects.
    """
    last_message = state["messages"][-1]

    # AIMessage with tool_calls means the LLM wants to use tools
    if hasattr(last_message, "tool_calls") and last_message.tool_calls:
        return TOOL_EXECUTOR

    # No tool calls means the LLM produced a final text response
    return END
