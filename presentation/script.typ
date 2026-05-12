#set document(
  title: "Presentation Script — Marketing Analytics Agent",
  author: "Nhan Chau",
)

#set page(
  paper: "a4",
  margin: (top: 2.5cm, bottom: 2.5cm, left: 2.8cm, right: 2.8cm),
  numbering: "1",
)

#set text(
  font: "Roboto",
  size: 11pt,
  lang: "en",
)

#set par(
  leading: 0.75em,
  spacing: 1.2em,
)

#set heading(numbering: none)

// ----- title block -----
#align(center)[
  #v(1.5cm)
  #text(size: 20pt, weight: "bold")[Presentation Script]
  #v(0.4em)
  #text(size: 13pt, style: "italic")[Design and Implementation of a LangGraph-Based Marketing Analytics Agent]
  #v(0.6em)
  #text(size: 11pt)[Nhan Chau · Tampere University · #datetime.today().display("[year]")]
  #v(0.3em)
  #text(size: 10pt, fill: luma(120))[Target length: ~10 minutes]
  #v(1.5cm)
  #line(length: 100%, stroke: 0.5pt + luma(180))
  #v(0.8cm)
]

// ----- helper: slide heading -----
#let slide(number, title, time) = {
  v(0.6em)
  block(
    fill: luma(235),
    radius: 4pt,
    inset: (x: 10pt, y: 6pt),
    width: 100%,
  )[
    #text(weight: "bold", size: 11pt)[Slide #number — #title]
    #h(1fr)
    #text(size: 9pt, fill: luma(100))[#time]
  ]
  v(0.2em)
}

// =====================================================================
#slide("1", "Title", "~30 sec")

Good [morning / afternoon], everyone. My name is Nhan. Today I want to share a problem I found interesting, the design I came up with to address it, and the thinking behind each decision.

// =====================================================================
#slide("2", "Introduction", "~2 min")

Imagine you are a marketing analyst. Every Monday morning, your manager asks: how did our campaigns — the ads we are running on Google, Meta, LinkedIn — perform last week, and why did our Google results drop on Thursday?

To answer that, you open a database, write a query in SQL — a language for asking questions to a database — wait for results, clean the data, build a chart, write a summary — and by the time you are done, half the morning is gone. And that is just one question.

I started thinking: what if you could just ask that question the same way you would ask a colleague, and get back a full structured answer? No SQL, no dashboard navigation — just a conversation.

That is the idea behind this thesis. I proposed the design of an AI agent that sits in front of a marketing database and handles that whole cycle automatically — from understanding the question to returning the report.

One thing to set expectations on: this thesis covers the design and a working implementation to validate the design decisions — but it is not production-grade. Things like security hardening, multi-tenant isolation, and scaling are out of scope. The goal is to show that the architecture works and that the design choices hold up, not to ship a product.

// =====================================================================
#slide("3", "Research Questions", "~1 min 30 sec")

The design work is guided by three research questions.

The first is about reliability: *how can the agent be designed to perform multi-step data analysis consistently?* This covers how the agent plans its steps, decides what to query, and knows when it has enough to answer.

The second is about consistency for recurring tasks: *how do structured prompt templates improve output quality for workflows like weekly reports?* Left to itself, the agent might approach the same task differently each time.

The third is about speed: *how can running multiple agents in parallel reduce the time needed for cross-platform comparisons?*

// =====================================================================
#slide("4", "System Architecture", "~1 min 30 sec")

When you send a message to the agent, it travels through four layers.

The *API layer* — think of it as the front door — receives your message. The *agent layer* is where the thinking happens, built with a framework called LangGraph, which manages the step-by-step reasoning loop. That loop follows the *ReAct pattern* — short for Reason and Act: the agent reasons about what to do, takes an action like running a query, observes the result, and reasons again. It keeps going until it has a complete answer.

The *tool layer* gives the agent three tools to interact with the database. And the *data layer* is a PostgreSQL database — a widely used type of relational database — containing the marketing data. The agent can read from it but never write to it.

So at its core, the system is a reasoning loop with controlled access to real data.

// =====================================================================
#slide("5", "Key Design #1 — Smart Agent, Simple Tools", "~1 min 30 sec")

Early on, I had to decide: how many tools should the agent have?

One approach is to build a specialised tool for every task — one for weekly reports, one for campaign analysis, one for each platform. But that means every new requirement needs new code, and the more tools there are, the more choices the model has to make — and the more it can go wrong.

The approach I took is the opposite. Give the model as few tools as possible, and trust it to handle the rest. The model can already reason, analyse, format, and adapt. What it cannot do on its own is connect to a database and run a query. So the tools exist only for that boundary — *schema discovery* (looking up what tables and columns exist in the database) and *SQL execution* (actually running the query and fetching the data).

