
#pdf.attach(
  "use-of-ai.typ",
  relationship: "source",
  mime-type: "text/vnd.typst",
  description: "The Typst source code for the front matter section describing how AI was used in producing this work.",
)

I hereby declare that the AI-based applications used in generating this work are as follows:

#table(
  align: left,
  columns: (70%, 30%),
  table.header(
    [*Application*],
    [*Version*]
  ),
  [Claude (Anthropic) — claude-sonnet-4-6], [claude-sonnet-4-6],
  [Claude Code (CLI)], [1.x],
)

== Purpose of the use of AI

AI assistance was used in two complementary ways during this thesis.

First, Claude Code (the Anthropic command-line AI assistant) was used as a
writing and development tool throughout the project. It assisted in scaffolding
Typst source files, suggesting phrasing for technical sections, and checking
logical consistency between chapters.

Second, the thesis itself studies AI agents: the system implemented as the
thesis artefact uses Claude as the reasoning core of a LangGraph ReAct agent.
The API-level use of Claude in the implementation is thus part of the research
contribution, not merely a writing aid.

== Parts of this work where AI was used

AI assistance was used throughout all chapters of this thesis, including the
frontmatter, main chapters, appendices, and bibliography. All AI-generated or
AI-assisted content was reviewed, verified, and approved by the author.
