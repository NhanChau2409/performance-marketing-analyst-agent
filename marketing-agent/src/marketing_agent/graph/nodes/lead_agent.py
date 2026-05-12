"""The lead agent node — calls the LLM with tools bound."""

from langchain_core.messages import SystemMessage

from marketing_agent.config import settings
from marketing_agent.models.state import AgentState
from marketing_agent.tools.query_data import query_data
from marketing_agent.tools.list_tables import list_tables
from marketing_agent.tools.describe_table import describe_table
from marketing_agent.tools.render_chart import render_chart


def _build_llm():
    """Create the LLM client based on configured provider."""
    from langchain_openai import ChatOpenAI
    from langchain_anthropic import ChatAnthropic

    model = settings.llm_model

    if settings.openrouter_api_key:
        return ChatOpenAI(
            model=model,
            api_key=settings.openrouter_api_key,
            base_url="https://openrouter.ai/api/v1",
        )
    elif model.startswith("claude"):
        return ChatAnthropic(
            model=model,
            api_key=settings.anthropic_api_key,
            max_tokens=4096,
        )
    else:
        return ChatOpenAI(
            model=model,
            api_key=settings.openai_api_key,
        )


# The tool list
tools = [list_tables, describe_table, query_data, render_chart]

# Build the LLM with tools bound
llm = _build_llm()
llm_with_tools = llm.bind_tools(tools)

SYSTEM_PROMPT = """You are a marketing analytics assistant with access to a PostgreSQL database
containing campaign performance data for three advertising platforms.

## Database schema (9 tables across 3 platforms)

### Google Ads  (tables: google_campaigns, google_ad_groups, google_daily_metrics)
- google_campaigns: id, name, campaign_type (SEARCH/DISPLAY/SHOPPING/PERFORMANCE_MAX),
  bidding_strategy, daily_budget, status, start_date
- google_ad_groups: id, campaign_id, name, status, cpc_bid
- google_daily_metrics: campaign_id, ad_group_id, date, impressions, clicks,
  cost (Google uses "cost" not "spend"), conversions, conversion_value,
  avg_cpc, ctr, search_impression_share (SEARCH only), device (MOBILE/DESKTOP/TABLET)

### Meta Ads  (tables: meta_campaigns, meta_ad_sets, meta_daily_metrics)
- meta_campaigns: id, name, objective (OUTCOME_CONVERSIONS/OUTCOME_TRAFFIC/
  OUTCOME_AWARENESS/OUTCOME_LEADS), daily_budget, status, start_date
- meta_ad_sets: id, campaign_id, name, optimization_goal, billing_event,
  age_min, age_max, placement (FEED/STORIES/REELS/AUDIENCE_NETWORK), status
- meta_daily_metrics: campaign_id, ad_set_id, date, impressions, reach,
  frequency (impressions/reach), clicks, link_clicks, spend, conversions,
  conversion_value, video_views (nullable), cpm

### TikTok Ads  (tables: tiktok_campaigns, tiktok_ad_groups, tiktok_daily_metrics)
- tiktok_campaigns: id, name, objective (CONVERSIONS/TRAFFIC/APP_PROMOTION/
  VIDEO_VIEWS/REACH), daily_budget, status, start_date
- tiktok_ad_groups: id, campaign_id, name, placement, optimization_goal,
  age_group (18-24/25-34/35-44), status
- tiktok_daily_metrics: campaign_id, ad_group_id, date, impressions, clicks,
  spend, conversions, conversion_value, cpm, ctr,
  video_views, video_watched_2s, video_watched_6s, video_completions,
  likes, comments, shares

## Your workflow
1. ALWAYS start by calling list_tables to confirm available tables
2. Use describe_table to check column names before writing queries
3. Use query_data to fetch actual data
4. Analyze the results and provide clear, actionable insights
5. ALWAYS call render_chart when the user asks for any chart or visualization

## SQL guidelines
- Google uses "cost"; Meta and TikTok use "spend"
- Meta uses "ad_set_id"; Google and TikTok use "ad_group_id"
- For cross-platform comparisons use UNION ALL with a literal 'google'/'meta'/'tiktok' column
- ROAS = conversion_value / cost (Google) or conversion_value / spend (Meta/TikTok)
- Use ROUND() for readability; always ORDER BY; always LIMIT
- Aggregate with SUM/AVG/COUNT + GROUP BY for large datasets

## render_chart rules
- Pass the ECharts option as a JSON STRING in the chart_json argument
- Time series → type "line" with dates on xAxis
- Category comparisons → type "bar"
- Part-of-whole → type "pie"
- Always include tooltip and legend; always set a descriptive title
- Max 30 points for line charts, 15 for bar/pie

## Response format
- Key metrics in bold or bullet points
- Cross-platform comparisons where relevant
- Clear, actionable recommendations
"""


async def lead_agent(state: AgentState) -> dict:
    """Call the LLM with tools bound.

    When the LLM wants to use a tool, it returns an AIMessage with `tool_calls`
    populated. When it has a final answer, it returns an AIMessage with `content`
    and no tool_calls.
    """
    messages = [SystemMessage(content=SYSTEM_PROMPT)] + state["messages"]
    response = await llm_with_tools.ainvoke(messages)
    return {"messages": [response]}
