// Test Plan — Marketing Analytics Agent
// Standalone document, compile with:
//   typst compile test-plan.typ --font-path ../thesis/fonts

#set document(
  title: "Marketing Analytics Agent — Test Plan",
  author: "Nhan Chau",
  date: datetime(year: 2026, month: 5, day: 3),
)

#set page(
  paper: "a4",
  margin: (top: 2.5cm, bottom: 2.5cm, left: 2.5cm, right: 2.5cm),
  numbering: "1",
  number-align: center,
)

#set text(font: "Roboto", size: 10.5pt, fill: luma(30))
#set par(justify: true, leading: 0.65em)
#set heading(numbering: "1.")

#let accent = rgb("#0055a5")
#let muted  = luma(110)
#let rowbg  = luma(248)

// ── Title block ────────────────────────────────────────────────────────────

#align(center)[
  #v(0.5cm)
  #text(size: 20pt, weight: "bold", fill: accent)[Marketing Analytics Agent]
  #v(0.2cm)
  #text(size: 14pt, fill: muted)[Test Plan]
  #v(0.35cm)
  #line(length: 60%, stroke: 0.5pt + accent)
  #v(0.35cm)
  #grid(
    columns: (auto, auto),
    gutter: 2cm,
    align(right)[#text(fill: muted)[*Author*]], [Nhan Chau],
    align(right)[#text(fill: muted)[*Date*]],   [3 May 2026],
    align(right)[#text(fill: muted)[*Version*]], [1.0],
  )
  #v(0.8cm)
]

// ── 1. Overview ────────────────────────────────────────────────────────────

= Overview

This document defines the functional test plan for the marketing analytics
agent proof-of-concept (POC). The agent is a LangGraph-based ReAct system
that answers natural-language questions about campaign performance data via
three tools: `list_tables`, `describe_table`, and `query_data`.

#v(0.3em)

*Test data.* A synthetic PostgreSQL database seeded with 181 days of data
(1 Oct 2025 – 31 Mar 2026) across three platforms: Google Ads, Meta, and
LinkedIn. The database contains 11 campaigns, 24 ad groups, 60 ads, and the
`daily_metrics`, `campaigns`, `ad_groups`, `ads`, and `audience_segments`
tables.

#v(0.3em)

*Scope.* Tests cover the three Phase-1 priority skills
(`weekly-report`, `campaign-analysis`, `investigate-drop`) and ad-hoc
query capability. Conversation-memory (multi-turn) is tested in T8.

// ── 2. Pass/Fail Criteria ──────────────────────────────────────────────────

= Pass / Fail Criteria

#table(
  columns: (auto, 1fr),
  stroke: none,
  fill: (_, row) => if calc.even(row) { rowbg } else { white },
  inset: (x: 8pt, y: 6pt),
  table.header(
    table.cell(fill: accent)[#text(fill: white, weight: "bold")[Criterion]],
    table.cell(fill: accent)[#text(fill: white, weight: "bold")[Definition]],
  ),
  [*Pass*],
  [The agent returns a correct, grounded answer using only the available data.
   Tool calls are visible and logically ordered.],
  [*Partial pass*],
  [The answer is directionally correct but misses a secondary metric or
   misstates a derived value (e.g., rounds ROAS differently).],
  [*Fail*],
  [The agent halluccinates data, refuses to answer, or returns an answer
   that contradicts what the SQL results show.],
)

// ── 3. Test Cases ──────────────────────────────────────────────────────────

= Test Cases

#v(0.5em)

// Helper: renders one test case block
#let tc(id, category, skill, question, tests, expected) = {
  block(
    width: 100%,
    fill: white,
    stroke: (left: 3pt + accent, rest: 0.5pt + luma(220)),
    radius: 3pt,
    inset: 10pt,
    breakable: false,
  )[
    #grid(
      columns: (auto, 1fr),
      gutter: 6pt,
      [#text(weight: "bold", fill: accent, size: 11pt)[#id]],
      [#text(weight: "bold", size: 11pt)[#category]
       #h(1fr)
       #box(
         fill: luma(240),
         radius: 3pt,
         inset: (x: 6pt, y: 3pt),
       )[#text(size: 8pt, fill: muted)[#skill]]
      ],
    )
    #v(0.3em)
    #block(
      fill: luma(250),
      radius: 3pt,
      inset: (x: 8pt, y: 6pt),
      width: 100%,
    )[
      #text(style: "italic", fill: luma(50))[#question]
    ]
    #v(0.4em)
    #grid(
      columns: (90pt, 1fr),
      gutter: 4pt,
      [#text(fill: muted, size: 9pt, weight: "bold")[WHAT IT TESTS]], tests,
      [#text(fill: muted, size: 9pt, weight: "bold")[EXPECTED BEHAVIOUR]], expected,
    )
  ]
  v(0.7em)
}

#tc(
  "T1",
  "Schema Discovery",
  "ad-hoc",
  "What data do you have access to? Describe the tables and their columns.",
  [Agent calls `list_tables` then `describe_table` for each table before answering.
   Establishes the baseline exploration behaviour.],
  [Names all 5 tables with a brief description of columns and data types. No SQL
   query needed.],
)