One insight I found along the way: *how a tool is described in plain English shapes agent behaviour more than the code behind it.* The description is what the model reads before every decision. Write it precisely, and the agent behaves predictably. Write it vaguely, and it guesses.

// =====================================================================
#slide("6", "Key Design #2 — Skills System", "~1 min 30 sec")

The ReAct loop works well for open-ended questions. But some workflows are not open-ended — they are the same every week.

A weekly performance report needs specific queries, specific computed metrics, and a specific output structure. If you just ask the agent "give me the weekly report," it might produce something reasonable — or it might skip a step, or structure the output differently from last week. That inconsistency is a problem when analysts rely on the report regularly.

Skills solve this without adding complexity. A skill is a plain text file with a numbered list of steps. When the analyst types `/weekly-report`, that file is injected into the agent's context — and the agent follows it like a recipe. No new tools, no retraining the model.

It is a bit like the difference between asking a chef to cook dinner however they like, versus handing them a recipe. The skill does not change what the agent can do — it just makes sure it does the same thing, the same way, every time.

// =====================================================================
#slide("7", "Key Design #3 — Parallel Multi-Agent Orchestration", "~1 min 30 sec")

The last design addresses a specific type of question: comparisons across platforms.

When an analyst asks "compare Google Ads and Meta for Q1," there are really two separate data-gathering tasks — one per platform. Running them one after the other is the simplest approach, but it means the analyst waits for both to finish sequentially.

The proposed design spawns two independent subagents — smaller, self-contained AI agents, one for Google and one for Meta — and runs them at the same time. Each one follows the full ReAct loop on its own, fetches the data it needs, and returns a structured summary. Once both are done, the lead agent combines them into a single comparison report.

The idea is that the analyst should not have to wait twice when the two tasks have nothing to do with each other. And as the number of platforms grows, the time saved grows with it.

---

*To close* — this thesis proposed an architecture where a marketing analyst can simply ask a question and get back a structured, data-driven answer. The three design contributions — minimal tools, a skills system, and parallel subagents — each address a different challenge: reliability, consistency, and speed. The next step is building and evaluating a working implementation against the six test scenarios defined in the evaluation plan.

*Thank you. I am happy to take any questions.*

// =====================================================================
#v(1cm)
#line(length: 100%, stroke: 0.5pt + luma(180))
#v(0.8cm)

#align(center)[
  #text(size: 16pt, weight: "bold")[Anticipated Q&A]
]
#v(0.6cm)

#let qa(q, a) = {
  block(inset: (left: 0pt), below: 1.2em)[
    #text(weight: "bold")[Q: #q]
    #parbreak()
    #a
  ]
}

#qa(
  "How does the LLM avoid generating incorrect SQL or wrong marketing metrics?",
  [
    There are two separate concerns here. For *SQL correctness*, the schema discovery tools give the agent real table names and column types before it writes any query. If a query still fails at runtime, the ReAct loop allows the agent to read the error and adapt — rewriting the query and trying again.

    For *business correctness*, the system does not guarantee 100% accuracy. Standard platform metrics — such as ROAS, which means return on ad spend: how much revenue came back for every dollar spent on ads, or CTR, the percentage of people who saw an ad and clicked on it — are defined in the system prompt using platform API documentation as a reference. For custom metrics that a company defines internally, those definitions need to be embedded in the model's context manually. Either way, the final output still requires an analyst to validate the numbers before acting on them.
  ]
)

#qa(
  "Why 3 tools rather than specialised tools for each task?",
  [
    Think of it this way — if you hire a skilled analyst, you do not hand them a separate instruction manual for every possible report they might produce. You give them access to the database and trust them to figure out the rest.

    That is the same idea here. The model today is already capable of reasoning through a problem, deciding what to query, interpreting the results, and formatting a clear answer. What it cannot do on its own is connect to a database, authenticate, and run a query — those are the hard boundaries. So the three tools exist only for that.

    Everything else — how to think, what to compute, how to present the output — is left open. And as models keep getting smarter, that open space only grows. A specialised tool for every task would actually limit that, because you would be locking the logic into code rather than letting the model reason through it.
  ]
)

#qa(
  "How would you prove that parallel subagents reduce latency compared to sequential execution?",
  [
    The planned evaluation runs the same cross-platform comparison twice — once sequentially, once with parallel subagents — and records wall-clock time for both. The expected result is that parallel time is close to the duration of the slowest single subagent, while sequential time grows with the number of tasks. This measurement is part of the evaluation plan and has not been run yet.
  ]
)

#v(1cm)
#line(length: 100%, stroke: 0.5pt + luma(180))
#v(0.3em)
#align(center)[
  #text(size: 9pt, fill: luma(130))[End of script — estimated ~10 minutes at a relaxed speaking pace]
]
