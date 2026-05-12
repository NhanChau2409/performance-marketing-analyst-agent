"""Seed the marketing database with platform-realistic synthetic data.

Creates 9 tables across 3 platform groups (Google Ads, Meta, TikTok), each
modelled after the respective platform's reporting API:
  - Google Ads API Field Reference: developers.google.com/google-ads/api/fields
  - Meta Ads Insights API: developers.facebook.com/docs/marketing-api/reference/ads-insights/
  - TikTok Ads API: ads.tiktok.com/marketing_api/docs

Generates 181 days of daily metrics (2025-10-01 to 2026-03-31) with
platform-specific performance envelopes, weekday/weekend variation, and a
monthly growth trend.
"""

import asyncio
import random
from datetime import date, timedelta

from sqlalchemy import text

from marketing_agent.db.connection import engine

START_DATE = date(2025, 10, 1)
END_DATE = date(2026, 3, 31)
DAYS = list(
    START_DATE + timedelta(n)
    for n in range((END_DATE - START_DATE).days + 1)
)


# ---------------------------------------------------------------------------
# Schema DDL
# ---------------------------------------------------------------------------

DROP_STATEMENTS = [
    "DROP TABLE IF EXISTS tiktok_daily_metrics CASCADE",
    "DROP TABLE IF EXISTS tiktok_ad_groups     CASCADE",
    "DROP TABLE IF EXISTS tiktok_campaigns     CASCADE",
    "DROP TABLE IF EXISTS meta_daily_metrics   CASCADE",
    "DROP TABLE IF EXISTS meta_ad_sets         CASCADE",
    "DROP TABLE IF EXISTS meta_campaigns       CASCADE",
    "DROP TABLE IF EXISTS google_daily_metrics CASCADE",
    "DROP TABLE IF EXISTS google_ad_groups     CASCADE",
    "DROP TABLE IF EXISTS google_campaigns     CASCADE",
]

