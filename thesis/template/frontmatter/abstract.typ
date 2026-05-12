/** abstract.typ
 *
 * Fill in the English abstract of your thesis in this file.
 *
***/

#pdf.attach(
  "abstract.typ",
  relationship: "source",
  mime-type: "text/vnd.typst",
  description: "Typst source code for the English abstract of this thesis.",
)

#import "../preamble.typ": *

This thesis presents the design of a conversational AI agent for marketing analytics.
The proposed system lets analysts query data and produce analytical reports using natural
language, without writing SQL or navigating BI tools.

The agent is designed on LangGraph using the ReAct pattern, with three minimal tools for
schema discovery and SQL execution, a skills system for structured multi-step workflows,
and a parallel multi-agent architecture for cross-platform analysis. A planned evaluation
covering six representative scenarios will validate the design. Key design hypotheses are
that tool descriptions function as embedded prompt engineering and that parallel subagents
reduce cross-platform analysis latency compared to sequential execution.
