-- =====================================================================
-- 02_data_cleaning.sql
-- Stage 3.3 : Clean the data
-- IMPORTANT : run this script on a COPY of the database (it creates VIEWS only,
--             it never UPDATEs or DELETEs raw rows, but a copy keeps data/raw untouched).
-- Findings of 01_database_exploration.sql: no NULLs, no duplicate IDs, no orphan IDs,
-- all dates valid, no negative spend, funnel logic respected. The cleaning layer therefore
--   (a) standardises types / labels,      (b) applies validation filters that remove 0 rows today
--   (c) aggregates each table to the same grain (campaign x day) BEFORE joining.
-- Rows are never silently deleted: the reconciliation query at the bottom proves it.
-- =====================================================================

DROP VIEW IF EXISTS clean_campaigns;
DROP VIEW IF EXISTS clean_daily_spend;
DROP VIEW IF EXISTS clean_leads;
DROP VIEW IF EXISTS clean_conversions;
DROP VIEW IF EXISTS campaign_daily;

-- ---------------------------------------------------------------------
-- 1. Campaigns: trim text, readable labels, real DATE values, numeric budget
-- ---------------------------------------------------------------------
CREATE VIEW clean_campaigns AS
SELECT
    TRIM(campaign_id)                                         AS campaign_id,
    TRIM(campaign_name)                                       AS campaign_name,
    LOWER(TRIM(channel))                                      AS channel_code,
    CASE LOWER(TRIM(channel))                                 -- consistent display labels
         WHEN 'paid_search' THEN 'Paid Search'
         WHEN 'paid_social' THEN 'Paid Social'
         WHEN 'display'     THEN 'Display'
         WHEN 'video'       THEN 'Video'
         WHEN 'affiliate'   THEN 'Affiliate'
         ELSE 'Other' END                                     AS channel,
    CASE LOWER(TRIM(objective))
         WHEN 'awareness'   THEN 'Awareness'
         WHEN 'lead_gen'    THEN 'Lead Generation'
         WHEN 'acquisition' THEN 'Acquisition'
         ELSE 'Other' END                                     AS objective,
    DATE(start_date)                                          AS start_date,
    DATE(end_date)                                            AS end_date,
    CAST(JULIANDAY(end_date) - JULIANDAY(start_date) AS INT) + 1 AS planned_days,
    CAST(budget AS REAL)                                      AS budget
FROM campaigns
WHERE campaign_id IS NOT NULL
  AND DATE(start_date) IS NOT NULL AND DATE(end_date) IS NOT NULL
  AND DATE(end_date) >= DATE(start_date)
  AND budget > 0;

-- ---------------------------------------------------------------------
-- 2. Daily spend: valid dates, non-negative spend, clicks <= impressions, known campaign
-- ---------------------------------------------------------------------
CREATE VIEW clean_daily_spend AS
SELECT
    d.spend_id,
    d.campaign_id,
    DATE(d.spend_date)                      AS spend_date,
    STRFTIME('%Y-%m', d.spend_date)         AS month,
    CAST(d.impressions AS INTEGER)          AS impressions,
    CAST(d.clicks      AS INTEGER)          AS clicks,
    CAST(d.spend       AS REAL)             AS spend
FROM daily_spend d
JOIN clean_campaigns c ON c.campaign_id = d.campaign_id
WHERE DATE(d.spend_date) IS NOT NULL
  AND d.spend >= 0
  AND d.impressions >= 0 AND d.clicks >= 0
  AND d.clicks <= d.impressions;

-- ---------------------------------------------------------------------
-- 3. Leads
-- ---------------------------------------------------------------------
CREATE VIEW clean_leads AS
SELECT l.lead_id, l.campaign_id, DATE(l.created_at) AS created_at,
       STRFTIME('%Y-%m', l.created_at) AS month, l.lead_score
FROM leads l
JOIN clean_campaigns c ON c.campaign_id = l.campaign_id
WHERE DATE(l.created_at) IS NOT NULL AND l.lead_score BETWEEN 0 AND 100;

-- ---------------------------------------------------------------------
-- 4. Conversions: attach campaign + lead cohort date.
--    Business rule found in the data: 'trial' = revenue 0, 'purchase' = revenue > 0.
--    Revenue is attributed to the day the LEAD was created (cohort attribution) so that
--    spend, leads, conversions and revenue of one day describe the same cohort.
-- ---------------------------------------------------------------------
CREATE VIEW clean_conversions AS
SELECT v.conversion_id,
       v.lead_id,
       l.campaign_id,
       l.created_at                          AS lead_date,
       DATE(v.converted_at)                  AS converted_at,
       CAST(JULIANDAY(v.converted_at) - JULIANDAY(l.created_at) AS INT) AS days_to_convert,
       v.conversion_type,
       CASE WHEN v.conversion_type = 'purchase' THEN 1 ELSE 0 END       AS is_purchase,
       CAST(v.revenue AS REAL)               AS revenue