CREATE_STATEMENTS = [
    # ── Google Ads ───────────────────────────────────────────────────────────
    """CREATE TABLE google_campaigns (
        id               SERIAL PRIMARY KEY,
        name             VARCHAR(200) NOT NULL,
        campaign_type    VARCHAR(50)  NOT NULL,
        bidding_strategy VARCHAR(50)  NOT NULL,
        daily_budget     NUMERIC(10,2) NOT NULL,
        status           VARCHAR(20)  NOT NULL DEFAULT 'ENABLED',
        start_date       DATE NOT NULL
    )""",
    """CREATE TABLE google_ad_groups (
        id          SERIAL PRIMARY KEY,
        campaign_id INTEGER REFERENCES google_campaigns(id),
        name        VARCHAR(200) NOT NULL,
        status      VARCHAR(20)  NOT NULL DEFAULT 'ENABLED',
        cpc_bid     NUMERIC(10,4)
    )""",
    """CREATE TABLE google_daily_metrics (
        id                      SERIAL PRIMARY KEY,
        campaign_id             INTEGER REFERENCES google_campaigns(id),
        ad_group_id             INTEGER REFERENCES google_ad_groups(id),
        date                    DATE    NOT NULL,
        impressions             INTEGER NOT NULL DEFAULT 0,
        clicks                  INTEGER NOT NULL DEFAULT 0,
        cost                    NUMERIC(10,2) NOT NULL DEFAULT 0,
        conversions             NUMERIC(10,2) NOT NULL DEFAULT 0,
        conversion_value        NUMERIC(10,2) NOT NULL DEFAULT 0,
        avg_cpc                 NUMERIC(10,4),
        ctr                     NUMERIC(8,6),
        search_impression_share NUMERIC(5,4),
        device                  VARCHAR(20) NOT NULL
    )""",
    # ── Meta Ads ─────────────────────────────────────────────────────────────
    """CREATE TABLE meta_campaigns (
        id           SERIAL PRIMARY KEY,
        name         VARCHAR(200) NOT NULL,
        objective    VARCHAR(60)  NOT NULL,
        daily_budget NUMERIC(10,2) NOT NULL,
        status       VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
        start_date   DATE NOT NULL
    )""",
    """CREATE TABLE meta_ad_sets (
        id                SERIAL PRIMARY KEY,
        campaign_id       INTEGER REFERENCES meta_campaigns(id),
        name              VARCHAR(200) NOT NULL,
        optimization_goal VARCHAR(50)  NOT NULL,
        billing_event     VARCHAR(30)  NOT NULL,
        age_min           INTEGER,
        age_max           INTEGER,
        placement         VARCHAR(30)  NOT NULL,
        status            VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE'
    )""",
    """CREATE TABLE meta_daily_metrics (
        id               SERIAL PRIMARY KEY,
        campaign_id      INTEGER REFERENCES meta_campaigns(id),
        ad_set_id        INTEGER REFERENCES meta_ad_sets(id),
        date             DATE    NOT NULL,
        impressions      INTEGER NOT NULL DEFAULT 0,
        reach            INTEGER NOT NULL DEFAULT 0,
        frequency        NUMERIC(6,3) NOT NULL DEFAULT 0,
        clicks           INTEGER NOT NULL DEFAULT 0,
        link_clicks      INTEGER NOT NULL DEFAULT 0,
        spend            NUMERIC(10,2) NOT NULL DEFAULT 0,
        conversions      INTEGER NOT NULL DEFAULT 0,
        conversion_value NUMERIC(10,2) NOT NULL DEFAULT 0,
        video_views      INTEGER,
        cpm              NUMERIC(10,4)
    )""",
    # ── TikTok Ads ────────────────────────────────────────────────────────────
    """CREATE TABLE tiktok_campaigns (
        id           SERIAL PRIMARY KEY,
        name         VARCHAR(200) NOT NULL,
        objective    VARCHAR(40)  NOT NULL,
        daily_budget NUMERIC(10,2) NOT NULL,
        status       VARCHAR(20)  NOT NULL DEFAULT 'ENABLE',
        start_date   DATE NOT NULL
    )""",
    """CREATE TABLE tiktok_ad_groups (
        id                SERIAL PRIMARY KEY,
        campaign_id       INTEGER REFERENCES tiktok_campaigns(id),
        name              VARCHAR(200) NOT NULL,
        placement         VARCHAR(20)  NOT NULL DEFAULT 'TIKTOK',
        optimization_goal VARCHAR(30)  NOT NULL,
        age_group         VARCHAR(20),
        status            VARCHAR(20)  NOT NULL DEFAULT 'ENABLE'
    )""",
    """CREATE TABLE tiktok_daily_metrics (
        id               SERIAL PRIMARY KEY,
        campaign_id      INTEGER REFERENCES tiktok_campaigns(id),
        ad_group_id      INTEGER REFERENCES tiktok_ad_groups(id),
        date             DATE    NOT NULL,
        impressions      INTEGER NOT NULL DEFAULT 0,
        clicks           INTEGER NOT NULL DEFAULT 0,
        spend            NUMERIC(10,2) NOT NULL DEFAULT 0,
        conversions      INTEGER NOT NULL DEFAULT 0,
        conversion_value NUMERIC(10,2) NOT NULL DEFAULT 0,
        cpm              NUMERIC(10,4),
        ctr              NUMERIC(8,6),
        video_views       INTEGER NOT NULL DEFAULT 0,
        video_watched_2s  INTEGER NOT NULL DEFAULT 0,
        video_watched_6s  INTEGER NOT NULL DEFAULT 0,
        video_completions INTEGER NOT NULL DEFAULT 0,
        likes    INTEGER NOT NULL DEFAULT 0,
        comments INTEGER NOT NULL DEFAULT 0,
        shares   INTEGER NOT NULL DEFAULT 0
    )""",
]


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

def day_factor(d: date) -> float:
    """Weekend × growth-trend multiplier."""
    weekend = 0.6 if d.weekday() >= 5 else 1.0
    months_since_start = (d.year - START_DATE.year) * 12 + (d.month - START_DATE.month)
    growth = 1.0 + 0.10 * months_since_start
    return round(weekend * growth * random.uniform(0.80, 1.25), 4)


# ---------------------------------------------------------------------------
# Google Ads seeding
# ---------------------------------------------------------------------------

GOOGLE_CAMPAIGNS = [
    ("Brand Search — Exact Match",   "SEARCH",          "TARGET_ROAS",             120.0),
    ("Non-Brand Search — Broad",     "SEARCH",          "MAXIMIZE_CONVERSIONS",    200.0),
    ("Display Prospecting",          "DISPLAY",         "TARGET_CPA",               80.0),
    ("Shopping — All Products",      "SHOPPING",        "TARGET_ROAS",             160.0),
    ("Performance Max",              "PERFORMANCE_MAX", "MAXIMIZE_CONVERSIONS",    300.0),
]

