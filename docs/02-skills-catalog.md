# Marketing Analytics Agent — Skills Catalog

> **Status**: POC / Idea Phase  
> **Date**: 2026-04-03  
> **Companion to**: [01-proposal.md](01-proposal.md)

---

## How Skills Work

A skill is a **Markdown prompt template** (`SKILL.md`) that tells the agent exactly
what to do for a specific use case — what data to fetch, what analysis to run, what
output to produce. Users trigger skills via slash commands (e.g., `/weekly-report`)
or the agent can activate them automatically based on what the user asks.

Skills don't contain code. They orchestrate the agent's **4 simple tools**
(`query_data`, `list_tables`, `describe_table`, `python_exec`) — following the
"smart agent, simple tools" pattern. The agent writes all Python code (analysis,
charts, Excel, PDFs, file I/O) itself via `python_exec`.

```
User: "/weekly-report google-ads last 4 weeks"
                │
                ▼
        Skill loaded → agent receives structured instructions
                │
                ▼
        Agent follows steps: query → analyze → chart → export
                │
                ▼
        Formatted report delivered to user
```

---

## Skills Overview

We identified **8 categories** of marketing analysis from common industry workflows.
Each category maps to 1-3 skills. Total: **20 skills**.

| # | Category | Skills | Frequency |
|---|----------|--------|-----------|
| 1 | Routine Reports | 4 skills | Weekly / Monthly / Quarterly |
| 2 | Campaign Analysis | 3 skills | Per campaign |
| 3 | Channel & Platform | 3 skills | Weekly / Monthly |
| 4 | Audience & Creative | 2 skills | Monthly / Quarterly |
| 5 | Budget & ROI | 3 skills | Monthly / Quarterly |
| 6 | Anomaly Investigation | 2 skills | Ad hoc |
| 7 | Funnel & Attribution | 2 skills | Monthly / Quarterly |
| 8 | Competitive | 1 skill | Monthly / Quarterly |

---

## Category 1: Routine Reports

### Skill: `weekly-report`

> The single most common marketing task. Every team does this every Monday.

```
Trigger:  /weekly-report [platform] [date-range]
Example:  /weekly-report all last-week
          /weekly-report google-ads 2026-03-24 to 2026-03-30
```

**What it does:**
1. Query last 7 days of `daily_metrics` joined with `campaigns`, grouped by day and platform
2. Calculate WoW changes for: spend, impressions, clicks, CTR, CPC, conversions, ROAS
3. Identify top 5 and bottom 5 campaigns by ROAS
4. Generate charts: daily spend trend line, platform comparison bar chart
5. Generate Excel with sheets: daily data, platform summary, top/bottom campaigns
6. Compile report with executive summary, tables, charts, and WoW arrows (↑↓)

**Output:** Markdown report + charts + Excel download  
**Consumer:** Marketing manager, VP Marketing  
**Data needed:** `daily_metrics`, `campaigns`

---

### Skill: `monthly-report`

> Full-month review. Usually takes an analyst 4-8 hours manually.

```
Trigger:  /monthly-report [month] [year]
Example:  /monthly-report march 2026
          /monthly-report last-month
```

**What it does:**
1. Query full month of data across all platforms
2. Calculate MoM and YoY comparisons for all KPIs
3. Break down by: platform, campaign type, ad group, top creatives
4. Generate charts:
   - Daily spend + conversions trend (dual axis line)
   - Platform performance comparison (grouped bar)
   - Campaign type mix (pie/donut)
   - ROAS trend vs. prior month (line)
   - Top 10 campaigns (horizontal bar)
5. Generate Excel with: raw data, platform pivot, campaign pivot, daily trends, YoY comparison
6. Compile PDF report with sections:
   - Executive summary (3-5 key takeaways)
   - Platform performance
   - Campaign performance
   - Creative performance
   - Audience insights
   - Budget utilization
   - Recommendations

**Output:** PDF report + Excel + charts  
**Consumer:** CMO, VP Marketing, cross-functional leadership  
**Data needed:** `daily_metrics`, `campaigns`, `ads`, `audience_segments`