FROM conversions v
JOIN clean_leads l ON l.lead_id = v.lead_id
WHERE DATE(v.converted_at) IS NOT NULL
  AND v.revenue >= 0
  AND DATE(v.converted_at) >= l.created_at;

-- ---------------------------------------------------------------------
-- 5. campaign_daily: ONE row per campaign per day.
--    Each source is aggregated to (campaign_id, date) first, then joined, so a join can
--    never multiply spend rows (the double-counting trap from the guideline).
-- ---------------------------------------------------------------------
CREATE VIEW campaign_daily AS
WITH spend AS (
    SELECT campaign_id, spend_date, month,
           SUM(impressions) AS impressions, SUM(clicks) AS clicks, SUM(spend) AS spend
    FROM clean_daily_spend
    GROUP BY campaign_id, spend_date, month
),
lead_day AS (
    SELECT campaign_id, created_at AS d, COUNT(*) AS leads
    FROM clean_leads
    GROUP BY campaign_id, created_at
),
conv_day AS (
    SELECT campaign_id, lead_date AS d,
           COUNT(*)                AS conversions,
           SUM(is_purchase)        AS purchases,
           SUM(revenue)            AS revenue
    FROM clean_conversions
    GROUP BY campaign_id, lead_date
)
SELECT s.campaign_id, c.campaign_name, c.channel, c.objective,
       s.spend_date, s.month,
       s.impressions, s.clicks,
       COALESCE(l.leads, 0)        AS leads,
       COALESCE(v.conversions, 0)  AS conversions,
       COALESCE(v.purchases, 0)    AS purchases,
       ROUND(s.spend, 2)           AS spend,
       ROUND(COALESCE(v.revenue, 0), 2) AS revenue
FROM spend s
JOIN clean_campaigns c ON c.campaign_id = s.campaign_id
LEFT JOIN lead_day l ON l.campaign_id = s.campaign_id AND l.d = s.spend_date
LEFT JOIN conv_day v ON v.campaign_id = s.campaign_id AND v.d = s.spend_date;

-- ---------------------------------------------------------------------
-- 6. RECONCILIATION: nothing lost, nothing double counted
--    raw total vs cleaned total must be identical for every measure (diff = 0)
-- ---------------------------------------------------------------------
SELECT 'spend'       AS measure,
       (SELECT ROUND(SUM(spend), 2)       FROM daily_spend)  AS raw_total,
       (SELECT ROUND(SUM(spend), 2)       FROM campaign_daily) AS cleaned_total,
       ROUND((SELECT SUM(spend) FROM daily_spend) - (SELECT SUM(spend) FROM campaign_daily), 2) AS diff
UNION ALL
SELECT 'impressions', (SELECT SUM(impressions) FROM daily_spend), (SELECT SUM(impressions) FROM campaign_daily),
       (SELECT SUM(impressions) FROM daily_spend) - (SELECT SUM(impressions) FROM campaign_daily)
UNION ALL
SELECT 'clicks', (SELECT SUM(clicks) FROM daily_spend), (SELECT SUM(clicks) FROM campaign_daily),
       (SELECT SUM(clicks) FROM daily_spend) - (SELECT SUM(clicks) FROM campaign_daily)
UNION ALL
SELECT 'leads', (SELECT COUNT(*) FROM leads), (SELECT SUM(leads) FROM campaign_daily),
       (SELECT COUNT(*) FROM leads) - (SELECT SUM(leads) FROM campaign_daily)
UNION ALL
SELECT 'conversions', (SELECT COUNT(*) FROM conversions), (SELECT SUM(conversions) FROM campaign_daily),
       (SELECT COUNT(*) FROM conversions) - (SELECT SUM(conversions) FROM campaign_daily)
UNION ALL
SELECT 'revenue', (SELECT ROUND(SUM(revenue), 2) FROM conversions), (SELECT ROUND(SUM(revenue), 2) FROM campaign_daily),
       ROUND((SELECT SUM(revenue) FROM conversions) - (SELECT SUM(revenue) FROM campaign_daily), 2)
UNION ALL
SELECT 'rows (campaign-days)', (SELECT COUNT(*) FROM daily_spend), (SELECT COUNT(*) FROM campaign_daily),
       (SELECT COUNT(*) FROM daily_spend) - (SELECT COUNT(*) FROM campaign_daily);

-- Rows removed by the cleaning filters, per table (expected 0 everywhere)
SELECT 'campaigns'   AS tbl, (SELECT COUNT(*) FROM campaigns)   - (SELECT COUNT(*) FROM clean_campaigns)   AS rows_removed
UNION ALL SELECT 'daily_spend', (SELECT COUNT(*) FROM daily_spend) - (SELECT COUNT(*) FROM clean_daily_spend)
UNION ALL SELECT 'leads',       (SELECT COUNT(*) FROM leads)       - (SELECT COUNT(*) FROM clean_leads)
UNION ALL SELECT 'conversions', (SELECT COUNT(*) FROM conversions) - (SELECT COUNT(*) FROM clean_conversions);
