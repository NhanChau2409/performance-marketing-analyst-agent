"""Execute tool calls requested by the LLM."""

from langchain_core.messages import ToolMessage

from marketing_agent.models.state import AgentState
from marketing_agent.tools.query_data import query_data
from marketing_agent.tools.list_tables import list_tables
from marketing_agent.tools.describe_table import describe_table
from marketing_agent.tools.render_chart import render_chart

# Map tool names to their implementations
TOOL_MAP: dict = {
    "list_tables": list_tables,
    "describe_table": describe_table,
    "query_data": query_data,
    "render_chart": render_chart,
}


async def tool_executor(state: AgentState) -> dict:
    """Execute all tool calls from the LLM's last message.

    For each tool call:
    1. Look up the tool function by name
    2. Call it with the provided arguments
    3. Wrap the result in a ToolMessage (linked by tool_call_id)

    The ToolMessage is critical — it tells the LLM which tool call each result
    belongs to. Without the correct tool_call_id, the LLM cannot match results
    to its requests.
    """
    last_message = state["messages"][-1]
    results = []

    for tool_call in last_message.tool_calls:
        tool_name = tool_call["name"]
        tool_args = tool_call["args"]
        tool_call_id = tool_call["id"]

        tool_fn = TOOL_MAP.get(tool_name)
        if tool_fn is None:
            results.append(ToolMessage(
                content=f"ERROR: Unknown tool '{tool_name}'. Available tools: {list(TOOL_MAP.keys())}",
                tool_call_id=tool_call_id,
            ))
            continue

        try:
            result = await tool_fn.ainvoke(tool_args)
            results.append(ToolMessage(
                content=str(result),
                tool_call_id=tool_call_id,
            ))
        except Exception as e:
            results.append(ToolMessage(
                content=f"ERROR executing {tool_name}: {type(e).__name__}: {e}",
                tool_call_id=tool_call_id,
            ))

    return {"messages": results}
