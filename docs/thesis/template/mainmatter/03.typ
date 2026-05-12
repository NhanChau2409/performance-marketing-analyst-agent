/** 03.typ — Chapter 3: System Architecture and Design
***/

#pdf.attach(
  "03.typ",
  relationship: "source",
  mime-type: "text/vnd.typst",
  description: "The Typst source code for Chapter 3 (Architecture and Design) of this thesis.",
)

#import "../preamble.typ": *

= System architecture and design <architecture>
This chapter presents the overall architecture of the marketing analytics agent and
explains the design decisions that shape it. Section @system-overview gives the
high-level structure. Sections @smart-agent-philosophy through @prompt-architecture
then describe four key design contributions: the smart-agent philosophy, tool
design, multi-agent orchestration, and the skills system.

== System overview <system-overview>
The system consists of four layers, as shown in @tab-layers:

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*Layer*], [*Responsibility*]),
    [API layer],   [Accepts user messages via HTTP; returns the final response],
    [Agent layer], [Runs the LangGraph ReAct graph; manages conversation state],
    [Tool layer],  [Three tools: schema discovery and SQL execution],
    [Data layer],  [PostgreSQL marketing database, accessed read-only],
  ),
  caption: [The four layers of the marketing analytics agent system.],
) <tab-layers>

At runtime, a user sends a message to the FastAPI endpoint. The endpoint invokes the
LangGraph graph with the current conversation state. The graph runs the ReAct loop:
the lead agent node calls the LLM, the router inspects the response, and if the model
has requested a tool call the tool executor node runs it. Tool results are appended to
the conversation history and the loop continues until the model emits a final text
response, which is returned to the caller.

== Smart agent, simple tools <smart-agent-philosophy>
The most consequential architectural decision in this system is the choice to use
_three_ tools instead of a larger library of specialised tools. Many agent systems grow
a tool for every distinct task: one tool per output format, one tool per data source,
one tool per report type. This thesis takes the opposite approach: only add a tool
when it crosses a boundary that the model cannot cross on its own.

The three tools in this system are:

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Tool*], [*Category*], [*Purpose*]),
    [`list_tables`],    [Schema], [List all database tables with row counts],
    [`describe_table`], [Schema], [Show schema, sample rows, and value distributions for one table],
    [`query_data`],     [Data],   [Execute a read-only SQL query; return results to the model],
  ),
  caption: [The three tools available to the agent.],
) <tab-four-tools>

The model cannot query the database on its own — hence `query_data` and the two schema
tools. Beyond these boundary-crossing operations, the model can reason about the
results, format summaries, and produce analysis narratives directly in its response.

This minimal design has two key advantages. First, fewer tools means fewer decision
points for the model, which reduces latency and increases reliability. Second, the tool
surface is narrow enough to reason about exhaustively in the system prompt, ensuring
the model understands the constraints and usage patterns of each tool completely.

== Tool design <tool-design>
Good tool design has two components that are equally important: the implementation
and the description. The implementation determines what the tool actually does; the
description determines when and how the model calls it.

=== Tool descriptions as prompt engineering <tool-descriptions>
A tool's natural-language description is read by the model on every turn. It
answers three questions: what does this tool do, when should I use it, and what should
I expect back? An imprecise description leads to wrong tool choices, incorrect
arguments, and wasted tool calls.

The following principles govern the descriptions in this system:

*Positive framing.* Describe what the tool _does_, not what it does not do.
Negative instructions prime the model to think about the forbidden action. Positive
instructions focus attention on available capabilities.

*Embedded constraints.* Include usage rules directly in the description:
"`list_tables` first before writing any SQL query." This creates a behavioural chain
without requiring the system prompt to enumerate every possible error.

*Concrete examples.* A single example in the description — a sample SQL query, a
sample column name — is more reliable than an abstract rule. The model applies
the example as a template.

*Error messages as instructions.* When a tool fails, the error message is the only
information the model has for self-correction. Good error messages state what happened,
what the model probably meant to do, and how to fix it.

=== Schema discovery flow <schema-discovery-flow>
The two schema tools serve different stages of discovery. `list_tables` gives a broad
overview: table names and row counts. `describe_table` gives a deep view of one table:
column names, types, nullability, and sample rows. Using both before writing SQL
eliminates the most common agent error — hallucinating column names — without
burdening the system prompt with the full schema of every table.

== Multi-agent orchestration <multi-agent>
Some marketing analyses require gathering data from multiple independent sources in
parallel. For example, a cross-platform comparison of Google Ads versus Meta for Q1
requires two separate SQL queries (one per platform), which can be run simultaneously
rather than sequentially.

