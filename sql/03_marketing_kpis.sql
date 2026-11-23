-- =====================================================================
-- 03_marketing_kpis.sql
-- Stage 3.4 / 3.5 : Marketing KPIs
-- Requires 02_data_cleaning.sql to have been run (uses campaign_daily / clean_campaigns).
--
-- KPI definitions
--   CTR              = Clicks / Impressions x 100
--   CPC              = Spend / Clicks
--   Conversion Rate  = Conversions / Clicks x 100
--   CPA              = Spend / Conversions          (a conversion = trial OR purchase)
--   Cost / Purchase  = Spend / Purchases            (stricter, revenue-generating conversions only)
--   ROAS             = Revenue / Spend
--   ROI              = (Revenue - Spend) / Spend x 100
-- All divisions use NULLIF(x, 0) to avoid divide-by-zero errors.
-- =====================================================================

DROP VIEW IF EXISTS campaign_kpis;
DROP VIEW IF EXISTS channel_kpis;
DROP VIEW IF EXISTS objective_kpis;
DROP VIEW IF EXISTS monthly_kpis;
DROP VIEW IF EXISTS overall_kpis;

-- ---------------------------------------------------------------------
-- Campaign level (campaign_daily is aggregated per campaign BEFORE any join with budget)
-- ---------------------------------------------------------------------
CREATE VIEW campaign_kpis AS
WITH agg AS (
    SELECT campaign_id,
           COUNT(*)          AS days_active,
           SUM(impressions)  AS impressions,
           SUM(clicks)       AS clicks,
           SUM(leads)        AS leads,
           SUM(conversions)  AS conversions,
           SUM(purchases)    AS purchases,
           SUM(spend)        AS spend,
           SUM(revenue)      AS revenue
    FROM campaign_daily
    GROUP BY campaign_id
)
SELECT c.campaign_id, c.campaign_name, c.channel, c.objective,
       c.start_date, c.end_date, c.budget,
       a.days_active, a.impressions, a.clicks, a.leads, a.conversions, a.purchases,
       ROUND(a.spend, 2)                                              AS spend,
       ROUND(a.revenue, 2)                                            AS revenue,
       ROUND(100.0 * a.clicks      / NULLIF(a.impressions, 0), 3)     AS ctr_pct,
       ROUND(a.spend / NULLIF(a.clicks, 0), 3)                        AS cpc,
       ROUND(a.spend / NULLIF(a.leads, 0), 3)                         AS cpl,
       ROUND(100.0 * a.conversions / NULLIF(a.clicks, 0), 3)          AS conv_rate_pct,
       ROUND(a.spend / NULLIF(a.conversions, 0), 3)                   AS cpa,
       ROUND(a.spend / NULLIF(a.purchases, 0), 3)                     AS cost_per_purchase,
       ROUND(a.revenue / NULLIF(a.spend, 0), 4)                       AS roas,
       ROUND(100.0 * (a.revenue - a.spend) / NULLIF(a.spend, 0), 2)   AS roi_pct,
       ROUND(100.0 * a.spend / c.budget, 2)                           AS budget_used_pct
FROM agg a
JOIN clean_campaigns c ON c.campaign_id = a.campaign_id;

-- ---------------------------------------------------------------------
-- Channel level (re-aggregates the campaign totals - ratios are recomputed, never averaged)
-- ---------------------------------------------------------------------
CREATE VIEW channel_kpis AS
SELECT channel,
       COUNT(*)                         AS campaigns,
       SUM(impressions)                 AS impressions,
       SUM(clicks)                      AS clicks,
       SUM(leads)                       AS leads,
       SUM(conversions)                 AS conversions,
       SUM(purchases)                   AS purchases,
       ROUND(SUM(spend), 2)             AS spend,
       ROUND(SUM(revenue), 2)           AS revenue,
       ROUND(100.0 * SUM(clicks)      / SUM(impressions), 3) AS ctr_pct,
       ROUND(SUM(spend) / SUM(clicks), 3)                    AS cpc,
       ROUND(100.0 * SUM(conversions) / SUM(clicks), 3)      AS conv_rate_pct,
       ROUND(SUM(spend) / SUM(conversions), 3)               AS cpa,
       ROUND(SUM(spend) / SUM(purchases), 3)                 AS cost_per_purchase,
       ROUND(SUM(revenue) / SUM(spend), 4)                   AS roas,
       ROUND(100.0 * (SUM(revenue) - SUM(spend)) / SUM(spend), 2) AS roi_pct
