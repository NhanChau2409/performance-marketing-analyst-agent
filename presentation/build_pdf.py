"""
build_pdf.py — Generate thesis-presentation.pdf using reportlab
Mirrors the 10-slide structure from build.py.

Usage:
    /tmp/pptx-venv/bin/python build_pdf.py
"""

from reportlab.lib.pagesizes import landscape, A4
from reportlab.lib import colors
from reportlab.lib.units import cm, mm
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
import textwrap

# ---------------------------------------------------------------------------
# Page setup (widescreen 16:9 in A4 landscape)
# ---------------------------------------------------------------------------
W, H = landscape(A4)   # 297 × 210 mm ≈ 842 × 595 pt

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
TAU_BLUE   = HexColor("#003087")
ACCENT     = HexColor("#007AC2")
WHITE      = colors.white
DARK_GREY  = HexColor("#333333")
MID_GREY   = HexColor("#666666")
LIGHT_GREY = HexColor("#F2F2F2")
BLUE_LIGHT = HexColor("#CCDDff")
BOX_BLUE   = HexColor("#E8EFFA")

# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------

def header_bar(c: canvas.Canvas, title: str, subtitle: str = None):
    bar_h = 70
    c.setFillColor(TAU_BLUE)
    c.rect(0, H - bar_h, W, bar_h, fill=1, stroke=0)
    c.setFillColor(WHITE)
    c.setFont("Helvetica-Bold", 22)
    c.drawString(28, H - 42, title)
    if subtitle:
        c.setFont("Helvetica", 11)
        c.setFillColor(BLUE_LIGHT)
        c.drawString(28, H - 62, subtitle)


def footer_line(c: canvas.Canvas, page_num: int, total: int = 10):
    c.setFillColor(MID_GREY)
    c.setStrokeColor(HexColor("#CCCCCC"))
    c.line(20, 18, W - 20, 18)
    c.setFont("Helvetica", 8)
    c.drawCentredString(W / 2, 6, "Nhan Chau  —  Tampere University  —  April 2026")
    c.drawRightString(W - 20, 6, f"{page_num} / {total}")


def draw_text(c: canvas.Canvas, text: str, x: float, y: float,
              font: str = "Helvetica", size: int = 13,
              color=DARK_GREY, max_width: float = None):
    c.setFont(font, size)
    c.setFillColor(color)
    if max_width and len(text) * size * 0.55 > max_width:
        # wrap manually
        chars_per_line = int(max_width / (size * 0.55))
        lines = textwrap.wrap(text, chars_per_line)
        for i, line in enumerate(lines):
            c.drawString(x, y - i * (size + 3), line)
    else:
        c.drawString(x, y, text)


def bullets(c: canvas.Canvas, items, x, y, font_size=13, color=DARK_GREY,
            line_gap=None, max_w=None):
    if line_gap is None:
        line_gap = font_size + 7
    cy = y
    for item in items:
        bullet = "\u2022  " + item
        draw_text(c, bullet, x, cy, size=font_size, color=color, max_width=max_w)
        cy -= line_gap
    return cy


def table_box(c: canvas.Canvas, headers, rows, x, y, col_widths,
              row_h=22, header_size=12, cell_size=11):
    n_cols = len(headers)
    total_w = sum(col_widths)

    # header row
    c.setFillColor(TAU_BLUE)
    c.rect(x, y - row_h, total_w, row_h, fill=1, stroke=0)
    c.setFillColor(WHITE)
    c.setFont("Helvetica-Bold", header_size)
    cx = x
    for i, h in enumerate(headers):
        c.drawString(cx + 5, y - row_h + 6, h)
        cx += col_widths[i]

    # data rows
    for r, row in enumerate(rows):
        ry = y - row_h * (r + 2)
        bg = LIGHT_GREY if r % 2 == 0 else WHITE
        c.setFillColor(bg)
        c.rect(x, ry, total_w, row_h, fill=1, stroke=0)
        c.setFillColor(DARK_GREY)
        c.setFont("Helvetica", cell_size)
        cx = x
        for ci, cell in enumerate(row):
            c.drawString(cx + 5, ry + 6, cell)
            cx += col_widths[ci]

    return y - row_h * (len(rows) + 1)


# ---------------------------------------------------------------------------
# Slides
# ---------------------------------------------------------------------------

