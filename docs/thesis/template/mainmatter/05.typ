/** 05.typ — Chapter 5: Evaluation Plan and Discussion
***/

#pdf.attach(
  "05.typ",
  relationship: "source",
  mime-type: "text/vnd.typst",
  description: "The Typst source code for Chapter 5 (Evaluation Plan and Discussion) of this thesis.",
)

#import "../preamble.typ": *

= Evaluation plan and discussion <evaluation>
This chapter describes the planned evaluation approach for the system and discusses the
key design decisions, expected trade-offs, and limitations identified during the design
phase. Empirical evaluation against a working implementation is left as future work.

== Evaluation methodology <eval-methodology>
Evaluation will be performed by running the agent against a set of representative
scenarios that cover the primary use cases identified in the design phase. Each
scenario consists of a natural-language prompt, an expected sequence of tool calls,
and expected output characteristics.

Because the agent's core reasoning component (the LLM) is a stochastic process,
quantitative pass/fail metrics would require many repeated runs. A practical evaluation
approach combines: (1) qualitative correctness checks per scenario, and (2) a
controlled comparison of agent behaviour with and without specific design elements
(e.g., with and without an active skill, or with a minimal versus full tool
description).

The six planned test scenarios are:

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header([*\#*], [*Scenario*], [*Type*]),
    [1], [Simple question: "How much did we spend on Google Ads last month?"], [Single query],
    [2], [Follow-up query: "Break that down by campaign type"], [Follow-up],
    [3], [Trend analysis: "Show spend by platform for the last 30 days"], [Multi-query],
    [4], [Investigation: "Why did our ROAS drop last week?"], [Multi-step],
    [5], [Structured report: "/weekly-report"], [Skill-driven],
    [6], [Parallel comparison: "Compare Google vs Meta for Q1"], [Multi-agent],
  ),
  caption: [Six planned evaluation scenarios covering the primary use cases.],
) <tab-eval-scenarios>

== Expected scenario outcomes <eval-results>
=== Scenario 1: simple question <eval-s1>
The agent is expected to call `list_tables` on first use to discover the schema, then
call `query_data` with an appropriate aggregation query. The final answer should be
delivered within a small number of tool calls, formatted as currency with a brief
sentence of context.

=== Scenario 2: follow-up query <eval-s2>
The agent should issue a refined SQL query based on the context from the previous turn,
adding a `GROUP BY campaign_type` clause without re-discovering the schema. This
scenario validates that the LangGraph message history is sufficient for the model to
maintain analytical context across turns.

=== Scenario 3: trend analysis <eval-s3>
The agent is expected to call `describe_table` to confirm date column formats, then
issue a single aggregation query grouping spend by platform and day. The result should
include a written summary identifying the highest-spend platform and notable trends.

=== Scenario 4: investigation <eval-s4>
The agent should decompose the investigation into sequential steps: confirm the ROAS
drop at a high level, identify affected platforms, drill into campaign-level data, and
identify a root cause. This scenario tests the agent's ability to plan and execute a
multi-step analytical workflow autonomously.

=== Scenario 5: skill-driven report <eval-s5>
With the `weekly-report` skill active, the agent should follow the skill's step
sequence without deviation — issuing the correct queries, computing week-over-week
changes, and producing a structured report with all required sections. Without the
skill, the model is expected to produce incomplete or inconsistently structured output,
demonstrating the value of the skills system.

=== Scenario 6: parallel subagents <eval-s6>
The lead agent should spawn two subagents — one for Google Ads data, one for Meta data
— running them concurrently via `asyncio.gather()`. The design predicts a reduction in
wall-clock time compared to sequential execution, proportional to the number of parallel
tasks. The lead agent should combine the subagent responses into a coherent
cross-platform comparison.

== Prompt engineering impact <eval-prompt>
A key evaluation will compare agent behaviour under two tool description conditions
for the `query_data` tool:

*Minimal description* ("Run a SQL query"): the agent is expected to guess column names,
skip schema discovery, and potentially attempt write operations when asked to "save"
results.

*Full description* (including when to call, SQL constraints, and example patterns): the
agent is expected to call schema tools before writing SQL, use correct column names, and
never attempt write operations.

This comparison requires no new tools or infrastructure — only a change to the
description string. It directly tests the design principle that tool descriptions
function as embedded prompt engineering.

== Limitations <limitations>
=== LLM inference cost
Each turn of the ReAct loop incurs an LLM API call. A complex weekly-report workflow
may require 8–12 turns. At current API pricing for capable models, this cost is
acceptable for a power-user analytics tool but may be prohibitive at scale without
prompt caching or a smaller fine-tuned model.

=== Skill coverage gap
The design identifies twenty analytics workflows but specifies only three skills for the
initial implementation. Workflows without a dedicated skill rely on the static system
prompt for guidance, which may lead to inconsistent output for complex multi-step tasks.

=== Read-only database access
The system is designed for read-only access to the marketing database. It cannot write
back annotations, budgets, or campaign status changes. Full analytics workflows may
benefit from write access, but this introduces security concerns that are out of scope
for this design.

== Discussion <discussion>
=== When to use subagents <when-subagents>
The parallel subagent pattern is valuable when tasks are clearly independent and each
task requires multiple tool calls. For simple two-query comparisons, the lead agent can
issue both queries sequentially without spawning subagents. A useful design heuristic
is: use subagents when each task would require more than three tool calls on its own,
making the parallelism overhead worthwhile.

=== The limits of the smart-agent philosophy <smart-agent-limits>
The three-tool design works well for SQL-driven analysis and natural-language
summaries. For highly specialised output requirements — for example, a compliance
report that must follow a precise regulatory template — the agent's text output alone
may be insufficient and a specialised tool would be needed. Adding such a tool is
justified when the frequency and precision requirements of the task outweigh the
additional complexity of expanding the tool surface.

=== Prompt as living document <prompt-living-document>
One of the most important design insights is that the system prompt requires continuous
maintenance. Every scenario where the agent fails reveals a gap in the prompt: a missing
instruction, an ambiguous rule, or an absent example. Treating the prompt as source code
— with version control and documented rationale for each change — is essential for
maintaining agent reliability over time.
