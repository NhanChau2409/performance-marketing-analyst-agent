/** 02.typ — Chapter 2: Background and Related Work
***/

#pdf.attach(
  "02.typ",
  relationship: "source",
  mime-type: "text/vnd.typst",
  description: "The Typst source code for Chapter 2 (Background) of this thesis.",
)

#import "../preamble.typ": *

= Background and related work <background>
This chapter introduces the technical and domain concepts on which the thesis builds.
Section @llms covers large language models and tool calling. Section @agents defines
AI agents and contrasts them with simpler LLM applications. Section @react-pattern
explains the ReAct pattern in detail. Section @langgraph-background introduces the
LangGraph framework. Section @marketing-domain describes the marketing analytics
domain. Section @related-work surveys related systems.

== Large language models and tool calling <llms>
Large language models are neural networks trained on vast corpora of text using the
Transformer architecture @vaswani2017attention. A Transformer processes its input as
a sequence of tokens and uses a self-attention mechanism to model long-range
dependencies. This allows models to learn rich representations of language and to
generalise from examples seen during training to novel prompts.

Modern LLMs such as GPT-4 @brown2020gpt3 and Claude are trained using a combination
of supervised pre-training on text corpora and reinforcement learning from human
feedback (RLHF). The result is a model that can follow complex natural-language
instructions, write code, reason through multi-step problems, and adapt its tone to the
context of a conversation.

=== Tool calling <tool-calling>
Tool calling (sometimes called _function calling_) extends an LLM's capabilities
beyond text generation @openai2023functions. In this paradigm, the model is given a
list of tools — each described by a name, a natural-language description, and a
parameter schema — alongside the user's message. When the model determines that a tool
would help it answer the question, it emits a structured JSON object specifying which
tool to call and what arguments to pass. The surrounding system (not the model) then
executes the tool and returns the result to the model as a new message. The model can
then continue reasoning with the new information or call another tool.

Tool calling transforms an LLM from a text generator into an active participant in a
computation. It is the foundational capability that enables AI agents.

=== Context windows and context management <context-windows>
Every LLM has a fixed _context window_ — the maximum number of tokens it can process
in a single call. Modern models support context windows of 100,000–200,000 tokens, but
practical agent deployments must still manage context carefully for two reasons: cost
(tokens in and out both have per-token prices) and focus (the model attends to all
content in its context; irrelevant content degrades output quality).

A common pitfall in data-analysis agents is loading large query results directly into
the context window. A 500-row SQL result set can easily consume 50,000 tokens — half
the effective context budget of many deployments — without providing the model with
any more actionable information than a five-line summary would. Effective context
management is therefore a first-class design concern, not an afterthought.

== Ai agents <agents>
The term _AI agent_ is used loosely in the literature, but for the purposes of this
thesis an agent is an LLM that operates in a loop, using tools to interact with the
world and deciding autonomously when it has gathered enough information to produce a
final answer. This definition contrasts with two simpler patterns:

*Chatbot (stateless Q&A).* The model receives a question and generates a single
response. There are no tools; no memory persists between turns; the model cannot take
actions. This is the simplest pattern and is appropriate for questions whose answers
can be generated from the model's training data alone.

*Pipeline (fixed steps).* A hardcoded sequence of operations — for example, fetch
data, summarise, format as PDF. The steps do not change based on the results of
earlier steps. Pipelines are predictable and easy to debug but cannot adapt when
the data or the question requires a different sequence of operations.

*Agent (autonomous decision-making loop).* The model decides at each step what to do
next, based on the results of its previous actions. It can take different paths through
a problem depending on what it discovers. If a query returns no data, it can investigate
why and try a different approach. If it discovers an anomaly, it can choose to
investigate further before summarising. This adaptability is what distinguishes an
agent from a pipeline @yao2022react.

The key insight is that an agent is an LLM in a loop that can use tools and decide
when to stop. The loop provides the ability to take multiple steps; the tools provide
the ability to interact with external systems; the model's reasoning ability enables
it to decide which tools to call, in what order, and when the task is complete.

== The react pattern <react-pattern>
The ReAct pattern @yao2022react (Reason + Act) is a specific agent loop design in
which the model alternates between a _reasoning_ step and an _action_ step. The name
is a portmanteau of the two operations:

- *Reason (Thought).* The model generates a short internal monologue describing what
  it has observed, what it still needs to find out, and what it plans to do next.
- *Act (Action).* The model emits a tool call based on its reasoning.
- *Observe (Observation).* The tool runs and returns a result to the model.

The loop repeats until the model decides it has enough information to produce a final
answer, at which point it emits a text response without a tool call.

The ReAct paper showed empirically that alternating between reasoning and acting
improves performance on multi-step question-answering tasks compared to either
chain-of-thought prompting alone @wei2022cot (reasoning without actions) or acting
alone (tool use without explicit reasoning steps). The reasoning step helps the model
plan its next action and catches errors early; the observation step grounds the
model's subsequent reasoning in real data rather than in its (potentially incorrect)
prior beliefs.

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*Step*], [*Description*]),
    [Thought], [Model reasons about current state and next action],
    [Action], [Model emits a tool call with arguments],
    [Observation], [Tool executes; result returned to model],
    [Thought], [Model incorporates observation and plans next step],
    [...], [...],
    [Final Answer], [Model emits a text response (no tool call)],
  ),
  caption: [The ReAct loop: alternating reasoning and acting until a final answer is produced.],
) <tab-react-loop>