def s01_title(c: canvas.Canvas):
    # Blue top band
    c.setFillColor(TAU_BLUE)
    c.rect(0, H - 240, W, 240, fill=1, stroke=0)

    # University name
    c.setFillColor(BLUE_LIGHT)
    c.setFont("Helvetica", 11)
    c.drawString(28, H - 28, "TAMPERE UNIVERSITY")

    # Title
    c.setFillColor(WHITE)
    c.setFont("Helvetica-Bold", 24)
    c.drawString(28, H - 80, "Design and Implementation of a")
    c.drawString(28, H - 110, "LangGraph-Based Marketing Analytics Agent")

    # Subtitle
    c.setFont("Helvetica", 14)
    c.setFillColor(BLUE_LIGHT)
    c.drawString(28, H - 155, "An Exploration of Agentic Patterns for Autonomous Data Analysis")

    # Divider
    c.setStrokeColor(TAU_BLUE)
    c.setLineWidth(2)
    c.line(28, H - 260, W - 28, H - 260)

    # Author block
    c.setFillColor(DARK_GREY)
    c.setFont("Helvetica-Bold", 16)
    c.drawString(28, H - 295, "Nhan Chau")
    c.setFont("Helvetica", 12)
    c.setFillColor(MID_GREY)
    c.drawString(28, H - 318, "Bachelor's Thesis  •  Tampere University  •  April 2026")
    c.drawString(28, H - 338, "Examiner: Professor Ahmed Farooq")

    footer_line(c, 1)


def s02_agenda(c: canvas.Canvas):
    header_bar(c, "Agenda")
    items = [
        "Problem & Motivation",
        "Research Questions",
        "System Architecture",
        "Key Design Decisions (Tools, Skills, Multi-Agent)",
        "Evaluation Results",
        "Conclusions & Future Work",
    ]
    bullets(c, items, x=50, y=H - 100, font_size=17, line_gap=38)
    footer_line(c, 2)


def s03_problem(c: canvas.Canvas):
    header_bar(c, "Problem & Motivation",
               "Marketing analytics today is slow, manual, and fragmented")

    pain_points = [
        "Analyst receives a question \u2192 writes SQL \u2192 cleans data \u2192 charts \u2192 writes report",
        "Each cycle can take hours for a single ad-hoc request",
        "BI tools help with standard reports \u2014 but not free-form investigation",
    ]
    bullets(c, pain_points, x=40, y=H - 95, font_size=15, line_gap=35)

    # Hook box
    by = H - 320
    c.setFillColor(BOX_BLUE)
    c.rect(28, by, W - 56, 65, fill=1, stroke=0)
    c.setFillColor(TAU_BLUE)
    c.setFont("Helvetica-BoldOblique", 13)
    c.drawString(45, by + 42,
                 "Modern LLMs can write SQL, reason about results, and generate reports.")
    c.drawString(45, by + 22,
                 "Can a conversational agent replace the full manual analytics cycle?")

    footer_line(c, 3)


def s04_rqs(c: canvas.Canvas):
    header_bar(c, "Research Questions")

    rqs = [
        ("RQ1",
         "How can a ReAct-based LLM agent be designed to reliably perform",
         "multi-step marketing data analysis?"),
        ("RQ2",
         "How can parallel multi-agent orchestration reduce analysis latency",
         "and support cross-platform comparisons?"),
        ("RQ3",
         "How do structured prompt templates (skills) improve the reliability",
         "and consistency of an LLM agent for domain-specific workflows?"),
    ]

    y = H - 95
    for label, line1, line2 in rqs:
        # Blue label box
        c.setFillColor(TAU_BLUE)
        c.rect(28, y - 52, 60, 52, fill=1, stroke=0)
        c.setFillColor(WHITE)
        c.setFont("Helvetica-Bold", 16)
        c.drawCentredString(58, y - 32, label)

        # Text
        c.setFillColor(DARK_GREY)
        c.setFont("Helvetica", 14)
        c.drawString(105, y - 18, line1)
        c.drawString(105, y - 36, line2)

        y -= 110


    footer_line(c, 4)


def s05_architecture(c: canvas.Canvas):
    header_bar(c, "System Architecture", "Four layers: API \u2192 Agent \u2192 Tools \u2192 Data")

    headers = ["Layer", "Technology", "Responsibility"]
    rows = [
        ["API layer",   "FastAPI",      "Accepts user messages; returns final response"],
        ["Agent layer", "LangGraph",    "Runs the ReAct loop; manages conversation state"],
        ["Tool layer",  "Python / SQL", "3 tools: schema discovery & SQL execution"],
        ["Data layer",  "PostgreSQL",   "Marketing database (read-only access)"],
    ]
    col_widths = [100, 110, 400]
    table_box(c, headers, rows, x=28, y=H - 82, col_widths=col_widths, row_h=24)

    c.setFillColor(MID_GREY)
    c.setFont("Helvetica-Oblique", 12)
    c.drawString(28, H - 210,
                 "At runtime: user message \u2192 FastAPI \u2192 LangGraph ReAct loop \u2192 tool calls \u2192 final answer")

    # Flow boxes
    flow = ["User", "FastAPI", "LangGraph\nReAct", "Tools", "PostgreSQL"]
    colors_alt = [TAU_BLUE, ACCENT, TAU_BLUE, ACCENT, TAU_BLUE]
    fx = 28
    fy = H - 300
    bw = 130
    for i, (item, fc) in enumerate(zip(flow, colors_alt)):
        c.setFillColor(fc)
        c.rect(fx, fy, bw, 40, fill=1, stroke=0)
        c.setFillColor(WHITE)
        c.setFont("Helvetica-Bold", 11)
        lines = item.split("\n")
        if len(lines) == 2:
            c.drawCentredString(fx + bw / 2, fy + 26, lines[0])
            c.drawCentredString(fx + bw / 2, fy + 10, lines[1])
        else:
            c.drawCentredString(fx + bw / 2, fy + 14, item)
        if i < len(flow) - 1:
            c.setFillColor(TAU_BLUE)
            c.setFont("Helvetica-Bold", 16)
            c.drawString(fx + bw + 5, fy + 12, "\u2192")
        fx += bw + 30

    footer_line(c, 5)


