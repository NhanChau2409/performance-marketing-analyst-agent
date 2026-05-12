# LangGraph Guide — Building a Marketing Analytics Agent

This guide teaches you how to build an AI agent using LangGraph, step by step. By the end,
you will understand how our marketing analytics agent works: a ReAct agent that queries
marketing data, runs analysis, and generates any output format (charts, Excel, PDF) —
all driven by an LLM deciding what to do next.

We assume you know Python but have never worked with LLM frameworks, agents, or LangGraph.
Every concept is introduced before it is used.

---

## 1. What Is an AI Agent?

Before we build anything, we need to understand what an "agent" actually is — and how it
differs from things you may have already seen.

### Three levels of LLM applications

**Chatbot (stateless Q&A):**
You send a question, you get an answer. No memory, no tools, no follow-up. Think of a
simple ChatGPT wrapper that answers "What is ROAS?" and forgets you asked.

**Pipeline (fixed steps):**
A hardcoded sequence: fetch data → summarize → format as PDF. The steps never change.
If the data looks weird, the pipeline doesn't adapt — it just runs the same steps every time.

**Agent (autonomous decision-making loop):**
An LLM that decides *what to do next* based on what it has learned so far. It can use tools,
inspect results, change course, and decide when it has enough information to answer.

### Why agents matter for marketing analytics

Imagine a user asks:

> "Generate a weekly performance report for all platforms."

A pipeline would run the same 5 queries every time. But what if LinkedIn had no spend this
week? What if Meta's data is missing? What if ROAS dropped and needs investigation?

An agent handles this naturally:

1. It queries the data
2. It notices Meta has no data — it flags this instead of crashing
3. It sees ROAS dropped on Google — it decides to dig deeper
4. It generates charts for the platforms that have data
5. It writes a summary that mentions the missing data and the ROAS anomaly

Nobody hardcoded steps 2–5. The LLM figured out those steps were needed.

### The key insight

> **An agent is an LLM in a loop that can use tools and decide when to stop.**

That's it. The loop gives it the ability to take multiple steps. The tools give it the
ability to interact with the real world (databases, files, APIs). The LLM's reasoning
ability lets it decide which tools to call, in what order, and when the job is done.

---

## 2. The ReAct Pattern

Now that we know what an agent is, let's look at the specific pattern our agent uses:
**ReAct** (Reason + Act).

### The idea

ReAct comes from a 2022 research paper that showed LLMs perform better when they alternate
between *thinking* and *acting*, rather than trying to do everything in one shot. The name
is a portmanteau: **Rea**son + **Act** = **ReAct**.

### The loop

```
┌──────────┐
│  Thought  │  ← LLM reasons about what to do next
└─────┬─────┘
      ▼
┌──────────┐
│  Action   │  ← LLM requests a tool call
└─────┬─────┘
      ▼
┌──────────┐
│Observation│  ← Tool returns real data
└─────┬─────┘
      ▼
┌──────────┐
│  Thought  │  ← LLM reasons about the result
└─────┬─────┘
      ▼
  ... repeat until the LLM has enough info ...
      ▼
┌──────────────┐
│ Final Answer  │
└──────────────┘
```

The LLM keeps looping — think, act, observe — until it decides it has enough information
to give a final answer. There is no hardcoded number of iterations.

### A concrete marketing example

Let's walk through a real scenario, step by step.

**User:** "Why did our ROAS drop last week?"

**Thought 1:** I need to check weekly ROAS trends to confirm the drop and see how bad it is.

**Action 1:**
```
query_data(sql="SELECT week, ROUND(AVG(roas), 2) as avg_roas
                FROM daily_metrics
                GROUP BY week
                ORDER BY week DESC
                LIMIT 4")
```

**Observation 1:** Results:
| week     | avg_roas |
|----------|----------|
| 2026-W13 | 2.9      |
| 2026-W12 | 3.4      |
| 2026-W11 | 3.1      |
| 2026-W10 | 3.2      |

**Thought 2:** Confirmed — ROAS dropped from 3.4 to 2.9 (a 15% decline). I need to find
which platform caused the drop.

**Action 2:**
```
query_data(sql="SELECT platform, ROUND(AVG(roas), 2) as avg_roas
                FROM daily_metrics
                WHERE week = '2026-W13'
                GROUP BY platform")
```

**Observation 2:**
| platform | avg_roas |
|----------|----------|
| Google   | 3.5      |
| Meta     | 1.8      |
| LinkedIn | 2.7      |

