# Presentation Script — Marketing Analytics Agent
**Target length: ~10 minutes (~1,400 words at a relaxed speaking pace)**

---

## Slide 1 — Title (30 seconds)

Good [morning / afternoon], everyone. My name is Nhan, and today I want to talk about a problem that almost every company faces, and an AI-powered solution I designed to help with it.

The thesis is titled: **"Design of a Conversational AI Agent for Marketing Analytics."**

---

## Slide 2 — The Problem (1.5 minutes)

Let me start with the problem.

Imagine you work at a company that runs ads — on Google, on Facebook, on LinkedIn. Every week, your marketing team wants to know:

- Which ads are performing well?
- How much money did we spend, and did it pay off?
- Why did our results drop last Tuesday?

To answer these questions, someone has to open a database, write a query in a language called SQL, clean up the data, build a chart, and write a report. That whole process can take **hours** — for a single question.

Business intelligence tools, like dashboards, help a little. But you still need to know how to use them, and they are not great at answering new or unexpected questions.

So the problem is clear: **getting answers from marketing data is too slow and requires too much technical skill.**

---

## Slide 3 — The Opportunity: Large Language Models (1 minute)

In the last few years, AI models like ChatGPT and Claude have become surprisingly capable. They can write code. They can answer complex questions. They can read a table of numbers and summarise the trends in plain English.

So the natural question is: **can we combine an AI model with a company's marketing database, and let it answer questions automatically?**

That is exactly what this thesis explores.

---

## Slide 4 — What I Built: The System Overview (1 minute)

I designed a system called a **Marketing Analytics Agent**. Here is the idea in simple terms:

You type a question in plain English — for example, "How much did we spend on Google Ads last month?" — and the agent figures out how to answer it. It looks at the database, runs the right queries, and gives you back a clear answer with numbers and a short explanation.

No SQL needed. No dashboard to navigate. Just a conversation.

The system is built on top of a framework called **LangGraph**, which handles the step-by-step reasoning loop, and connects to a **PostgreSQL database** containing marketing campaign data.

---

## Slide 5 — How the Agent Thinks: The ReAct Loop (1.5 minutes)

Now, you might wonder — how does the AI actually "think" its way to an answer? It does not guess. It follows a loop called the **ReAct pattern**, which stands for Reason and Act.

Here is how it works:

1. **Reason** — the agent looks at your question and thinks: "What do I need to find out first?"
2. **Act** — it takes an action, like querying the database.
3. **Observe** — it reads the result.
4. Then it **reasons again**: "Do I have enough to answer, or do I need to dig deeper?"

It keeps doing this — reason, act, observe — until it has enough information to give you a final answer.

This is very different from a simple chatbot that just generates a response from memory. This agent is actively interacting with real data. It does not make up numbers. It reads them from the database.

---

## Slide 6 — The Tools (1 minute)

To interact with the database, the agent has exactly **three tools**. I kept it minimal on purpose.

- **List tables** — this is like opening a map. The agent first looks at what tables exist in the database.
- **Describe table** — this is like zooming in on one table to see what columns it has and what the data looks like.
- **Query data** — this is where the agent actually runs a database query to fetch the numbers it needs.

Why only three tools? Because fewer tools means fewer ways for the agent to get confused. The agent is smart enough to handle the analysis in its head — it only needs tools when it has to touch the database.

One interesting design insight I found: **how you describe a tool in plain English matters more than how you code it.** If the description is clear and precise, the agent uses the tool correctly almost every time. If the description is vague, the agent guesses — and guesses wrong. So tool descriptions are essentially a form of instructions for the AI.

---

## Slide 7 — Handling Complex Questions: Parallel Subagents (1 minute)

Some questions are more complex. For example: "Compare our Google Ads performance versus our Meta performance for the first quarter."

This requires gathering data from two different platforms at the same time. To handle this, the system uses a **multi-agent design**.

The main agent — I call it the lead agent — recognises that this is a parallel job. So it **spawns two smaller subagents**, one for Google, one for Meta, and runs them at the same time — in parallel. While one is querying Google data, the other is querying Meta data simultaneously.

When both finish, the lead agent collects their results and combines them into one unified comparison report.

The benefit is speed. Instead of doing everything one after another, the agent splits the work and does it at the same time, cutting the waiting time roughly in half.

---

## Slide 8 — The Skills System (1 minute)

The last design contribution is what I call the **Skills System**.

Some marketing tasks are very structured. For example, a weekly performance report always needs: the same type of data, the same calculations (like comparing this week to last week), and the same output format with specific sections.

If you just ask the agent "give me the weekly report," it might miss a step or format the output differently each time.

Skills fix this. A skill is basically a **recipe** — a numbered list of instructions written in plain English — that gets injected into the agent's context when triggered. For example, when someone types `/weekly-report`, the agent receives a step-by-step guide:

1. Query the last 7 days of data.
2. Compute week-over-week changes.
3. Find the top and bottom performing campaigns.
4. Write a structured report with these exact sections.

The agent then follows that recipe. The result is much more consistent and reliable output.

What makes skills elegant is that they do not require any new code. You just write a text file, and the agent uses it as a guide. Adding a new analytical workflow is as simple as writing a new skill file.

---

## Slide 9 — Evaluation Plan (45 seconds)

I planned six test scenarios to evaluate the system:

- A simple question
- A follow-up question
- A trend analysis over 30 days
- An investigation into why a metric dropped
- A skill-triggered structured report
- A parallel cross-platform comparison

Each scenario tests a different part of the system. I also planned a controlled experiment to directly show that better tool descriptions lead to better agent behaviour — the same tool, just described differently, produces noticeably different results.

Empirical testing with a working implementation is planned as next steps.

---

## Slide 10 — Conclusions (45 seconds)

To summarise, this thesis made four contributions:

1. A clean, minimal **system architecture** — three tools, a ReAct reasoning loop, built entirely from open-source components, no custom AI training required.
2. A **parallel multi-agent design** that reduces waiting time for complex cross-platform analyses.
3. A **skills system** that makes the agent reliable for structured workflows without adding complexity to the code.
4. A **tool description principle** — the idea that the plain-English description of a tool shapes agent behaviour more than the code itself.

The goal was to make marketing data analysis accessible to anyone on a team, not just the data engineers. Instead of waiting hours for a report, you ask a question and get an answer in seconds.

Thank you. I am happy to take any questions.

---

*[End of script — estimated ~10 minutes at a relaxed pace of ~140 words/min]*