== LangGraph <langgraph-background>
LangGraph @langgraph2024 is a Python library for building stateful, multi-step LLM
applications as directed graphs. It provides the infrastructure for the ReAct loop
without prescribing the application logic: the developer defines nodes (functions that
transform the graph state), edges (routing logic that determines which node runs next),
and the graph state itself (a typed dictionary that accumulates information across
steps).

=== State <langgraph-state>
The graph state is a Python `TypedDict` that is passed through every node. In a
conversational agent, the state typically includes the conversation history as a list
of messages. LangGraph automatically appends each new message — whether from the user,
the model, or a tool — to the history, so every node always has access to the full
context of the conversation so far.

=== Nodes <langgraph-nodes>
A node is an ordinary Python function (or coroutine, for async execution) that takes
the current state as input and returns a dictionary of state updates. In a ReAct agent,
the two key nodes are:

- *Lead agent node.* Calls the LLM with the current message history. If the model
  returns a tool call, the tool call is appended to the history. If the model returns
  a text response, that response is the final answer.

- *Tool executor node.* Reads the tool calls from the most recent model message,
  executes each tool, and appends the results as `ToolMessage` objects to the history.

=== Edges and routing <langgraph-edges>
Edges connect nodes and determine the flow of execution. LangGraph supports _conditional
edges_ — routing functions that inspect the current state and return the name of the
next node to run. In a ReAct agent, a single conditional edge after the lead agent node
checks whether the latest model message contains tool calls: if yes, route to the tool
executor; if no, terminate.

=== Checkpointing and memory <langgraph-checkpointing>
LangGraph supports persistent checkpoints: after each step, the entire graph state can
be saved to a database (SQLite or PostgreSQL). This allows a conversation to be resumed
after a process restart, and it enables multi-turn conversations across HTTP requests
where no long-lived process keeps state in memory.

== The marketing analytics domain <marketing-domain>
Marketing analytics concerns the collection, analysis, and reporting of data about the
performance of advertising campaigns. The key entities in a typical marketing data
model are:

- *Campaigns.* A named initiative on a specific platform (Google Ads, Meta, LinkedIn,
  TikTok) with a defined budget, start date, and end date.
- *Ad groups.* Sub-units within a campaign that target a specific audience or keyword
  group.
- *Ads (creatives).* The individual advertisements — text, image, or video — shown
  to users.
- *Daily metrics.* The performance measurements recorded each day for each ad:
  impressions, clicks, spend, conversions, and revenue.

The standard KPIs that analysts track are listed in @tab-kpis. Analysing these metrics
across platforms, time periods, and campaign types — and understanding why they change —
is the core work of a marketing analyst.

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header([*KPI*], [*Definition*], [*Unit*]),
    [Impressions], [Number of times an ad was shown], [count],
    [Clicks],      [Number of times an ad was clicked], [count],
    [CTR],         [$"Clicks" / "Impressions" times 100$], [\%],
    [CPC],         [$"Spend" / "Clicks"$], [\$],
    [Conversions], [Actions completed after clicking], [count],
    [CPA],         [$"Spend" / "Conversions"$], [\$],
    [Revenue],     [Revenue attributed to conversions], [\$],
    [ROAS],        [$"Revenue" / "Spend"$], [×],
  ),
  caption: [Standard marketing KPIs and their definitions.],
) <tab-kpis>

The analytical workflows that recur most often in marketing teams are:
routine performance reports (weekly, monthly, quarterly), campaign-level deep dives,
anomaly investigation ("why did ROAS drop last week?"), budget tracking (planned vs.
actual spend), and cross-platform channel comparisons.

== Related work <related-work>
=== Text-to-sql systems
Translating natural language to SQL has been an active research area since the 1970s.
Recent neural approaches use LLMs fine-tuned on paired (question, SQL) datasets to
generate queries for unseen schemas. Systems such as DIN-SQL and DAIL-SQL achieve high
accuracy on benchmark datasets such as Spider. However, text-to-SQL systems in isolation
produce only a query — not the analysis, visualisation, or narrative summary that a
marketing analyst actually needs. The agent approach in this thesis subsumes
text-to-SQL as one step in a larger reasoning loop.

=== LLM code execution agents
Toolformer @schick2023toolformer demonstrated that LLMs can learn to use tools by
inserting tool calls into their own training data. Code Interpreter (now Advanced Data
Analysis) in ChatGPT is a commercial system that allows users to upload datasets and
have a GPT model analyse them by writing and executing Python code. The present work
differs in domain specificity: the agent has direct access to a live marketing
database and is guided by a domain-specific system prompt and skill templates, rather
than operating on uploaded files.

=== Multi-agent frameworks
MetaGPT @hong2023metagpt and similar frameworks assign different LLM agents to different
roles (product manager, engineer, tester) and let them communicate to solve software
engineering tasks. The multi-agent pattern in this thesis is simpler: a single lead
agent spawns worker subagents for parallel data gathering. The design prioritises
simplicity and reliability over expressiveness; workers communicate only through shared
filesystem artifacts, not through natural-language messages.

=== Commercial marketing ai tools
Several vendors offer AI-powered marketing analytics products, including Tableau
Einstein, Google Looker with Gemini, and Meta Advantage+. These systems are integrated
tightly with their platforms and offer limited extensibility. The open, composable
architecture in this thesis — where any database, any LLM provider, and any output
format can be substituted — is specifically designed to avoid vendor lock-in and to
serve as a research and learning platform.