**Thought 3:** Meta's ROAS is 1.8 — much lower than the others. I should check what
changed on Meta specifically. Let me compare Meta's spend and conversions.

**Action 3:**
```
query_data(sql="SELECT week, SUM(spend) as spend, SUM(conversions) as conversions
                FROM daily_metrics
                WHERE platform = 'Meta'
                AND week IN ('2026-W12', '2026-W13')
                GROUP BY week")
```

**Observation 3:**
| week     | spend  | conversions |
|----------|--------|-------------|
| 2026-W12 | 12,000 | 408         |
| 2026-W13 | 18,500 | 333         |

**Thought 4:** Meta's spend increased by 54% but conversions dropped by 18%. That explains
the ROAS collapse — they scaled spend into poorly performing audiences. I now have enough
information to answer.

**Final Answer:** "Your ROAS dropped from 3.4 to 2.9 last week, a 15% decline driven
almost entirely by Meta. Meta's spend increased 54% (from $12K to $18.5K) while
conversions fell 18%. This suggests the budget scaled into lower-quality audiences.
Recommendation: audit Meta's audience targeting and consider rolling back the spend
increase."

### What just happened?

- The **LLM** did all the reasoning (which queries to run, how to interpret results)
- The **tools** provided real data (SQL queries against the marketing database)
- The **loop** allowed multiple steps (4 rounds of think-act-observe)
- The **LLM decided when to stop** (after it had enough evidence to explain the drop)

No one programmed those 4 steps. A different question would produce different steps. That's
the power of the ReAct pattern.

---

## 3. LangGraph Fundamentals

We now know *what* an agent is (Section 1) and *how* it reasons (Section 2). But how do we
actually build one in Python? That's where **LangGraph** comes in.

### What is LangGraph?

LangGraph is a Python framework for building agents as **state machines** (also called
**graphs**). You define:

- **State**: the data that flows through the agent
- **Nodes**: functions that read state, do work, and update state
- **Edges**: connections between nodes (including conditional routing)

LangGraph handles the rest: running the loop, managing state, saving checkpoints,
streaming progress, and recovering from errors.

### Why not just write a while loop?

You *could* build a ReAct agent with a raw while loop:

```python
# Naive approach (don't do this in production)
while True:
    response = llm.invoke(messages)
    if response.tool_calls:
        for call in response.tool_calls:
            result = execute_tool(call)
            messages.append(result)
    else:
        break  # done
```

This works for a demo, but falls apart in production:

| Problem | While loop | LangGraph |
|---------|-----------|-----------|
| Save/resume conversation | You build it | Built-in checkpointing |
| Stream progress to UI | You build it | Built-in streaming |
| Error recovery mid-loop | You build it | Checkpoint + retry |
| Visualize the graph | Not possible | Built-in visualization |
| Add parallel subagents | Painful | First-class support |
| Debug what happened | Print statements | Event trace |

LangGraph handles the boring infrastructure so you can focus on the interesting parts:
what tools to build and how to prompt the LLM.

### 3.1 State

State is the **shared whiteboard** that all parts of the agent can read from and write to.
It's a Python `TypedDict` — just a dictionary with typed keys.

```python
from typing import TypedDict, Annotated
from langgraph.graph import add_messages
from langchain_core.messages import BaseMessage

class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], add_messages]  # conversation history
    next_action: str | None                                # routing hint
```

Two things to notice:

**`messages`** — This is the conversation history: every human message, every LLM response,
every tool result. This is how the LLM "remembers" what happened earlier in the loop.

**`Annotated[..., add_messages]`** — This is a **reducer**. When a node returns
`{"messages": [new_msg]}`, LangGraph doesn't *replace* the messages list — it *appends*
to it. The `add_messages` reducer handles this automatically. Without it, each node would
overwrite the entire conversation history.

Think of it this way:
- Without reducer: `state["messages"] = new_value` (replaces everything)
- With `add_messages`: `state["messages"].extend(new_value)` (appends)

**`next_action`** — A simple string we use for routing. The LLM node sets it to `"tools"`
when it wants to call a tool, or `None` when it's done. The router reads this to decide
which node runs next.

### 3.2 Nodes

Nodes are **Python functions** that take the current state, do some work, and return a
dictionary of state updates. Think of each node as a worker standing at the whiteboard:
it reads what's there, does its job, and writes its results back.

Here's the most important node — the one that calls the LLM:

```python
async def lead_agent(state: AgentState) -> dict:
    """The thinking node — calls the LLM and decides what to do next."""
    messages = state["messages"]           # read the conversation so far
    response = await llm.ainvoke(messages)  # ask the LLM what to do

    # Did the LLM request tool calls?
    if response.tool_calls:
        return {
            "messages": [response],      # add LLM's response to history
            "next_action": "tools"       # tell the router: run the tools next
        }
    else:
        return {
            "messages": [response],      # add LLM's final answer
            "next_action": "respond"     # tell the router: we're done
        }
```

Notice:
- The function is `async` — LLM calls are I/O-bound, so we use async/await
- It returns a `dict`, not a full `AgentState` — LangGraph merges these updates into state
- The `add_messages` reducer means `[response]` gets *appended* to the existing messages

### 3.3 Edges and Routing

Edges connect nodes together. There are two kinds:

**Normal edges** — always go from A to B:
```python
graph.add_edge("tool_executor", "lead_agent")  # after tools run, always go back to LLM
```

**Conditional edges** — go to different nodes based on state (like a traffic light that
reads the traffic and decides which lane gets green):

```python
def router(state: AgentState) -> str:
    """Decide where to go next based on what the LLM decided."""
    if state["next_action"] == "tools":
        return "tool_executor"   # LLM wants to call tools → go to tool node
    return END                   # LLM is done → end the graph
```

The router is a pure function — it just reads state and returns a string. LangGraph uses
that string to pick the next node.

### 3.4 Building the Graph

Now we wire everything together:

```python
from langgraph.graph import StateGraph, END

# 1. Create a graph with our state type
graph = StateGraph(AgentState)

# 2. Add nodes (the workers)
graph.add_node("lead_agent", lead_agent)
graph.add_node("tool_executor", tool_executor)

# 3. Set the starting point
graph.set_entry_point("lead_agent")

# 4. Add edges (the connections)
graph.add_conditional_edges(
    "lead_agent",       # from this node...
    router,             # use this function to decide...
    {
        "tool_executor": "tool_executor",  # if router returns "tool_executor" → go there
        END: END                           # if router returns END → stop
    }
)
graph.add_edge("tool_executor", "lead_agent")  # after tools → back to LLM (the loop!)

# 5. Compile into a runnable application
app = graph.compile()
```

Here's what that graph looks like:

```
               ┌─────────────────┐
               │      START      │
               └────────┬────────┘
                        ▼
               ┌─────────────────┐
        ┌─────→│   lead_agent    │
        │      │  (calls LLM)    │
        │      └────────┬────────┘
        │               ▼
        │      ┌─────────────────┐
        │      │     router      │
        │      └───┬─────────┬───┘
        │          │         │
        │   tools? │         │ done?
        │          ▼         ▼
        │  ┌──────────┐  ┌──────┐
        │  │  tool_    │  │ END  │
        └──│ executor  │  └──────┘
           └──────────┘
```

That loop — `lead_agent → router → tool_executor → lead_agent` — is the ReAct pattern
from Section 2, implemented as a graph. The LLM keeps looping through tools until it
decides it's done, at which point the router sends it to END.

---

## 4. Tool Calling — How the LLM Uses Tools

We've referenced "tools" many times. Let's now understand exactly how they work.

### The key mental model

The LLM **does not execute code**. It has no access to your database, your filesystem, or
the internet. Instead, it outputs a structured request: "please call this function with
these arguments." The framework (LangGraph) executes the function and feeds the result back
to the LLM.

It's like a manager (LLM) telling an assistant (framework) what to do:
- Manager: "Run this SQL query and tell me the results."
- Assistant: *runs the query, brings back the data*
- Manager: "Now make a bar chart from those results."
- Assistant: *makes the chart, reports back*

The manager never touches the database or the charting library directly.

### Defining a tool

A tool is a Python function decorated with `@tool`. The **docstring is critical** — it's
the description the LLM reads to decide when and how to use the tool. Writing good tool
descriptions is prompt engineering.

```python
from langchain_core.tools import tool

@tool
def query_data(sql: str, save_as: str = "results.csv") -> str:
    """Execute a read-only SQL query against the marketing database.

    Use this to fetch campaign metrics, daily performance data, platform
    breakdowns, and any other data from the marketing_data schema.
    Results are saved to the sandbox filesystem at the given path.
    Returns a text summary of the results (row count, column names, sample rows).

    Args:
        sql: A read-only SQL query (SELECT only, no INSERT/UPDATE/DELETE).
        save_as: Filename to save results to. Defaults to "results.csv".
    """
    # ... implementation that runs the query and returns a summary string
```