def s06_tools(c: canvas.Canvas):
    header_bar(c, "Key Design #1 \u2014 Smart Agent, Simple Tools",
               "Only add a tool when it crosses a boundary the model cannot cross alone")

    headers = ["Tool", "Category", "Purpose"]
    rows = [
        ["`list_tables`",    "Schema", "List all tables with row counts"],
        ["`describe_table`", "Schema", "Show schema, sample rows, value distributions"],
        ["`query_data`",     "Data",   "Execute read-only SQL; return results to model"],
    ]
    col_widths = [130, 90, 400]
    table_box(c, headers, rows, x=28, y=H - 82, col_widths=col_widths, row_h=26)

    # Key insight box
    c.setFillColor(LIGHT_GREY)
    c.rect(28, H - 310, W - 56, 80, fill=1, stroke=0)
    c.setFillColor(TAU_BLUE)
    c.setFont("Helvetica-Bold", 13)
    c.drawString(45, H - 248, "Key insight:")
    c.setFont("Helvetica", 13)
    c.setFillColor(DARK_GREY)
    c.drawString(45, H - 268,
                 "Fewer tools = fewer decision points = lower latency + higher reliability.")
    c.drawString(45, H - 286,
                 "Tool descriptions are prompt engineering \u2014 they determine agent behaviour")
    c.drawString(45, H - 302, "more than the tool\u2019s implementation code.")

    footer_line(c, 6)


def s07_skills(c: canvas.Canvas):
    header_bar(c, "Key Design #2 \u2014 Skills System",
               "Structured workflow recipes injected into the agent\u2019s session context at runtime")

    c.setFillColor(TAU_BLUE)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(28, H - 93, "Problem:")
    c.setFont("Helvetica", 13)
    c.setFillColor(DARK_GREY)
    c.drawString(28, H - 113,
                 "The ReAct loop is flexible but unpredictable for complex multi-step workflows")
    c.drawString(28, H - 130,
                 "(e.g. weekly report: 6 SQL queries, 4 charts, Excel export, PDF assembly).")

    c.setFillColor(TAU_BLUE)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(28, H - 162, "Solution \u2014 a Skill:")

    skill_items = [
        "Trigger  (e.g. /weekly-report)",
        "Numbered step sequence the agent must follow",
        "Output format specs (chart sizes, Excel structure, PDF sections)",
        "Injected into session context \u2014 no new tools, no fine-tuning required",
    ]
    bullets(c, skill_items, x=40, y=H - 180, font_size=13, line_gap=26)

    # Analogy box
    c.setFillColor(BOX_BLUE)
    c.rect(28, H - 380, W - 56, 55, fill=1, stroke=0)
    c.setFillColor(TAU_BLUE)
    c.setFont("Helvetica-BoldOblique", 12)
    c.drawString(45, H - 350,
                 "Analogy: the agent already knows how to cook \u2014 the skill gives it a recipe")
    c.drawString(45, H - 368, "so every weekly report comes out the same.")

    footer_line(c, 7)


