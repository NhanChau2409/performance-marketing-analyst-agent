"""CLI entry point — chat with the agent in your terminal."""

import asyncio
import uuid

from langchain_core.messages import HumanMessage

from marketing_agent.graph.graph import build_graph


async def main():
    """Simple REPL (Read-Eval-Print Loop) for chatting with the agent."""
    graph = build_graph()

    # Each conversation gets a unique thread_id for checkpointing
    thread_id = str(uuid.uuid4())
    config = {"configurable": {"thread_id": thread_id}}

    print("Marketing Analytics Agent")
    print("Type 'quit' to exit, 'new' for a new conversation.\n")

    while True:
        user_input = input("You: ").strip()

        if not user_input:
            continue
        if user_input.lower() == "quit":
            break
        if user_input.lower() == "new":
            thread_id = str(uuid.uuid4())
            config = {"configurable": {"thread_id": thread_id}}
            print("--- New conversation ---\n")
            continue

        # Invoke the graph with the user's message
        result = await graph.ainvoke(
            {"messages": [HumanMessage(content=user_input)]},
            config=config,
        )

        # Check whether the graph paused at an interrupt_before checkpoint
        state = await graph.aget_state(config)
        while state.next:
            # Graph is paused before tool_executor — show pending tool calls
            last_msg = state.values["messages"][-1]
            tool_names = [tc["name"] for tc in last_msg.tool_calls]
            print(f"\n[Interrupt] Agent wants to call: {', '.join(tool_names)}")
            confirm = input("Allow tool execution? (y/n): ").strip().lower()

            if confirm == "y":
                result = await graph.ainvoke(None, config=config)
                state = await graph.aget_state(config)
            else:
                print("Tool execution cancelled. Starting a new turn.")
                break

        if not state.next:
            # Graph ran to completion — print the final answer
            agent_message = result["messages"][-1]
            print(f"\nAgent: {agent_message.content}\n")


if __name__ == "__main__":
    asyncio.run(main())