```python
@tool
def python_exec(code: str) -> str:
    """Execute Python code in the sandbox environment.

    The sandbox has pandas, matplotlib, openpyxl, weasyprint, and other
    common libraries pre-installed. Use this for ANY computation: analysis,
    chart generation, Excel export, PDF creation, data transformation, etc.

    The agent writes the Python code directly — no need for specialized
    export tools when the sandbox has all libraries installed.

    Args:
        code: Python code to execute. Can read/write files in the sandbox.
              Use matplotlib for charts, openpyxl for Excel, weasyprint for PDF.
    """
    # ... implementation that executes the code in a sandboxed environment
```

Notice: the docstrings explain **when** to use the tool, **what** it does, and **what the
arguments mean**. The LLM reads these to make decisions. If the docstring is vague, the LLM
will misuse the tool.

> **Design philosophy: smart agent, simple tools.** We use only 4 generic tools (query_data,
> list_tables, describe_table, python_exec). The agent uses `python_exec` with
> `open()`/`os.listdir()`/`pd.read_csv()` for file operations, and writes
> matplotlib/openpyxl/weasyprint code itself — no convenience wrappers. This keeps
> the tool surface small and lets the LLM's coding ability handle the complexity.

### Binding tools to the LLM

Before the LLM can call tools, it needs to know they exist:

```python
tools = [query_data, list_tables, describe_table, python_exec]

# bind_tools tells the LLM about available tools
# The LLM will now include tool_calls in its responses when appropriate
llm_with_tools = llm.bind_tools(tools)
```

After binding, when the LLM decides it needs data, it won't try to make up an answer — it
will output a structured tool call request instead.

### Executing tool calls

When the LLM responds with tool calls, someone needs to actually run them. LangGraph
provides `ToolNode` for this, but let's first see the manual version to understand what's
happening:

```python
from langchain_core.messages import ToolMessage

async def tool_executor(state: AgentState) -> dict:
    """Execute whatever tools the LLM requested."""
    last_message = state["messages"][-1]  # the AIMessage with tool_calls
    results = []

    for tool_call in last_message.tool_calls:
        # Look up the tool function by name
        tool_fn = tool_map[tool_call["name"]]  # e.g., {"query_data": query_data, ...}

        # Run it with the arguments the LLM provided
        result = await tool_fn.ainvoke(tool_call["args"])

        # Wrap the result in a ToolMessage so the LLM can read it
        results.append(ToolMessage(
            content=result,               # the string the tool returned
            tool_call_id=tool_call["id"]  # links this result to the request
        ))

    return {"messages": results}  # add all results to conversation history
```

Or, using LangGraph's built-in shortcut:

```python
from langgraph.prebuilt import ToolNode

# This does the same thing as the manual version above
tool_executor = ToolNode(tools)
```

### The message flow

Here's the complete flow of messages during one cycle of the ReAct loop:

```
1. HumanMessage("Why did ROAS drop?")
       ↓
2. AIMessage(
       content="",                          ← LLM produces no text...
       tool_calls=[{                        ← ...instead requests a tool call
           "name": "query_data",
           "args": {"sql": "SELECT ..."},
           "id": "call_abc123"
       }]
   )
       ↓
3. ToolMessage(
       content="4 rows returned: ...",      ← tool result
       tool_call_id="call_abc123"           ← matches the request
   )
       ↓
4. AIMessage(
       content="Your ROAS dropped..."       ← final answer (no tool_calls)
   )
```

Steps 2–3 can repeat many times before the LLM reaches step 4. Each iteration adds
messages to the conversation, building up context the LLM uses to reason about what to do
next.

---

## 5. Checkpointing — Saving and Resuming State

So far, our agent works in a single run: the user asks a question, the agent loops through
tools, and returns an answer. But what about *conversations* — multi-turn interactions
where the user asks follow-up questions?

### The problem

Without checkpointing, when the user sends a second message, the agent starts fresh with
an empty state. It has no memory of the first exchange.

### What checkpointing does

After each node runs, LangGraph saves the entire state (all messages, all state fields)
to storage. When a new message arrives for the same conversation, LangGraph loads the saved
state and continues from where it left off.

Think of it like a save game: every node is an auto-save point, and `thread_id` is the
name of your save file.