---

### Skill: `quarterly-review`

> Strategic review for leadership. Trend analysis + budget recommendations.

```
Trigger:  /quarterly-review [quarter] [year]
Example:  /quarterly-review Q1 2026
```

**What it does:**
1. Query 3 months of data + same quarter prior year
2. Calculate quarterly totals, QoQ trends, YoY trends
3. Assess goal attainment (if goals are configured)
4. Budget utilization analysis (planned vs. actual)
5. Channel efficiency ranking with ROI
6. Generate charts:
   - Monthly trend within quarter (line)
   - Channel mix waterfall (spend vs. revenue contribution)
   - YoY comparison (grouped bar)
   - Efficiency frontier (scatter: spend vs. ROAS by campaign)
7. Generate recommendations for next quarter budget allocation
8. Compile executive PDF (slide-deck style)

**Output:** Executive PDF + Excel + charts  
**Consumer:** CMO, CEO, CFO  
**Data needed:** `daily_metrics`, `campaigns`, `ads`, `audience_segments` + budget config

---

### Skill: `email-report`

> Email marketing performance. Typically weekly summary + monthly deep dive.

```
Trigger:  /email-report [period]
Example:  /email-report last-week
          /email-report march-2026
```

**What it does:**
1. Query email send/delivery/open/click/bounce/unsubscribe data
2. Calculate key metrics: open rate, CTR, click-to-open rate, unsubscribe rate, deliverability
3. Rank emails by engagement score
4. Identify trends: is deliverability declining? Open rates dropping?
5. Generate charts: engagement trend, per-email comparison bar, list health gauge
6. A/B test results summary (if any)

**Output:** Markdown report + charts  
**Consumer:** Email marketing manager, content team  
**Data needed:** Email platform data (separate table or API integration)

---

## Category 2: Campaign Analysis

### Skill: `campaign-analysis`

> Post-campaign retrospective. "Did this campaign work?"

```
Trigger:  /campaign-analysis [campaign-name-or-id]
Example:  /campaign-analysis "Q1 Brand Search - US"
          /campaign-analysis campaign_id=abc123
```

**What it does:**
1. Fetch all data for the specified campaign (metrics, ad groups, ads, audiences)
2. Calculate total performance: spend, impressions, clicks, CTR, conversions, ROAS, CPA
3. Break down by: ad group, creative, audience segment, day, device, geo (if available)
4. Identify best and worst performing ad groups / creatives / audiences
5. Generate funnel: impressions → clicks → conversions (with rates at each step)
6. Compare to benchmark (avg of similar campaigns, same platform/type)
7. Generate charts:
   - Daily performance trend
   - Ad group comparison bar
   - Creative performance matrix
   - Audience segment heatmap
8. Recommendations: what to keep, what to cut, what to test next

**Output:** Markdown report + charts + Excel breakdown  
**Consumer:** Campaign manager, marketing team  
**Data needed:** `daily_metrics`, `campaigns`, `ad_groups`, `ads`, `audience_segments`

---

### Skill: `campaign-comparison`

> Side-by-side comparison of 2+ campaigns or platforms.

```
Trigger:  /campaign-comparison [campaign-a] vs [campaign-b]
Example:  /campaign-comparison "Brand Search" vs "Brand Display" 
          /campaign-comparison google vs meta Q1-2026
```

**What it does:**
1. Fetch data for both campaigns/platforms
2. Normalize metrics for fair comparison (e.g., per-$1000-spend basis)
3. Side-by-side KPI table: spend, CPM, CPC, CTR, conversion rate, CPA, ROAS
4. Generate charts:
   - Grouped bar: KPI comparison
   - Dual-axis line: daily trends overlaid
   - Scatter: spend efficiency comparison
5. Declare winner per metric, overall assessment
6. Recommendation: where to shift budget

**Output:** Markdown report + comparison charts  
**Consumer:** Campaign manager, VP Marketing  
**Data needed:** `daily_metrics`, `campaigns`

---

### Skill: `ab-test-analysis`

> Statistical analysis of A/B test variants.