GOOGLE_BIDDING_DEVICES = ["MOBILE", "DESKTOP", "TABLET"]
GOOGLE_DEVICE_SPLIT = [0.55, 0.38, 0.07]  # realistic mobile-heavy split


async def seed_google(conn) -> tuple[int, int]:
    g_campaign_ids = []
    g_adgroup_ids = []

    for name, ctype, bidding, budget in GOOGLE_CAMPAIGNS:
        r = await conn.execute(
            text("""
                INSERT INTO google_campaigns (name, campaign_type, bidding_strategy, daily_budget, start_date)
                VALUES (:name, :ctype, :bidding, :budget, :start)
                RETURNING id
            """),
            {"name": name, "ctype": ctype, "bidding": bidding, "budget": budget, "start": START_DATE},
        )
        cid = r.scalar()
        g_campaign_ids.append((cid, ctype, budget))

        # 2–3 ad groups per campaign
        for ag_idx in range(random.randint(2, 3)):
            r2 = await conn.execute(
                text("""
                    INSERT INTO google_ad_groups (campaign_id, name, cpc_bid)
                    VALUES (:cid, :name, :bid) RETURNING id
                """),
                {"cid": cid, "name": f"ag_{ag_idx + 1}_{name[:20].replace(' ', '_').lower()}",
                 "bid": round(random.uniform(0.5, 3.5), 2)},
            )
            agid = r2.scalar()
            g_adgroup_ids.append((agid, cid, ctype, budget))

    # Daily metrics — device split
    rows = []
    for agid, cid, ctype, budget in g_adgroup_ids:
        for d in DAYS:
            f = day_factor(d)
            for dev, dev_share in zip(GOOGLE_BIDDING_DEVICES, GOOGLE_DEVICE_SPLIT):
                daily_cost = round(budget * f * dev_share, 2)
                cpc = round(random.uniform(0.80, 3.50) * (1.2 if dev == "MOBILE" else 1.0), 4)
                clicks = max(1, int(daily_cost / cpc))
                ctr = round(random.uniform(0.03, 0.08) if ctype == "SEARCH" else random.uniform(0.005, 0.02), 6)
                impressions = max(clicks, int(clicks / ctr))
                cvr = random.uniform(0.03, 0.06) if ctype in ("SEARCH", "PERFORMANCE_MAX") else random.uniform(0.01, 0.03)
                conversions = round(clicks * cvr, 2)
                conv_value = round(conversions * random.uniform(60, 120), 2)
                sis = round(random.uniform(0.30, 0.85), 4) if ctype == "SEARCH" else None

                rows.append({
                    "cid": cid, "agid": agid, "date": d,
                    "impressions": impressions, "clicks": clicks,
                    "cost": daily_cost, "conversions": conversions,
                    "conversion_value": conv_value,
                    "avg_cpc": round(daily_cost / clicks, 4) if clicks else 0,
                    "ctr": ctr, "sis": sis, "device": dev,
                })

    await conn.execute(
        text("""
            INSERT INTO google_daily_metrics
                (campaign_id, ad_group_id, date, impressions, clicks, cost,
                 conversions, conversion_value, avg_cpc, ctr, search_impression_share, device)
            VALUES (:cid, :agid, :date, :impressions, :clicks, :cost,
                    :conversions, :conversion_value, :avg_cpc, :ctr, :sis, :device)
        """),
        rows,
    )
    return len(g_campaign_ids), len(g_adgroup_ids)


# ---------------------------------------------------------------------------
# Meta Ads seeding
# ---------------------------------------------------------------------------

META_CAMPAIGNS = [
    ("Conversions — Retargeting",   "OUTCOME_CONVERSIONS", 150.0),
    ("Conversions — Prospecting",   "OUTCOME_CONVERSIONS", 250.0),
    ("Traffic — Blog & Content",    "OUTCOME_TRAFFIC",      90.0),
    ("Awareness — Brand Video",     "OUTCOME_AWARENESS",   110.0),
    ("Lead Gen — Free Trial",       "OUTCOME_LEADS",       180.0),
]

META_PLACEMENTS = ["FEED", "STORIES", "REELS", "AUDIENCE_NETWORK"]
META_PLACEMENT_SPLIT = [0.45, 0.25, 0.20, 0.10]


