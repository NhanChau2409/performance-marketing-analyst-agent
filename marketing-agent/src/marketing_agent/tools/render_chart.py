"""Tool: return an ECharts option object for the frontend to render."""

import json

from langchain_core.tools import tool


@tool
def render_chart(chart_json: str) -> str:
    """Render a visualization chart using ECharts.

    Call this AFTER query_data when the user asks for a chart or when data
    is well-suited for visualization.

    Pass a JSON STRING of the complete ECharts option object as chart_json.

    Chart type guidelines:
    - Time series (daily/weekly trends) → type "line", dates on xAxis
    - Category comparisons (platforms, campaigns, ad groups) → type "bar"
    - Part-of-whole (budget split, channel mix) → type "pie"
    - Always include tooltip and legend

    Example bar chart (pass this as a JSON string):
    {"title":{"text":"ROAS by Platform"},"tooltip":{},"legend":{},"xAxis":{"type":"category","data":["Google","Meta","TikTok"]},"yAxis":{"type":"value"},"series":[{"type":"bar","data":[4.2,3.1,2.8],"name":"ROAS"}]}

    Args:
        chart_json: JSON string of the complete ECharts option object.
    """
    json.loads(chart_json)  # validate — raises if malformed
    return chart_json