### Setting it up

For development, use in-memory storage (fast, but lost when the process restarts):

```python
from langgraph.checkpoint.memory import MemorySaver

checkpointer = MemorySaver()
app = graph.compile(checkpointer=checkpointer)
```

For production, use PostgreSQL (persistent across restarts and deployments):

```python
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver

# Uses the same database as your application
async with AsyncPostgresSaver.from_conn_string(database_url) as checkpointer:
    await checkpointer.setup()  # creates the checkpoint tables
    app = graph.compile(checkpointer=checkpointer)
```

### Using thread IDs

Every conversation gets a unique `thread_id`. This is how LangGraph knows which saved
state to load:

```python
from langchain_core.messages import HumanMessage

# First message — creates a new conversation
config = {"configurable": {"thread_id": "user-session-123"}}
result = await app.ainvoke(
    {"messages": [HumanMessage("What was our total spend last month?")]},
    config
)

# Follow-up message — LangGraph loads the saved state automatically
result = await app.ainvoke(
    {"messages": [HumanMessage("Break that down by platform")]},
    config  # same thread_id → same conversation
)
```

The second call doesn't need to repeat the first question. The agent has the full
conversation history from the checkpoint and knows what "that" refers to.

### Why this matters

- **Multi-turn conversations**: users ask follow-ups naturally
- **Error recovery**: if the agent crashes mid-loop, it can resume from the last checkpoint
- **Session persistence**: user can close their browser and come back later

---

## 6. Managing the Context Window

This is the section where theory meets the harsh reality of production. It's the #1
practical challenge you will face building agents.

### The problem

LLMs have a **context window** — a maximum amount of text they can process at once.
Current models support 128K–200K tokens (roughly 100K–150K words). That sounds like a lot,
but marketing data is *big*.

Let's do the math:

```
500 rows of campaign data exported as CSV   ≈ 50,000 tokens
A 4-week daily breakdown across 5 platforms ≈ 30,000 tokens
System prompt + tool descriptions            ≈  3,000 tokens
Previous conversation messages               ≈  5,000 tokens
─────────────────────────────────────────────────────────────
Total for one query cycle                    ≈ 88,000 tokens  ← already 50-70% of context
```

After two or three tool calls, you've blown through your context window. The LLM either
starts forgetting earlier parts of the conversation or refuses to process the request.

### Strategy 1: Sandbox-as-memory (data on disk, summaries in context)

This is the primary strategy for our marketing agent. Instead of putting raw data into the
conversation, we:

1. **Save raw data to files** in a sandbox filesystem
2. **Return only a summary** to the LLM

```
Without sandbox:
  tool returns: "row1: Google, 2026-03-25, $1,234, 45 clicks, 3 conversions, ...
                 row2: Google, 2026-03-26, $1,156, 42 clicks, 2 conversions, ...
                 ... 498 more rows ..."
  → 50,000 tokens consumed

With sandbox:
  tool saves: results.csv (500 rows on disk)
  tool returns: "Saved 500 rows to results.csv. Columns: platform, date, spend,
                 clicks, conversions, roas. Date range: 2026-03-01 to 2026-03-31.
                 Top platform by spend: Google ($38K)."
  → 100 tokens consumed
```

The raw data is still available — the agent can ask other tools to read the file, make
charts from it, or export it to Excel. But the LLM's context only holds the summary.

This 500x reduction in token usage is what makes real-world agents viable.

### Strategy 2: Message compaction

For long conversations, older messages become less relevant. Message compaction summarizes
old messages when the context starts filling up:

```
Before compaction (12 messages, 80K tokens):
  [Human: "What was spend last month?"]
  [AI: tool_call → query_data]
  [Tool: "Saved 500 rows..."]
  [AI: "Total spend was $127K..."]
  [Human: "Break down by platform"]
  [AI: tool_call → query_data]
  [Tool: "Saved results..."]
  [AI: "Google: $52K, Meta: $41K..."]
  ... 4 more exchanges ...

After compaction (4 messages, 5K tokens):
  [System summary: "User asked about last month's spend ($127K total).
   Breakdown: Google $52K, Meta $41K, LinkedIn $19K, TikTok $15K.
   Files created: spend_summary.csv, platform_breakdown.csv"]
  [Human: "Now compare to the previous month"]  ← recent messages kept intact
  [AI: ...]
```

### Strategy 3: Defer tool descriptions

