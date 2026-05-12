/** glossary.typ
 *
 * Glossary of abbreviations and key terms used in this thesis.
 *
***/

#import "../preamble.typ": *

#let glossary_words = (
  api: (
    name: "API",
    description: [
      Application Programming Interface. A defined contract through which
      software components communicate.
    ]
  ),
  cpa: (
    name: "CPA",
    description: [
      Cost Per Acquisition. A marketing metric expressing the average cost
      incurred to obtain one conversion or customer.
    ]
  ),
  cpc: (
    name: "CPC",
    description: [
      Cost Per Click. The average cost paid each time a user clicks on an
      advertisement.
    ]
  ),
  cpm: (
    name: "CPM",
    description: [
      Cost Per Mille. The cost per one thousand ad impressions.
    ]
  ),
  ctr: (
    name: "CTR",
    description: [
      Click-Through Rate. The ratio of clicks to impressions for an
      advertisement, expressed as a percentage.
    ]
  ),
  csv: (
    name: "CSV",
    description: [
      Comma-Separated Values. A plain-text file format for tabular data.
    ]
  ),
  gpu: (
    name: "GPU",
    description: [
      Graphics Processing Unit. Parallel computing hardware used to accelerate
      neural network training and inference.
    ]
  ),
  json: (
    name: "JSON",
    description: [
      JavaScript Object Notation. A lightweight, human-readable data interchange
      format.
    ]
  ),
  kpi: (
    name: "KPI",
    description: [
      Key Performance Indicator. A measurable value used to evaluate the
      success of a marketing campaign or business objective.
    ]
  ),
  llm: (
    name: "LLM",
    description: [
      Large Language Model. A neural network trained on large text corpora
      that can generate and understand natural language.
    ]
  ),
  poc: (
    name: "POC",
    description: [
      Proof of Concept. An early implementation used to validate feasibility
      before committing to a full production build.
    ]
  ),
  roas: (
    name: "ROAS",
    description: [
      Return on Ad Spend. A marketing metric expressing the revenue generated
      per unit of advertising expenditure.
    ]
  ),
  react: (
    name: "ReAct",
    description: [
      Reason + Act. An agent pattern in which a language model alternates
      between a reasoning step and a tool-calling action step @yao2022react.
    ]
  ),
  sql: (
    name: "SQL",
    description: [
      Structured Query Language. The standard language for querying and
      manipulating relational databases.
    ]
  ),
  tuni: (
    name: "TUNI",
    description: "Tampere University"
  ),
)