```
Trigger:  /ab-test-analysis [test-name-or-ids]
Example:  /ab-test-analysis ad_id=abc vs ad_id=xyz
```

**What it does:**
1. Fetch variant-level data (impressions, clicks, conversions per variant)
2. Calculate conversion rates per variant
3. Run statistical significance test (chi-squared or z-test)
4. Calculate confidence interval, p-value, lift percentage
5. Declare winner (or "not yet significant — need N more impressions")
6. Generate chart: variant comparison with confidence intervals

**Output:** Markdown summary + chart  
**Consumer:** Campaign manager, growth team  
**Data needed:** `daily_metrics`, `ads`

---

## Category 3: Channel & Platform Analysis

### Skill: `paid-media-review`

> Deep dive into paid channels. The weekly optimization review.

```
Trigger:  /paid-media-review [platform] [period]
Example:  /paid-media-review google-ads last-week
          /paid-media-review all march-2026
```

**What it does:**
1. Query all paid campaigns for the period, grouped by platform/campaign/ad-group
2. Calculate: spend, CPM, CPC, CTR, conversion rate, CPA, ROAS for each level
3. Identify:
   - Budget pacing (on track vs. over/underspending?)
   - Campaigns with degrading performance (WoW CTR/ROAS decline)
   - High-spend, low-ROAS campaigns (waste candidates)
   - Low-spend, high-ROAS campaigns (scale candidates)
4. Generate charts:
   - Spend vs. ROAS scatter (bubble size = conversions)
   - Performance trend lines by campaign
   - Budget pacing bar (planned vs. actual)
5. Action items: pause, scale, adjust bids, refresh creative

**Output:** Markdown report + charts + Excel  
**Consumer:** Paid media specialist, marketing manager  
**Data needed:** `daily_metrics`, `campaigns`, `ad_groups`

---

### Skill: `content-performance`

> Which content drives traffic, engagement, and leads?

```
Trigger:  /content-performance [period]
Example:  /content-performance last-30-days
```

**What it does:**
1. Query content-level metrics (page views, time on page, bounce rate, conversions)
2. Rank content by composite score (traffic × engagement × conversion weight)
3. Identify: top performers, declining content, new content performance
4. Generate charts:
   - Top 20 content by composite score (horizontal bar)
   - Content age vs. performance (scatter — find content decay)
   - Content type breakdown (pie)
5. Recommendations: refresh candidates, gaps, promotion opportunities

**Output:** Markdown report + charts  
**Consumer:** Content team, SEO team  
**Data needed:** Web analytics data (content table + metrics)

---

### Skill: `channel-mix`

> Cross-channel efficiency comparison. Where should we invest?

```
Trigger:  /channel-mix [period]
Example:  /channel-mix Q1-2026
```

**What it does:**
1. Query spend, leads, pipeline, revenue by channel (paid search, paid social, organic,
   email, referral, direct, events)
2. Calculate per-channel: CPL, CPA, ROAS, % of total spend, % of total revenue
3. Identify over-invested channels (high spend %, low revenue %) and under-invested ones
4. Generate charts:
   - Spend allocation pie vs. revenue contribution pie (side by side)
   - Channel efficiency matrix (quadrant: high/low spend × high/low ROAS)
   - Marginal CPL trend by channel (are we hitting diminishing returns?)
5. Budget reallocation recommendation with projected impact

**Output:** Markdown report + charts + reallocation Excel model  
**Consumer:** VP Marketing, CMO, CFO  
**Data needed:** `daily_metrics`, `campaigns`, attribution data

---

## Category 4: Audience & Creative

### Skill: `audience-analysis`

> Which audiences convert best? Are we targeting the right people?

```
Trigger:  /audience-analysis [platform] [period]
Example:  /audience-analysis meta Q1-2026
```

**What it does:**
1. Query audience segment performance data
2. Rank segments by: conversion rate, CPA, ROAS, volume
3. Calculate ICP fit (if ICP criteria are configured)
4. Identify: high-value segments to scale, low-value segments to exclude
5. Generate charts:
   - Segment performance heatmap (segments × metrics)
   - Top segments horizontal bar
   - Segment size vs. conversion rate scatter