Every tool bound to the LLM adds to context (the function name, description, and parameter
schema). With 30+ tools, that's thousands of tokens before the user even says anything.

The solution: only bind the tools the agent is likely to need for the current task. A
report-generation task doesn't need the "delete file" tool.

### The takeaway

Context management is not glamorous, but it's the difference between a demo that works on
small data and a production agent that handles real marketing datasets. The sandbox-as-memory
pattern is the single most important architectural decision in our agent.

---

## 7. Streaming — Real-Time Updates

### Why streaming matters

Agent work is slow. A single ReAct loop with 3–4 tool calls takes 30–60 seconds. If the
user sees nothing during that time, they'll think the app is broken.

Streaming solves this by sending real-time updates as the agent works:

```
User sees:
  🔧 Querying weekly ROAS data...
  ✅ Got 4 weeks of data
  🔧 Breaking down by platform...
  ✅ Found 4 platforms
  🔧 Investigating Meta spend...
  ✅ Analysis complete
  📝 Your ROAS dropped from 3.4 to 2.9 last week...  ← final answer streams token by token
```

### LangGraph streaming modes

LangGraph provides two streaming approaches:

**`astream_events`** — Fine-grained events: individual tokens, tool start/end, node
transitions. Best for building rich UIs.

**`astream`** — Node-level outputs: you get the full state update after each node completes.
Simpler but less granular.

### Basic streaming example

```python
from langchain_core.messages import HumanMessage

config = {"configurable": {"thread_id": "session-456"}}

async for event in app.astream_events(
    {"messages": [HumanMessage("Generate weekly report")]},
    config=config,
    version="v2"
):
    kind = event["event"]

    if kind == "on_chat_model_stream":
        # Token-by-token LLM output — the final answer streaming in
        token = event["data"]["chunk"].content
        if token:
            print(token, end="", flush=True)

    elif kind == "on_tool_start":
        # A tool is about to run
        tool_name = event["name"]
        print(f"\nCalling: {tool_name}...")

    elif kind == "on_tool_end":
        # A tool finished
        tool_name = event["name"]
        print(f"Done: {tool_name}")

    elif kind == "on_chain_start" and event["name"] == "lead_agent":
        # The LLM node is starting a new thinking cycle
        print("\nThinking...")
```

### Connecting to a web UI via SSE

In production, these events are sent to the browser using **Server-Sent Events (SSE)** —
a simple HTTP protocol where the server pushes messages to the client over a long-lived
connection.

With FastAPI, it looks like this:

```python
from fastapi import FastAPI
from fastapi.responses import StreamingResponse

app_api = FastAPI()

@app_api.post("/api/stream")
async def stream_endpoint(request: StreamRequest):
    async def event_generator():
        async for event in app.astream_events(
            {"messages": [HumanMessage(request.message)]},
            config={"configurable": {"thread_id": request.session_id}},
            version="v2"
        ):
            # Convert LangGraph events to SSE format
            sse_data = convert_to_sse(event)
            if sse_data:
                yield f"data: {sse_data}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")
```

The browser connects to this endpoint and receives events in real time. No WebSockets
needed — SSE is simpler and works over standard HTTP.

---

## 8. Subagents — Multi-Agent Patterns

### When one agent isn't enough

Some tasks are too big or too complex for a single agent loop. Consider:

> "Compare performance across all 5 platforms for the last quarter and create a
> comprehensive report with charts for each."

A single agent would need to:
1. Query data for 5 platforms (5 tool calls, sequential)
2. Analyze each platform (5 thinking steps)
3. Create charts for each (5 more tool calls)
4. Compare across platforms
5. Generate the report

That's 15+ loop iterations, taking minutes. And it's doing the same thing 5 times for
different platforms — a natural candidate for parallelism.

### The pattern: subagents as tools

A **subagent** is just another LangGraph graph, invoked as a tool. The lead agent spawns
subagents to handle subtasks, collects their results, and synthesizes the final answer.

```python
@tool
async def research_agent(prompt: str, platform: str) -> str:
    """Spawn a research subagent to gather and analyze data for a specific platform.

    Use this to parallelize data gathering across platforms. Each subagent
    independently queries data, performs analysis, and returns findings.

    Args:
        prompt: What to research (e.g., "Analyze Q1 performance trends").
        platform: Which platform to focus on (e.g., "Meta", "Google").
    """
    from langchain_core.messages import SystemMessage, HumanMessage

    # Build a separate graph for the subagent (same structure, different tools/prompt)
    sub_graph = build_subagent_graph(tools=[query_data, python_exec])

    result = await sub_graph.ainvoke({
        "messages": [
            SystemMessage(
                f"You are a data research agent specializing in {platform} marketing "
                f"analytics. Gather data and produce a detailed analysis."
            ),
            HumanMessage(prompt)
        ]
    })

    # Return the subagent's final answer as a string
    return result["messages"][-1].content
```