The system supports this through a `research_agent` tool available only to the lead
agent. When the lead agent calls this tool with a list of tasks, each task is executed
as an independent subagent — a complete LangGraph ReAct graph — running in its own
asyncio coroutine. The coroutines are launched concurrently with `asyncio.gather()`.

=== Communication through returned results <subagent-communication>
Subagents communicate with the lead agent by returning their query results as structured
text in their final response. Each subagent queries the database, formats the results
as a Markdown table, and returns a concise summary. When all subagents complete,
`asyncio.gather()` collects their responses and the lead agent synthesises them into
a unified analysis.

This design keeps inter-agent communication simple: results flow as text, requiring no
shared storage or additional coordination overhead.

=== Subagent constraints <subagent-constraints>
Subagents have a restricted tool set: they can use the schema tools and `query_data`,
but they cannot call `research_agent`. This prevents recursive agent spawning. Subagents
are given a lean system prompt that instructs them to fetch the requested data and return
a structured summary — the lead agent is responsible for the final synthesis.

== Skills: structured workflow templates <skills>
The ReAct loop is flexible but unpredictable for complex, multi-step workflows. When a
user requests a weekly performance report, the agent must issue multiple queries,
compute week-over-week changes, and produce a structured written report — in the right
order, with consistent formatting. Without guidance, the model may skip steps or produce
inconsistent output.

Skills solve this problem without adding new tools or fine-tuning the model.

=== Skill structure <skill-structure>
A skill is a Markdown file with a structured header that specifies:

- The trigger (e.g., `/weekly-report`).
- The data required (table names, date ranges).
- A numbered sequence of steps the agent must follow.
- Output format specifications (section headings, table structure, summary format).

When a user triggers a skill — either by typing a slash command or by asking a
question that the agent recognises as matching a skill — the skill's instructions are
injected into the session context (Part 2 of the system prompt, described in the next
section). The model then follows the skill instructions as a recipe.

=== Why skills work <why-skills-work>
The key observation is that skills provide _structured instructions_ for the model to
follow, not _new capabilities_. The model already knows how to use the three tools; the
skill tells it exactly which tools to call, in what order, with what arguments, and
what the output should look like. This is analogous to giving a skilled chef a recipe:
the chef already knows how to cook, but the recipe ensures consistency and completeness.

The distinction between skills and tools is important. A tool extends what the agent
can _do_. A skill extends what the agent _reliably does_ for a specific workflow.
Adding a new analytical capability can often be achieved by writing a new skill rather
than building a new tool — a substantially lower development cost.

== System prompt architecture <prompt-architecture>
The system prompt is constructed in three parts, assembled dynamically at the start of
each turn:

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Part*], [*Tokens*], [*Content*]),
    [Static prompt],   [~2,000], [Identity, tools, output standards, workflow patterns, guardrails],
    [Session context], [200–500], [Today's date, table summary, active skill (if any)],
    [Conversation],    [grows],   [Full message history managed by LangGraph],
  ),
  caption: [The three-part system prompt structure.],
) <tab-prompt-parts>

The static prompt is loaded once and cached. It establishes the agent's identity
("you are a marketing analytics agent"), documents the three tools, specifies output
formatting standards (currency as \$1,234.56, rates as 12.4\%, ROAS as 3.2×), and
provides workflow pattern templates for the most common request types.

The session context is assembled fresh on each turn. It injects the current date (so
the model can compute date ranges correctly), a summary of available database tables
(so the model does not need to call `list_tables` every session), and the active skill
instructions if a skill was triggered.

The conversation history is managed by LangGraph's built-in message accumulation.
When the history grows large, LangGraph applies a trimming strategy that removes old
tool messages while preserving the user/assistant turns, keeping the total token count
within budget.

=== Prompt design principles <prompt-design-principles>
Six principles govern the design of the static system prompt, derived from iterative
testing:

+ *Positive framing.* State what the agent has and can do, not what it lacks.
+ *Explain why, not just what.* "Do not print entire dataframes — a 500-row dataset
  is ~50,000 tokens" is more robust than "do not print dataframes" because the agent
  can apply the principle to novel situations it has not seen.
+ *Concrete examples over abstract rules.* "\$1,234.56 for currency, 3.2× for ROAS"
  leaves no room for interpretation.
+ *Structure for scannability.* The model "reads" the prompt every turn; headers and
  bullet points make the relevant section easy to locate.
+ *Front-load critical instructions.* The model attends more to the beginning of a
  prompt; the most critical guardrails appear early.
+ *Iterate on failures.* Every time the agent makes an error in testing, the prompt
  is updated to prevent that error in future sessions.
