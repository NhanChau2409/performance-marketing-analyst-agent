"""Agent state — the shared data structure that flows through the graph."""

from typing import Annotated, TypedDict

from langchain_core.messages import BaseMessage
from langgraph.graph import add_messages


class AgentState(TypedDict):
    """The state that every node in the graph can read and write.

    `messages` is the conversation history. The `add_messages` reducer ensures
    new messages are appended (not replaced) when a node returns updates.

    This is intentionally minimal. We add fields as we need them.
    """

    messages: Annotated[list[BaseMessage], add_messages]