Notice: from the lead agent's perspective, `research_agent` is just another tool. The LLM
doesn't know (or care) that it's a whole separate agent under the hood.

### Foreground vs background execution

**Foreground (blocking):** The lead agent waits for each subagent to finish before
continuing. Simple, but sequential.

```python
# Lead agent calls research_agent for Meta, waits for result,
# then calls research_agent for Google, waits again, etc.
```

**Background (async/parallel):** Multiple subagents run simultaneously. Much faster for
independent tasks.

```python
# Lead agent spawns all 5 platform subagents at once.
# They run in parallel, each querying their own platform data.
# Results come back together, and the lead agent synthesizes.
```

### Marketing example: parallel platform analysis

```
                    ┌─────────────────┐
                    │   lead_agent    │
                    │ "Compare all    │
                    │  platforms"     │
                    └────────┬────────┘
                             │
                    spawns 5 subagents
                             │
            ┌────────┬───────┼───────┬────────┐
            ▼        ▼       ▼       ▼        ▼
        ┌───────┐┌───────┐┌───────┐┌───────┐┌───────┐
        │Google ││ Meta  ││Linked ││TikTok ││Twitter│
        │sub-   ││sub-   ││In sub-││sub-   ││sub-   │
        │agent  ││agent  ││agent  ││agent  ││agent  │
        └───┬───┘└───┬───┘└───┬───┘└───┬───┘└───┬───┘
            │        │       │       │        │
            └────────┴───────┼───────┴────────┘
                             │
                    results collected
                             │
                    ┌────────▼────────┐
                    │   lead_agent    │
                    │ synthesizes     │
                    │ final report    │
                    └─────────────────┘
```

Each subagent independently queries data, analyzes trends, and creates charts for its
platform. The lead agent collects all 5 analyses and writes the final comparative report.
What would take 5+ minutes sequentially can finish in 1–2 minutes with parallelism.

---

## 9. Putting It All Together — The Marketing Agent Graph

Let's combine everything from the previous sections into the complete marketing agent.

### The complete graph

```
                ┌───────────────┐
                │     START     │
                └───────┬───────┘
                        ▼
                ┌───────────────┐
         ┌─────→│  lead_agent   │←────────────────────────┐
         │      │ (LLM decides) │                         │
         │      └───────┬───────┘                         │
         │              ▼                                 │
         │      ┌───────────────┐                         │
         │      │    router     │                         │
         │      └──┬─────────┬──┘                         │
         │         │         │                            │
         │  tools? │         │ done?                      │
         │         ▼         ▼                            │
         │  ┌────────────┐ ┌─────┐                        │
         │  │   tool_    │ │ END │                        │
         │  │  executor  │ └─────┘                        │
         │  └──────┬─────┘                                │
         │         │                                      │
         │         │ executes one or more of:             │
         │         ├── query_data (SQL → CSV + summary)   │
         │         ├── list_tables / describe_table       │
         │         ├── python_exec (analysis, charts,     │
         │         │    Excel, PDF, file I/O — all code)  │
         │         ├── research_agent (subagent)          │
         │         │                                      │
         └─────────┴──────────────────────────────────────┘
                   results added to messages
```

### The complete state

```python
from typing import TypedDict, Annotated
from langgraph.graph import add_messages
from langchain_core.messages import BaseMessage

class MarketingAgentState(TypedDict):
    """State for the marketing analytics agent.

    messages: The full conversation history (human, AI, tool messages).
              Uses add_messages reducer to append rather than replace.
    next_action: Routing hint set by lead_agent, read by router.
    skill_instructions: Optional system-level instructions injected based on
                        the detected task type (e.g., report generation, data
                        exploration). Modifies agent behavior without changing
                        the graph structure.
    """
    messages: Annotated[list[BaseMessage], add_messages]
    next_action: str | None
    skill_instructions: str | None
```

### The complete graph construction

