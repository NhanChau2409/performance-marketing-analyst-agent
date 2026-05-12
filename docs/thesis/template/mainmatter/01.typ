/** 01.typ — Chapter 1: Introduction
***/

#pdf.attach(
  "01.typ",
  relationship: "source",
  mime-type: "text/vnd.typst",
  description: "The Typst source code for Chapter 1 (Introduction) of this thesis.",
)

#import "../preamble.typ": *

= Introduction <introduction>
Marketing teams are among the heaviest consumers of data in modern organisations.
Every week, analysts must answer questions such as: which campaigns are producing the
highest return on ad spend, why did click-through rates drop on a particular platform,
and how should the budget be reallocated for the next quarter? Answering each question
requires querying a database, cleaning and joining results, writing visualisation code,
and assembling the findings into a report — a cycle that can take hours for a single
request.

Business intelligence tools help structure common reports, but they are poorly suited
for ad-hoc investigation: the analyst must still know how to navigate the tool,
construct the right filters, and interpret the raw output. Natural-language interfaces
to databases have been studied for decades, but translating a free-form English
question into a correct SQL query remains an open problem, and presenting the answer
in a meaningful way requires additional reasoning that traditional query systems cannot
provide @gartner2023analytics.

Recent advances in large language models (LLMs) offer a different approach. Modern
LLMs can write correct SQL for unfamiliar schemas, generate Python visualisation code,
reason about intermediate results, and decide what steps to take next in order to
answer a question. These capabilities, combined with an agentic control loop that gives
the model access to real tools, create the possibility of a system that can
autonomously handle the full analysis cycle — from data retrieval to chart generation
to narrative summary — in response to a single natural-language request.

== Motivation and problem statement <motivation>
This thesis explores whether a conversational AI agent can replace the manual
data-analysis workflow that marketing teams currently perform. The central challenge is
not simply connecting an LLM to a database: it is designing the system so that the
model reliably produces correct, well-formatted, context-efficient output across a
wide variety of questions, without hallucinating data or exhausting its context window
with raw query results.

Concretely, the system built in this thesis must be able to:

- Accept a natural-language question or command from a marketing analyst.
- Autonomously discover the database schema, write and execute SQL queries, and
  perform data analysis.
- Generate charts, tables, and summaries from query results.
- Delegate work to parallel subagents when comparing multiple platforms simultaneously.

== Research questions <research-questions>
This thesis addresses three research questions:

*RQ1.* How can a ReAct-based LLM agent be designed to reliably perform multi-step
marketing data analysis, including schema discovery, SQL query generation, and
structured report generation?

*RQ2.* How can parallel multi-agent orchestration be designed to reduce analysis
latency and support cross-platform comparisons in a marketing analytics agent?

*RQ3.* How do structured prompt templates (skills) improve the reliability and
consistency of an LLM agent for domain-specific analytical workflows?

== Contributions <contributions>
The main contributions of this thesis are:

+ *A proposed system architecture* for a LangGraph-based marketing analytics agent
  with a ReAct graph, three minimal tools, and a parallel multi-agent orchestration
  layer. The design shows how the full analysis stack — from natural-language query to
  structured report — can be composed from open-source components without custom model
  training.

+ *A parallel multi-agent design* in which a lead agent spawns independent subagents
  for concurrent data gathering across platforms. Subagents return structured text
  results to the lead agent, which synthesises them into a unified report, reducing
  wall-clock latency compared to sequential execution.

+ *A skills system design* — a lightweight mechanism for injecting structured,
  step-by-step workflow instructions into the agent's session context at runtime,
  improving reliability for complex analytical tasks without modifying the tool layer.

+ *A tool description design principle*: the hypothesis that a tool's natural-language
  description determines agent behaviour more strongly than the tool's implementation
  code, formulated as a testable claim for the planned evaluation.

== Scope and limitations <scope>
This thesis focuses on the design of the agent system. The target data environment is a
PostgreSQL database with synthetic marketing data covering three advertising platforms
(Google Ads, Meta, LinkedIn). The LLM backbone is treated as a black box: the thesis
does not study model training or fine-tuning. Security hardening and multi-tenant
isolation are out of scope.

== Thesis structure <thesis-structure>
Chapter @background reviews the background: large language models and tool calling,
the ReAct agent pattern, the LangGraph framework, multi-agent systems, and the
marketing analytics domain. Chapter @architecture presents the system architecture and
the key design decisions. Chapter @implementation describes the planned implementation
of each component. Chapter @evaluation defines the evaluation plan and discusses the
expected results and design trade-offs. Chapter @conclusions summarises the design
contributions and outlines next steps.