#tc(
  "T2",
  "Weekly Report",
  "weekly-report",
  "Give me a weekly performance summary for the last week of January 2026. " +
  "Show spend, clicks, conversions, and ROAS by platform.",
  [Multi-table join (`daily_metrics` + `campaigns`), GROUP BY platform and
   date range, derived metric ROAS = revenue / spend.],
  [Returns a table with one row per platform. ROAS values are rounded and
   plausible given the seed data cost/revenue ranges.],
)

#tc(
  "T3",
  "Top / Bottom Campaign Ranking",
  "campaign-analysis",
  "Which 3 campaigns had the highest ROAS in Q1 2026? Which 3 had the lowest?",
  [ORDER BY derived metric, LIMIT, and the ability to produce both a top and
   bottom list in a single response turn.],
  [Returns two ranked lists with campaign names, platforms, and ROAS values.
   No campaign appears in both lists.],
)

#tc(
  "T4",
  "Cross-Platform Comparison",
  "campaign-comparison",
  "Compare Google Ads, Meta, and LinkedIn for Q1 2026. " +
  "Show total spend, total conversions, CPC, and ROAS per platform.",
  [GROUP BY platform, multiple derived metrics in one query (CPC = spend/clicks,
   ROAS = revenue/spend), date-range filtering.],
  [A three-row summary table. LinkedIn should show higher CPC than Meta
   (consistent with seed config).],
)

#tc(
  "T5",
  "Campaign Deep Dive",
  "campaign-analysis",
  "Find the campaign with the most total conversions and break it down: " +
  "daily conversion trend, ad group performance, and its audience segment.",
  [Multi-step reasoning — agent must first identify the campaign, then issue
   two or three follow-up queries autonomously without prompting.],
  [Identifies the top campaign by name, shows a daily trend table, a per-ad-group
   breakdown, and the linked audience segment from `audience_segments`.],
)

#tc(
  "T6",
  "Anomaly Investigation",
  "investigate-drop",
  "Conversions on Meta seem to have dropped in February 2026 compared to January. " +
  "Investigate — which campaigns drove the drop and what changed?",
  [Iterative narrowing: platform → month comparison → campaign-level diff.
   Tests multi-query reasoning and root-cause framing.],
  [Confirms the drop with numbers, isolates the specific Meta campaign(s) responsible,
   and proposes a plausible cause (budget, CTR, or CVR change).],
)

#tc(
  "T7",
  "Budget Efficiency",
  "paid-media-review",
  "Which campaigns are spending the most but delivering the worst return? " +
  "Show the top 5 by spend with their ROAS, and flag any below 1.0.",
  [ORDER BY spend DESC, conditional flagging on derived ROAS threshold,
   combined sort + filter logic.],
  [A ranked table of 5 campaigns. Any campaign with ROAS < 1 is explicitly
   flagged as unprofitable.],
)

#tc(
  "T8",
  "Multi-Turn Memory",
  "ad-hoc (multi-turn)",
  [_Step 1:_ Ask T3 (top/bottom by ROAS). \
   _Step 2 (same thread):_ "For the worst-performing campaign you just found, " +
   "show me its daily spend trend over its entire history."],
  [Conversation memory via `MemorySaver`. Agent must recall the campaign name from
   the previous turn without the user repeating it.],
  [Step 2 correctly names the campaign identified in Step 1 and returns a daily
   spend series covering Oct 2025 – Mar 2026.],
)

// ── 4. Run Order ───────────────────────────────────────────────────────────

= Recommended Run Order

Run tests in sequence within a single browser session. Keep T8 in the same
conversation thread as T3 to verify memory.

#table(
  columns: (auto, auto, 1fr, auto),
  stroke: none,
  fill: (_, row) => if calc.even(row) { rowbg } else { white },
  inset: (x: 8pt, y: 5pt),
  table.header(
    table.cell(fill: accent)[#text(fill: white, weight: "bold")[Step]],
    table.cell(fill: accent)[#text(fill: white, weight: "bold")[Test]],
    table.cell(fill: accent)[#text(fill: white, weight: "bold")[Purpose]],
    table.cell(fill: accent)[#text(fill: white, weight: "bold")[Thread]],
  ),
  [1], [T1], [Confirm schema exploration works],              [New],
  [2], [T2], [Baseline aggregation + derived metrics],        [New],
  [3], [T3], [Ranking + sorting],                            [New],
  [4], [T8], [Memory — follow up on T3 in same thread],       [Same as T3],
  [5], [T4], [Cross-platform join],                           [New],
  [6], [T5], [Multi-step autonomous querying],                [New],
  [7], [T6], [Anomaly investigation (most complex)],          [New],
  [8], [T7], [Budget efficiency + threshold flagging],        [New],
)

// ── 5. Out of Scope ────────────────────────────────────────────────────────

= Out of Scope

The following are *not* covered by this test plan and are deferred to later
implementation phases:

- Chart and file export (`python_exec` tool — not yet implemented)
- Skill-triggered workflows (`/weekly-report` slash commands)
- Email, content, and attribution reports (require additional data tables)
- Statistical A/B test analysis
- Competitive benchmarking (requires external data)
