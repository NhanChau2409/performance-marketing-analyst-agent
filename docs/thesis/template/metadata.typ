//
// metadata.typ
//
// Write any metadata related to your document here, by
// filling in suitable values for the given variables. This
// file is automatically loaded by the main file.
//

#import "../tauthesis.typ" as tauthesis

// Common metadata.

#let author = "Nhan Chau"

#let examiners = (
  (
    title: "Professor",
    firstname: "Ahmed",
    lastname: "Farooq",
  ),
)

/**
 * One of "fi" or "en".
 ***/

#let language = "en"

/**
 * "FI" if your language was set as "fi", or some accepted
 * region such as "US" or "GB", if your language was "en".
 ***/
#let region = "US"

/**
 * This allows you to choose a citation style. See
 * <https://typst.app/docs/reference/model/bibliography/#parameters-style>
 * for possible options.
 ***/

#let citationStyle = "ieee"

/**
 * Choose which bibliography file you wish to use.
 * Valid values are "yaml" for Hayagriva and "bib" for BibLaTeX.
 ***/

#let bibFileSuffix = "yaml"

/**
 * Set this to false if you are an international student and do
 * not need a Finnish abstract.
 ***/

#let includeFinnishAbstract = false

/**
 * Set this to true before compiling your document, if you intend
 * to print a physical copy of it.
 ***/

#let physicallyPrinted = false

/**
 * This flag makes the document pages two-sided, meaning the inner
 * margin will vary on even and odd pages. Only set this to true if
 *
 * 1. you set the flag physicallyPrinted to true and
 * 2. your main matter is over 80 pages long.
 *
 * Setting this to true will make the document very annoying to
 * read on electronic screens, if physicallyPrinted is also true.
 ***/

#let printTwoSided = false

/**
 * Set this to true, if you utilized artificial intelligence, such as large
 * language models in writing your thesis.
 ***/

#let usedAI = true

/**
 * Set this to false if you are writing a monograph
 * dissertation. Keep the value as true if you are writing
 * a compilation thesis. If you are not writing a PhD
 * dissertation or a licentiate thesis with publications,
 * the value does not matter.
 ***/

#let compilationThesis = false

/**
 * Setting this to false will disable the loading of PhD
 * dissertation publications at the end of the document.
 ***/

#let attachPublications = false

// A description that ends up in document metadata.

#let description = "A bachelor's thesis on designing and implementing a LangGraph-based conversational AI agent for marketing analytics, exploring agentic patterns including the ReAct loop, parallel multi-agent orchestration, and structured prompt templates (skills)."

// Choose your thesis type.

#let thesisType = tauthesis.bachelorsThesisType

#let työnTyyppi = tauthesis.kandidaatinTyönTyyppi

//// Finnish metadata (not used — includeFinnishAbstract = false).

#let alaotsikko = none
#let avainsanat = ("tekoälyagentti", "markkinointianalytiikka", "LangGraph", "ReAct")
#let koulu = "Tampereen Yliopisto"
#let otsikko = "LangGraph-pohjaisen markkinointianalytiikka-agentin suunnittelu ja toteutus"
#let sijainti = "Tampereella"
#let tiedekunta = "Tiedekunta" // TODO
#let tutkintoOhjelma = "Tutkinto-ohjelma" // TODO

//// English metadata.

#let faculty = "Faculty" // TODO: e.g. "Faculty of Information Technology and Communication Sciences"
#let keywords = (
  "AI agent",
  "LangGraph",
  "ReAct",
  "marketing analytics",
  "large language models",
  "tool calling",
  "multi-agent systems",
)
#let location = "Tampere"
#let subtitle = "An Exploration of Agentic Patterns for Autonomous Data Analysis"
#let maintitle = "Design and Implementation of a LangGraph-Based Marketing Analytics Agent"
#let thesisProgramme = "Bachelor's Programme in Science and Engineering"
#let university = "Tampere University"

// Set the maximum heading levels under which figures and equations are numbered.

#let figNumberWithinLevel = 1

#let eqNumberWithinLevel = 1

// Determines whether the link to the table of contents is
// displayed or not.

#let displayLinkToToC = true

// Line numbers for reviewer.

#let showParagraphLineNumbers = false

// Choose whether to include certain frontmatter sections.

#let includeGlossary = true

#let includeListOfFigures = true

#let includeListOfTables = true

#let includeListOfListings = true

// Fonts.

#let textFont = "Roboto"

#let mathFont = "STIX Two Math"

#let codeFont = "Fira Mono"