FROM campaign_kpis
GROUP BY channel;

CREATE VIEW objective_kpis AS
SELECT objective,
       COUNT(*)                         AS campaigns,
       SUM(impressions)                 AS impressions,
       SUM(clicks)                      AS clicks,
       SUM(leads)                       AS leads,
       SUM(conversions)                 AS conversions,
       SUM(purchases)                   AS purchases,
       ROUND(SUM(spend), 2)             AS spend,
       ROUND(SUM(revenue), 2)           AS revenue,
       ROUND(100.0 * SUM(clicks)      / SUM(impressions), 3) AS ctr_pct,
       ROUND(SUM(spend) / SUM(clicks), 3)                    AS cpc,
       ROUND(100.0 * SUM(conversions) / SUM(clicks), 3)      AS conv_rate_pct,
       ROUND(SUM(spend) / SUM(conversions), 3)               AS cpa,
       ROUND(SUM(revenue) / SUM(spend), 4)                   AS roas,
       ROUND(100.0 * (SUM(revenue) - SUM(spend)) / SUM(spend), 2) AS roi_pct
FROM campaign_kpis
GROUP BY objective;

-- ---------------------------------------------------------------------
-- Monthly level (month = month of the spend day / lead cohort)
-- ---------------------------------------------------------------------
CREATE VIEW monthly_kpis AS
SELECT month,
       SUM(impressions)                 AS impressions,
       SUM(clicks)                      AS clicks,
       SUM(leads)                       AS leads,
       SUM(conversions)                 AS conversions,
       SUM(purchases)                   AS purchases,
       ROUND(SUM(spend), 2)             AS spend,
       ROUND(SUM(revenue), 2)           AS revenue,
       ROUND(100.0 * SUM(clicks)      / SUM(impressions), 3) AS ctr_pct,
       ROUND(SUM(spend) / SUM(conversions), 3)               AS cpa,
       ROUND(SUM(revenue) / SUM(spend), 4)                   AS roas
FROM campaign_daily
GROUP BY month;

-- ---------------------------------------------------------------------
-- Whole portfolio
-- ---------------------------------------------------------------------
CREATE VIEW overall_kpis AS
SELECT COUNT(*)                         AS campaigns,
       SUM(impressions)                 AS impressions,
       SUM(clicks)                      AS clicks,
       SUM(leads)                       AS leads,
       SUM(conversions)                 AS conversions,
       SUM(purchases)                   AS purchases,
       ROUND(SUM(spend), 2)             AS spend,
       ROUND(SUM(revenue), 2)           AS revenue,
       ROUND(100.0 * SUM(clicks)      / SUM(impressions), 3) AS ctr_pct,
       ROUND(SUM(spend) / SUM(clicks), 3)                    AS cpc,
       ROUND(100.0 * SUM(conversions) / SUM(clicks), 3)      AS conv_rate_pct,
       ROUND(SUM(spend) / SUM(conversions), 3)               AS cpa,
       ROUND(SUM(spend) / SUM(purchases), 3)                 AS cost_per_purchase,
       ROUND(SUM(revenue) / SUM(spend), 4)                   AS roas,
       ROUND(100.0 * (SUM(revenue) - SUM(spend)) / SUM(spend), 2) AS roi_pct
FROM campaign_kpis;

-- Sanity check: KPI views must reproduce the raw totals exactly
SELECT * FROM overall_kpis;