6. Targeting recommendations

**Output:** Markdown report + heatmap + charts  
**Consumer:** Demand gen, product marketing  
**Data needed:** `audience_segments`, `daily_metrics`, `campaigns`

---

### Skill: `creative-analysis`

> Which ads/creatives work best? What patterns win?

```
Trigger:  /creative-analysis [platform] [period]
Example:  /creative-analysis google-ads last-30-days
```

**What it does:**
1. Query ad-level (creative-level) performance data
2. Group by creative attributes: type (image/video/text), headline theme, CTA type
3. Rank by CTR, conversion rate, ROAS
4. Identify winning patterns (e.g., "video creatives have 2x CTR vs. static images")
5. Identify creative fatigue (CTR declining over time for same creative)
6. Generate charts:
   - Creative type comparison (grouped bar)
   - Top 10 creatives (horizontal bar)
   - Creative fatigue curve (CTR over time for top creatives)
7. Recommendations: winning patterns to replicate, fatigued creatives to refresh

**Output:** Markdown report + charts  
**Consumer:** Creative team, campaign managers  
**Data needed:** `ads`, `daily_metrics`

---

## Category 5: Budget & ROI

### Skill: `budget-tracker`

> Planned vs. actual spend. Am I overspending or underspending?

```
Trigger:  /budget-tracker [period]
Example:  /budget-tracker march-2026
          /budget-tracker Q1-2026
```

**What it does:**
1. Query actual spend by channel/campaign/line-item
2. Compare against planned budget (from budget config or uploaded spreadsheet)
3. Calculate: variance, burn rate, projected end-of-period spend
4. Flag: overspending channels (>110% of plan), underspending (<80% of plan)
5. Generate charts:
   - Budget vs. actual bar (by channel)
   - Burn rate line (cumulative spend vs. plan over time)
   - Variance waterfall
6. Reallocation suggestions if some channels are under-budget

**Output:** Markdown report + charts + Excel  
**Consumer:** Marketing ops, VP Marketing, CFO  
**Data needed:** `daily_metrics` (actual spend), budget config table

---

### Skill: `roi-analysis`

> Channel-level ROI. Where is the money working hardest?

```
Trigger:  /roi-analysis [period]
Example:  /roi-analysis Q1-2026
```

**What it does:**
1. Query spend, conversions, revenue by channel
2. Calculate per-channel: CPL, CPA, ROAS, CAC, contribution margin
3. Rank channels by efficiency
4. Calculate blended metrics across all channels
5. Generate charts:
   - ROAS by channel (bar, sorted)
   - Spend vs. revenue scatter (with break-even line)
   - Efficiency trend over time (line)
6. Highlight: best ROI channels, worst ROI channels, break-even channels

**Output:** Markdown report + charts + Excel  
**Consumer:** CMO, CFO, VP Marketing  
**Data needed:** `daily_metrics`, `campaigns`, revenue data

---

### Skill: `budget-optimizer`

> Data-driven budget reallocation recommendation.

```
Trigger:  /budget-optimizer [total-budget] [period]
Example:  /budget-optimizer $500K next-quarter
```

**What it does:**
1. Query historical performance by channel (3-6 months)
2. Calculate marginal returns per channel (does more spend = proportionally more output?)
3. Identify diminishing returns thresholds
4. Model scenarios:
   - Current allocation (baseline)
   - Optimized allocation (shift from low-ROI to high-ROI)
   - Aggressive growth (maximize volume, accept lower efficiency)
   - Conservative (maximize efficiency, accept lower volume)
5. Generate charts:
   - Current vs. optimized allocation (side-by-side pie/bar)
   - Projected impact table (spend, leads, revenue per scenario)
   - Marginal CPL curves by channel
6. Deliver recommendation with projected impact

**Output:** Markdown report + scenario Excel model + charts  
**Consumer:** CMO, CFO, VP Marketing  
**Data needed:** `daily_metrics`, `campaigns` (historical), budget constraints

---

