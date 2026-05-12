"""Build the ReAct agent graph — LLM with tools in a loop."""

from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver

from marketing_agent.models.state import AgentState
from marketing_agent.graph.nodes.lead_agent import lead_agent
from marketing_agent.graph.nodes.router import router, TOOL_EXECUTOR
from marketing_agent.graph.nodes.tool_executor import tool_executor


def build_graph():
    """Construct the ReAct agent graph.

    The graph looks like this:

        START → lead_agent → router → tool_executor → lead_agent → ... → END

    The lead_agent ↔ tool_executor loop repeats until the LLM produces a final
    text answer (no tool_calls), at which point the router sends it to END.
    """
    graph = StateGraph(AgentState)

    # Add all nodes
    graph.add_node("lead_agent", lead_agent)
    graph.add_node("tool_executor", tool_executor)

    # Entry point
    graph.set_entry_point("lead_agent")

    # Conditional edge: after lead_agent, the router decides what's next.
    # The explicit map makes every branch visible without reading router.py.
    graph.add_conditional_edges(
        "lead_agent",
        router,
        {TOOL_EXECUTOR: "tool_executor", END: END},
    )

    # After tools execute, always go back to the LLM
    graph.add_edge("tool_executor", "lead_agent")

    checkpointer = MemorySaver()
    return graph.compile(checkpointer=checkpointer)