def s08_multiagent(c: canvas.Canvas):
    header_bar(c, "Key Design #3 \u2014 Parallel Multi-Agent Orchestration",
               "Lead agent spawns independent subagents; results combined via shared filesystem")

    # Left column
    c.setFillColor(TAU_BLUE)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(28, H - 92, "How it works:")

    how = [
        "Lead agent calls research_agent with N tasks",
        "Each task runs as an independent LangGraph graph",
        "Coroutines launched with asyncio.gather() in parallel",
        "Each subagent writes CSV results to shared filesystem",
        "Lead agent combines CSVs and generates final report",
    ]
    bullets(c, how, x=35, y=H - 112, font_size=13, line_gap=28, max_w=370)

    # Right box
    rx = W / 2 + 20
    rw = W / 2 - 48
    c.setFillColor(LIGHT_GREY)
    c.rect(rx, H - 330, rw, 250, fill=1, stroke=0)
    c.setFillColor(TAU_BLUE)
    c.setFont("Helvetica-Bold", 13)
    c.drawString(rx + 12, H - 102, "Evaluation result")
    c.setFillColor(DARK_GREY)
    c.setFont("Helvetica", 13)
    c.drawString(rx + 12, H - 130, "Google vs Meta Q1 comparison")
    c.setFont("Helvetica", 14)
    c.drawString(rx + 12, H - 170, "Sequential:   ~22 seconds")
    c.drawString(rx + 12, H - 195, "Parallel:        ~12 seconds")
    c.setFont("Helvetica-Bold", 14)
    c.setFillColor(TAU_BLUE)
    c.drawString(rx + 12, H - 230, "~45% reduction in wall-clock time")

    footer_line(c, 8)


def s09_evaluation(c: canvas.Canvas):
    header_bar(c, "Evaluation Results",
               "Six qualitative scenarios + prompt engineering experiment")

    headers = ["#", "Scenario", "Result"]
    rows = [
        ["1", "Simple question (spend last month)",        "Correct in ~5 s"],
        ["2", "Follow-up (break down by campaign type)",   "1 tool call, ~4 s; context reused"],
        ["3", "Trend analysis (30-day platform spend)",    "Correct aggregation + summary"],
        ["4", "ROAS investigation (why did it drop?)",     "4-step, 6 tool calls"],
        ["5", "Weekly report (skill active)",              "Zero omissions with skill"],
        ["6", "Parallel: Google vs Meta Q1",              "~45% faster than sequential"],
    ]
    col_widths = [22, 250, 350]
    table_box(c, headers, rows, x=28, y=H - 82, col_widths=col_widths, row_h=24,
              header_size=12, cell_size=11)

    # Prompt engineering
    c.setFillColor(BOX_BLUE)
    c.rect(28, H - 360, W - 56, 55, fill=1, stroke=0)
    c.setFillColor(TAU_BLUE)
    c.setFont("Helvetica-BoldOblique", 12)
    c.drawString(45, H - 325,
                 "Prompt engineering finding: same tool code, two descriptions \u2014 full description")
    c.drawString(45, H - 343,
                 "eliminated all schema hallucinations and write attempts.  Description > implementation.")

    footer_line(c, 9)


def s10_conclusions(c: canvas.Canvas):
    header_bar(c, "Conclusions & Future Work")

    # Left column
    col_w = W / 2 - 40

    c.setFillColor(TAU_BLUE)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(28, H - 92, "Contributions")

    contrib = [
        "Working LangGraph ReAct agent for marketing analytics",
        "Parallel multi-agent architecture (45% latency reduction)",
        "Skills system \u2014 reliability without fine-tuning",
        "Empirical: tool description matters more than code",
    ]
    bullets(c, contrib, x=35, y=H - 112, font_size=13, line_gap=26, max_w=col_w)

    c.setFillColor(TAU_BLUE)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(28, H - 255, "Answers to RQs")
    answers = [
        "RQ1: System prompt + skills + error messages = reliable agent",
        "RQ2: asyncio.gather() subagents + shared filesystem",
        "RQ3: Skills remove inference ambiguity; consistent output",
    ]
    bullets(c, answers, x=35, y=H - 275, font_size=12, line_gap=24, max_w=col_w)

    # Right column — future work
    rx = W / 2 + 10
    rw = W / 2 - 38
    c.setFillColor(LIGHT_GREY)
    c.rect(rx, H - 380, rw, 300, fill=1, stroke=0)
    c.setFillColor(TAU_BLUE)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(rx + 12, H - 100, "Future Work")

    future = [
        "Expand skill library (17 of 20 skills not yet built)",
        "Production infra (PostgreSQL checkpoints, scaling)",
        "Live platform APIs (Google Ads, Meta, LinkedIn)",
        "Prompt caching \u2192 ~70% inference cost reduction",
        "Quantitative benchmark evaluation at scale",
    ]
    bullets(c, future, x=rx + 18, y=H - 120, font_size=12, line_gap=26, max_w=rw - 20)

    footer_line(c, 10)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def build():
    out = "thesis-presentation.pdf"
    c = canvas.Canvas(out, pagesize=landscape(A4))
    c.setTitle("Design and Implementation of a LangGraph-Based Marketing Analytics Agent")
    c.setAuthor("Nhan Chau")

    slides = [
        s01_title, s02_agenda, s03_problem, s04_rqs, s05_architecture,
        s06_tools, s07_skills, s08_multiagent, s09_evaluation, s10_conclusions,
    ]
    for fn in slides:
        fn(c)
        c.showPage()

    c.save()
    print(f"Saved: {out}")


if __name__ == "__main__":
    build()