## Category 6: Anomaly Investigation

### Skill: `investigate-drop`

> Something went wrong. Find out why.

```
Trigger:  /investigate-drop [metric] [timeframe]
Example:  /investigate-drop roas last-week
          /investigate-drop leads march-15-to-march-22
          /investigate-drop ctr meta last-7-days
```

**What it does:**
1. Confirm the drop: query the metric over time, quantify the change
2. Narrow down scope:
   - Which platform(s) are affected?
   - Which campaign(s)?
   - Which ad groups / creatives / audiences?
   - Which days specifically?
3. Check common causes:
   - Spend change? (budget cut → fewer impressions → fewer conversions)
   - CTR drop? (creative fatigue, competitor activity, audience exhaustion)
   - Conversion rate drop? (landing page issue, tracking broken, offer expired)
   - CPC increase? (auction competition, quality score, seasonal demand)
   - External factors? (holiday, news event, platform algorithm change)
4. Generate charts:
   - Metric trend with anomaly highlighted
   - Breakdown by the dimension causing the drop
   - Comparison: affected vs. unaffected campaigns
5. Root cause assessment + recommended action

**Output:** Investigation report with root cause + next steps  
**Consumer:** Marketing manager, paid media specialist  
**Data needed:** `daily_metrics`, `campaigns`, `ad_groups`, `ads`

---

### Skill: `cost-spike`

> CPC/CPL/CPA suddenly increased. Why?

```
Trigger:  /cost-spike [metric] [platform] [period]
Example:  /cost-spike cpc google-ads last-week
          /cost-spike cpa meta march-2026
```

**What it does:**
1. Confirm the spike: trend the cost metric, quantify increase
2. Break down by campaign / ad group / keyword / audience to isolate
3. Check causes:
   - Auction competition increased? (impression share dropped)
   - Quality/relevance score dropped?
   - Audience saturation? (frequency too high)
   - Creative fatigue? (same ads running too long, CTR declining)
   - Conversion tracking issue? (costs same but conversions undercounted)
   - Seasonal/event-driven demand increase?
4. Generate charts:
   - Cost trend with spike highlighted
   - Component breakdown (CPM × CTR × CVR = CPA)
   - Before/after comparison by dimension
5. Recommended actions (refresh creative, adjust bids, expand audience, etc.)

**Output:** Investigation report with diagnosis + actions  
**Consumer:** Paid media specialist, marketing manager  
**Data needed:** `daily_metrics`, `campaigns`, `ad_groups`, `ads`

---

## Category 7: Funnel & Attribution

### Skill: `funnel-analysis`

> Where are we losing people? Conversion rates between stages.

```
Trigger:  /funnel-analysis [period]
Example:  /funnel-analysis Q1-2026
          /funnel-analysis last-30-days
```

**What it does:**
1. Query volume at each funnel stage: impression → click → lead → MQL → SQL → opportunity → closed
2. Calculate conversion rates between each stage
3. Calculate velocity (median days between stages)
4. Compare to prior period (MoM or QoQ)
5. Identify biggest bottleneck (lowest conversion rate stage)
6. Break down by channel/platform to see which channels have best full-funnel conversion
7. Generate charts:
   - Funnel visualization (horizontal bar, shrinking)
   - Stage conversion rates (bar chart with period comparison)
   - Velocity by stage (time chart)
   - Channel × stage heatmap
8. Recommendations: which stage to focus on, which channels have best end-to-end conversion

**Output:** Markdown report + funnel chart + Excel  
**Consumer:** VP Marketing, demand gen, sales leadership  
**Data needed:** `daily_metrics`, `campaigns`, CRM funnel data

---

### Skill: `attribution-report`

> Which channels/campaigns deserve credit for revenue?

```
Trigger:  /attribution-report [model] [period]
Example:  /attribution-report last-touch Q1-2026
          /attribution-report linear last-quarter
```

