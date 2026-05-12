/** A.typ — Appendix A: Database Schema
***/

#pdf.attach(
  "A.typ",
  relationship: "source",
  mime-type: "text/vnd.typst",
  description: "The Typst source code for Appendix A (Database Schema) of this thesis.",
)

#import "../preamble.typ": *

= Database schema <appendix-db-schema>
This appendix lists the full SQL schema of the marketing database used by the agent.
The schema is PostgreSQL-compatible. All tables are read-only from the agent's
perspective; the agent connects via a database user that has `SELECT` privileges only.

```sql
CREATE TABLE campaigns (
    id            SERIAL PRIMARY KEY,
    platform      VARCHAR(50)  NOT NULL,  -- 'google_ads' | 'meta' | 'linkedin'
    name          VARCHAR(255) NOT NULL,
    campaign_type VARCHAR(50)  NOT NULL,  -- 'search' | 'display' | 'video' | 'social'
    status        VARCHAR(20)  NOT NULL,  -- 'active' | 'paused' | 'ended'
    daily_budget  NUMERIC(10,2),
    start_date    DATE         NOT NULL,
    end_date      DATE
);

CREATE TABLE ad_groups (
    id               SERIAL PRIMARY KEY,
    campaign_id      INTEGER REFERENCES campaigns(id),
    name             VARCHAR(255) NOT NULL,
    targeting_type   VARCHAR(50),
    audience_segment VARCHAR(100),
    status           VARCHAR(20)  NOT NULL
);

CREATE TABLE ads (
    id            SERIAL PRIMARY KEY,
    ad_group_id   INTEGER REFERENCES ad_groups(id),
    name          VARCHAR(255) NOT NULL,
    headline      VARCHAR(255),
    description   TEXT,
    creative_type VARCHAR(50),   -- 'text' | 'image' | 'video' | 'carousel'
    status        VARCHAR(20)    NOT NULL
);

CREATE TABLE daily_metrics (
    id           SERIAL PRIMARY KEY,
    campaign_id  INTEGER REFERENCES campaigns(id),
    ad_group_id  INTEGER REFERENCES ad_groups(id),
    ad_id        INTEGER REFERENCES ads(id),
    date         DATE         NOT NULL,
    platform     VARCHAR(50)  NOT NULL,
    impressions  INTEGER      NOT NULL DEFAULT 0,
    clicks       INTEGER      NOT NULL DEFAULT 0,
    conversions  INTEGER      NOT NULL DEFAULT 0,
    spend        NUMERIC(10,2) NOT NULL DEFAULT 0,
    revenue      NUMERIC(10,2) NOT NULL DEFAULT 0
);

CREATE TABLE audience_segments (
    id             SERIAL PRIMARY KEY,
    name           VARCHAR(100) NOT NULL,
    description    TEXT,
    platform       VARCHAR(50),
    estimated_size INTEGER
);

-- Indexes for common query patterns
CREATE INDEX idx_daily_metrics_date     ON daily_metrics(date);
CREATE INDEX idx_daily_metrics_platform ON daily_metrics(platform);
CREATE INDEX idx_daily_metrics_campaign ON daily_metrics(campaign_id);
```

The derived KPIs used in analysis are computed by the agent at query time:

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*KPI*], [*SQL expression*]),
    [CTR],  [`CAST(clicks AS FLOAT) / NULLIF(impressions, 0) * 100`],
    [CPC],  [`spend / NULLIF(clicks, 0)`],
    [CPA],  [`spend / NULLIF(conversions, 0)`],
    [ROAS], [`revenue / NULLIF(spend, 0)`],
  ),
  caption: [KPI expressions used in SQL queries.],
) <tab-kpi-sql>