async def seed_meta(conn) -> tuple[int, int]:
    m_campaigns = []
    m_adsets = []

    for name, objective, budget in META_CAMPAIGNS:
        r = await conn.execute(
            text("""
                INSERT INTO meta_campaigns (name, objective, daily_budget, start_date)
                VALUES (:name, :obj, :budget, :start) RETURNING id
            """),
            {"name": name, "obj": objective, "budget": budget, "start": START_DATE},
        )
        cid = r.scalar()
        m_campaigns.append((cid, objective, budget))

        opt_goal = "CONVERSIONS" if "CONVERSIONS" in objective else (
            "VIDEO_VIEWS" if "AWARENESS" in objective else "LINK_CLICKS"
        )
        for ag_idx in range(random.randint(2, 3)):
            age_min = random.choice([18, 25, 30])
            r2 = await conn.execute(
                text("""
                    INSERT INTO meta_ad_sets
                        (campaign_id, name, optimization_goal, billing_event, age_min, age_max, placement)
                    VALUES (:cid, :name, :opt, :bill, :amin, :amax, :place) RETURNING id
                """),
                {
                    "cid": cid,
                    "name": f"adset_{ag_idx + 1}_{name[:18].replace(' ', '_').lower()}",
                    "opt": opt_goal,
                    "bill": "IMPRESSIONS" if "AWARENESS" in objective else "LINK_CLICKS",
                    "amin": age_min, "amax": age_min + random.choice([10, 14, 20]),
                    "place": random.choice(META_PLACEMENTS),
                },
            )
            asid = r2.scalar()
            m_adsets.append((asid, cid, objective, budget))

    rows = []
    for asid, cid, objective, budget in m_adsets:
        for d in DAYS:
            f = day_factor(d)
            spend = round(budget * f * random.uniform(0.85, 1.15), 2)
            cpm = round(random.uniform(8, 18), 4)
            impressions = max(1, int(spend / cpm * 1000))
            reach = max(1, int(impressions * random.uniform(0.60, 0.85)))
            frequency = round(impressions / reach, 3)
            ctr = random.uniform(0.01, 0.03)
            clicks = max(1, int(impressions * ctr))
            link_clicks = max(1, int(clicks * random.uniform(0.65, 0.85)))
            cvr = random.uniform(0.01, 0.04)
            conversions = max(0, int(link_clicks * cvr))
            conv_value = round(conversions * random.uniform(40, 90), 2)
            video_views = int(impressions * random.uniform(0.05, 0.25)) if "AWARENESS" in objective else None

            rows.append({
                "cid": cid, "asid": asid, "date": d,
                "impressions": impressions, "reach": reach, "frequency": frequency,
                "clicks": clicks, "link_clicks": link_clicks, "spend": spend,
                "conversions": conversions, "conversion_value": conv_value,
                "video_views": video_views,
                "cpm": round(cpm, 4),
            })

    await conn.execute(
        text("""
            INSERT INTO meta_daily_metrics
                (campaign_id, ad_set_id, date, impressions, reach, frequency,
                 clicks, link_clicks, spend, conversions, conversion_value, video_views, cpm)
            VALUES (:cid, :asid, :date, :impressions, :reach, :frequency,
                    :clicks, :link_clicks, :spend, :conversions, :conversion_value,
                    :video_views, :cpm)
        """),
        rows,
    )
    return len(m_campaigns), len(m_adsets)


# ---------------------------------------------------------------------------
# TikTok Ads seeding
# ---------------------------------------------------------------------------

TIKTOK_CAMPAIGNS = [
    ("Conversions — Purchase",    "CONVERSIONS",    180.0),
    ("Traffic — Product Page",    "TRAFFIC",        100.0),
    ("Video Views — Brand Story", "VIDEO_VIEWS",    140.0),
    ("App Promotion",             "APP_PROMOTION",  220.0),
]

TIKTOK_AGE_GROUPS = ["18-24", "25-34", "35-44"]
TIKTOK_AGE_SPLIT  = [0.55, 0.30, 0.15]  # TikTok skews young