**What it does:**
1. Query touchpoint data with conversion outcomes
2. Apply attribution model (first-touch, last-touch, linear, time-decay, position-based)
3. Calculate per-channel: attributed revenue, attributed conversions, ROAS under model
4. Compare models: how does credit shift between first-touch and last-touch?
5. Generate charts:
   - Revenue attribution by channel (stacked bar)
   - Model comparison (grouped bar: same channels, different models)
   - Touch sequence analysis (most common conversion paths)
6. Insights: which channels are "assisters" vs. "closers"

**Output:** Markdown report + charts + Excel  
**Consumer:** VP Marketing, marketing ops, CFO  
**Data needed:** Multi-touch attribution data (touchpoint table + conversions)

---

## Category 8: Competitive

### Skill: `competitive-benchmark`

> How do we compare to industry averages?

```
Trigger:  /competitive-benchmark [industry] [period]
Example:  /competitive-benchmark saas Q1-2026
          /competitive-benchmark ecommerce last-quarter
```

**What it does:**
1. Calculate our key metrics: CTR, CPC, CPL, conversion rate, ROAS, email open rate
2. Look up industry benchmarks (from stored benchmark data or web search)
3. Compare: above/below benchmark for each metric, by how much
4. Identify strengths (significantly above benchmark) and weaknesses (below)
5. Generate charts:
   - Benchmark comparison bar (our value vs. industry avg, per metric)
   - Radar/spider chart (multi-metric profile vs. benchmark)
6. Prioritized improvement recommendations (focus on biggest gaps)

**Output:** Markdown report + charts  
**Consumer:** VP Marketing, CMO  
**Data needed:** Internal metrics + industry benchmark data

---

## POC Priority: Which Skills to Build First?

Based on frequency, user value, and implementation simplicity:

### Phase 1 (MVP — build these first)

| Priority | Skill | Why |
|----------|-------|-----|
| P0 | `weekly-report` | Highest frequency, every team needs it, straightforward data flow |
| P0 | `campaign-analysis` | Core use case — "how did this campaign do?" |
| P0 | `investigate-drop` | Highest value — saves hours of manual root cause analysis |

### Phase 2 (Core — build after MVP works)

| Priority | Skill | Why |
|----------|-------|-----|
| P1 | `monthly-report` | Extension of weekly, more comprehensive |
| P1 | `campaign-comparison` | Natural follow-up to campaign analysis |
| P1 | `paid-media-review` | Weekly optimization workflow for paid teams |
| P1 | `budget-tracker` | Simple but high-value for management reporting |

### Phase 3 (Advanced — build when data layer is richer)

| Priority | Skill | Why |
|----------|-------|-----|
| P2 | `roi-analysis` | Needs revenue attribution data |
| P2 | `channel-mix` | Needs cross-channel attribution |
| P2 | `audience-analysis` | Needs audience segment data |
| P2 | `creative-analysis` | Needs creative-level data |
| P2 | `funnel-analysis` | Needs CRM funnel stage data |
| P2 | `cost-spike` | Specialized investigation |
| P2 | `budget-optimizer` | Needs historical depth + modeling |

### Phase 4 (Nice-to-have)

| Priority | Skill | Why |
|----------|-------|-----|
| P3 | `quarterly-review` | Extension of monthly |
| P3 | `attribution-report` | Needs multi-touch attribution data |
| P3 | `competitive-benchmark` | Needs external benchmark data |
| P3 | `ab-test-analysis` | Niche use case |
| P3 | `email-report` | Needs email platform integration |
| P3 | `content-performance` | Needs web analytics integration |

---

## Skills vs. Ad-Hoc Questions

Skills handle **structured, repeatable workflows**. But users will also ask
**ad-hoc questions** that don't map to any skill:

- "What's our best-performing ad creative this month?"
- "How much did we spend on LinkedIn in February?"
- "Show me daily conversions for the last 2 weeks"

The lead agent handles these directly using the base tools (`query_data`,
`python_exec`) without needing a skill. Skills are for the complex,
multi-step workflows that would be hard for the agent to get right without
structured instructions.

```
User question
    │
    ├── Matches a skill?  → Load skill, follow structured workflow
    │
    └── Ad-hoc question?  → Agent uses tools directly (query_data, python_exec)
```