```python
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
from langchain_core.tools import tool
from langgraph.prebuilt import ToolNode

# --- Tools ---
# Smart agent, simple tools — the agent writes Python code directly via python_exec
# for charts (matplotlib), Excel (openpyxl), PDF (weasyprint), and any analysis.
tools = [query_data, list_tables, describe_table, python_exec]
tool_executor = ToolNode(tools)

# --- LLM with tools bound ---
llm_with_tools = llm.bind_tools(tools)

# --- Nodes ---
async def lead_agent(state: MarketingAgentState) -> dict:
    """Call the LLM with the full conversation history and available tools."""
    messages = state["messages"]

    # Inject skill instructions as a system message if present
    if state.get("skill_instructions"):
        from langchain_core.messages import SystemMessage
        messages = [SystemMessage(state["skill_instructions"])] + list(messages)

    response = await llm_with_tools.ainvoke(messages)

    if response.tool_calls:
        return {"messages": [response], "next_action": "tools"}
    else:
        return {"messages": [response], "next_action": "respond"}

def router(state: MarketingAgentState) -> str:
    """Route to tool executor or end, based on what the LLM decided."""
    if state["next_action"] == "tools":
        return "tool_executor"
    return END

# --- Graph ---
graph = StateGraph(MarketingAgentState)

graph.add_node("lead_agent", lead_agent)
graph.add_node("tool_executor", tool_executor)

graph.set_entry_point("lead_agent")
graph.add_conditional_edges("lead_agent", router, {
    "tool_executor": "tool_executor",
    END: END
})
graph.add_edge("tool_executor", "lead_agent")  # the ReAct loop

# --- Compile with checkpointing ---
checkpointer = AsyncPostgresSaver.from_conn_string(database_url)
await checkpointer.setup()
app = graph.compile(checkpointer=checkpointer)
```

### How skills modify behavior

Skills are injected instructions that change how the agent behaves without changing the
graph. For example, when the system detects the user wants a "weekly report," it sets
`skill_instructions` to something like:

```
You are generating a weekly marketing performance report.
Always include: spend by platform, ROAS trends, top/bottom campaigns.
Export the final report as both Excel and PDF.
Use charts for all trend data.
```

The graph stays the same — the LLM just gets different guidance about *what* to do, while
the ReAct loop handles *how* to do it.

---

## 10. Key Takeaways

Here's what we covered, distilled to the essentials:

- **Agent** = LLM + tools + loop + state. The LLM reasons, the tools execute, the loop
  repeats, the state remembers.

- **ReAct** = the specific loop pattern our agent uses. Reason, act, observe, repeat until
  done.

- **LangGraph** = a framework that implements the loop as a state machine (graph). It
  handles state management, checkpointing, streaming, and error recovery so you don't
  have to.

- **Tools** = how the agent interacts with the real world. The LLM outputs structured
  requests; the framework executes them. Tool docstrings are prompt engineering.

- **Checkpointing** = saving state after each step. Enables multi-turn conversations,
  error recovery, and session persistence. Thread IDs identify conversations.

- **Context management** = the #1 practical challenge. The sandbox-as-memory pattern
  (data on disk, summaries in context) is the key architectural decision that makes
  real-world agents viable.

- **Streaming** = sending real-time progress updates to the user via SSE. Essential for
  UX since agent work takes 30–60 seconds.

- **Subagents** = divide-and-conquer for complex tasks. A subagent is just another graph
  invoked as a tool. Enables parallel execution.

---

## Appendix: Further Reading

- **LangGraph documentation**: https://langchain-ai.github.io/langgraph/
  Start with the "Quick Start" tutorial, then read "How-to Guides" for specific patterns.

- **ReAct paper**: *"ReAct: Synergizing Reasoning and Acting in Language Models"*
  (Yao et al., 2022). The original paper that introduced the pattern.
  https://arxiv.org/abs/2210.03629

- **Tool calling**: https://python.langchain.com/docs/concepts/tool_calling/
  How LLMs interact with external functions. Covers the message protocol in detail.

- **LangChain messages guide**: https://python.langchain.com/docs/concepts/messages/
  Understanding `HumanMessage`, `AIMessage`, `ToolMessage`, and `SystemMessage` — the
  building blocks of every LLM conversation.

- **LangGraph checkpointing**: https://langchain-ai.github.io/langgraph/concepts/persistence/
  Deep dive into persistence, thread management, and checkpoint storage backends.

- **LangGraph streaming**: https://langchain-ai.github.io/langgraph/concepts/streaming/
  All streaming modes and how to integrate with web frameworks.