async def seed_tiktok(conn) -> tuple[int, int]:
    t_campaigns = []
    t_adgroups = []

    for name, objective, budget in TIKTOK_CAMPAIGNS:
        r = await conn.execute(
            text("""
                INSERT INTO tiktok_campaigns (name, objective, daily_budget, start_date)
                VALUES (:name, :obj, :budget, :start) RETURNING id
            """),
            {"name": name, "obj": objective, "budget": budget, "start": START_DATE},
        )
        cid = r.scalar()
        t_campaigns.append((cid, objective, budget))

        opt = "CONVERT" if objective == "CONVERSIONS" else (
            "SHOW" if objective == "VIDEO_VIEWS" else "CLICK"
        )
        for ag_idx in range(random.randint(2, 3)):
            age = random.choices(TIKTOK_AGE_GROUPS, TIKTOK_AGE_SPLIT)[0]
            r2 = await conn.execute(
                text("""
                    INSERT INTO tiktok_ad_groups
                        (campaign_id, name, placement, optimization_goal, age_group)
                    VALUES (:cid, :name, 'TIKTOK', :opt, :age) RETURNING id
                """),
                {
                    "cid": cid,
                    "name": f"adg_{ag_idx + 1}_{name[:18].replace(' ', '_').lower()}",
                    "opt": opt, "age": age,
                },
            )
            agid = r2.scalar()
            t_adgroups.append((agid, cid, objective, budget))

    rows = []
    for agid, cid, objective, budget in t_adgroups:
        for d in DAYS:
            f = day_factor(d)
            spend = round(budget * f * random.uniform(0.80, 1.20), 2)
            cpm = round(random.uniform(5, 12), 4)
            impressions = max(1, int(spend / cpm * 1000))
            ctr = random.uniform(0.01, 0.025)
            clicks = max(1, int(impressions * ctr))
            cvr = random.uniform(0.005, 0.02)
            conversions = max(0, int(clicks * cvr))
            conv_value = round(conversions * random.uniform(30, 80), 2)

            # Video funnel (TikTok-specific)
            video_views = int(impressions * random.uniform(0.30, 0.65))
            watched_2s  = int(video_views * random.uniform(0.70, 0.90))
            watched_6s  = int(watched_2s  * random.uniform(0.45, 0.65))
            completions = int(watched_6s  * random.uniform(0.25, 0.45))

            # Social engagement
            likes    = int(impressions * random.uniform(0.005, 0.025))
            comments = int(likes * random.uniform(0.05, 0.15))
            shares   = int(likes * random.uniform(0.03, 0.10))

            rows.append({
                "cid": cid, "agid": agid, "date": d,
                "impressions": impressions, "clicks": clicks, "spend": spend,
                "conversions": conversions, "conv_value": conv_value,
                "cpm": round(cpm, 4), "ctr": round(ctr, 6),
                "video_views": video_views, "watched_2s": watched_2s,
                "watched_6s": watched_6s, "completions": completions,
                "likes": likes, "comments": comments, "shares": shares,
            })

    await conn.execute(
        text("""
            INSERT INTO tiktok_daily_metrics
                (campaign_id, ad_group_id, date, impressions, clicks, spend,
                 conversions, conversion_value, cpm, ctr,
                 video_views, video_watched_2s, video_watched_6s, video_completions,
                 likes, comments, shares)
            VALUES (:cid, :agid, :date, :impressions, :clicks, :spend,
                    :conversions, :conv_value, :cpm, :ctr,
                    :video_views, :watched_2s, :watched_6s, :completions,
                    :likes, :comments, :shares)
        """),
        rows,
    )
    return len(t_campaigns), len(t_adgroups)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def seed():
    async with engine.begin() as conn:
        for stmt in DROP_STATEMENTS:
            await conn.execute(text(stmt))
        for stmt in CREATE_STATEMENTS:
            await conn.execute(text(stmt))

        random.seed(42)
        g_camps, g_ags  = await seed_google(conn)
        random.seed(43)
        m_camps, m_ags  = await seed_meta(conn)
        random.seed(44)
        t_camps, t_ags  = await seed_tiktok(conn)

    total_campaigns  = g_camps + m_camps + t_camps
    total_adgroups   = g_ags   + m_ags   + t_ags
    total_days       = (END_DATE - START_DATE).days + 1
    print(f"Google:  {g_camps} campaigns, {g_ags} ad groups")
    print(f"Meta:    {m_camps} campaigns, {m_ags} ad sets")
    print(f"TikTok:  {t_camps} campaigns, {t_ags} ad groups")
    print(f"Total:   {total_campaigns} campaigns, {total_adgroups} groups")
    print(f"Days:    {total_days} ({START_DATE} → {END_DATE})")
    print("Done.")


if __name__ == "__main__":
    asyncio.run(seed())
