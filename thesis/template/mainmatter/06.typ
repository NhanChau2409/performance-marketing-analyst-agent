/** 06.typ — Chapter 6: Conclusions
***/

#pdf.attach(
  "06.typ",
  relationship: "source",
  mime-type: "text/vnd.typst",
  description: "The Typst source code for Chapter 6 (Conclusions) of this thesis.",
)

#import "../preamble.typ": *

= Conclusions <conclusions>
This thesis presented the design of a conversational AI agent for marketing analytics.
The proposed system allows marketing analysts to query data and produce analytical
reports using natural language, without writing SQL or navigating business intelligence
tools.

== Summary of design contributions <contributions-summary>
The work makes four main design contributions:

The first is a *proposed architecture* for a LangGraph-based ReAct agent with three
minimal tools (schema discovery and SQL execution) and a parallel multi-agent
orchestration layer. The design demonstrates that the full analysis cycle — from
natural-language query to structured analytical report — can be composed from
open-source components without custom model training.

The second is a *parallel multi-agent design* in which a lead agent spawns independent
subagents for concurrent data gathering across advertising platforms. Subagents return
structured text results; the lead agent synthesises them into a unified report. The
design is expected to reduce wall-clock latency for cross-platform analyses compared to
sequential execution.

The third is the *skills system*: a lightweight mechanism for injecting structured,
step-by-step workflow instructions into the agent's session context at runtime. Skills
are expected to improve agent reliability for complex multi-step workflows without
requiring new tools or model fine-tuning.

The fourth is a *tool description design principle*: the wording of a tool's
natural-language description is expected to determine agent behaviour more strongly than
the tool's implementation code. This principle is formulated as a testable hypothesis
for the planned evaluation.

== Answers to research questions <rq-answers>
*RQ1: How can a ReAct-based LLM agent be designed to reliably perform multi-step
marketing data analysis?*

Reliability is designed to come from three complementary mechanisms: the system prompt,
which encodes domain knowledge, output standards, and workflow patterns; the skills
system, which provides structured recipes for complex workflows; and informative tool
error messages, which enable the model to self-correct when a query fails. No single
mechanism is expected to be sufficient on its own.

*RQ2: How can parallel multi-agent orchestration be designed to reduce analysis
latency and support cross-platform comparisons in a marketing analytics agent?*

The lead-agent-plus-subagents pattern addresses this. By spawning independent subagents
for each platform and running them concurrently with `asyncio.gather()`, the design
converts a sequential O(n) process into a parallel one. The expected benefit grows
linearly with the number of platforms compared.

*RQ3: How do structured prompt templates (skills) improve the reliability and
consistency of an LLM agent for domain-specific workflows?*

Skills address this by providing the model with an explicit step sequence, SQL patterns,
and output format specification for each workflow. This removes the need for the model
to infer the correct workflow from first principles on every request, reducing the risk
of skipped steps or inconsistent output structure.

== Next steps <future-work>
The following steps are planned to extend this design into a working system:

*Implementation and testing.* The proposed architecture needs to be implemented and
evaluated against the six test scenarios defined in @eval-methodology. The planned
evaluation will validate the design decisions and identify any gaps in the system
prompt, tool descriptions, or skill templates.

*Expanded skill library.* The design identifies twenty analytics workflows. Implementing
the remaining skills — particularly the budget optimiser, attribution report, and funnel
analysis — would cover the majority of recurring marketing analytics use cases.

*Production infrastructure.* A production deployment would require a shared PostgreSQL
checkpoint store for session persistence, secret management for API credentials, and
horizontal scaling of the API layer for concurrent users.

*Live platform API integration.* The design targets a PostgreSQL database seeded with
synthetic data. Connecting to live Google Ads, Meta, and LinkedIn APIs would enable
real-time analysis.

*Model cost optimisation.* Prompt caching — supported by Anthropic's API — would cache
the static system prompt and reduce inference cost for long sessions.
