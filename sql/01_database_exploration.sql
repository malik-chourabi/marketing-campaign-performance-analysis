-- =====================================================================
-- 01_database_exploration.sql
-- Stage 3.1 / 3.2 : Import the database, explore it, run data-quality checks
-- Database : data/raw/marketing-campaigns-v1.0.0.sqlite  (SQLite)
-- NOTE     : this script is READ-ONLY (SELECT only). The raw file is never modified.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1  DATABASE STRUCTURE
-- ---------------------------------------------------------------------

-- Query 1.1: Which tables exist? (expected: campaigns, daily_spend, leads, conversions)
SELECT name AS table_name, type
FROM sqlite_master
WHERE type = 'table'
ORDER BY name;

-- Query 1.2: Columns and declared data types of every table
SELECT 'campaigns'   AS table_name, name AS column_name, type AS declared_type FROM pragma_table_info('campaigns')
UNION ALL
SELECT 'daily_spend' , name, type FROM pragma_table_info('daily_spend')
UNION ALL
SELECT 'leads'       , name, type FROM pragma_table_info('leads')
UNION ALL
SELECT 'conversions' , name, type FROM pragma_table_info('conversions');

-- Query 1.3: Distinct values of the categorical columns
SELECT 'channel' AS attribute, channel AS value, COUNT(*) AS n_campaigns FROM campaigns GROUP BY channel
UNION ALL
SELECT 'objective', objective, COUNT(*) FROM campaigns GROUP BY objective
UNION ALL
SELECT 'conversion_type', conversion_type, COUNT(*) FROM conversions GROUP BY conversion_type;

-- Query 1.4: Date coverage of each table
SELECT 'campaigns.start_date'     AS column_name, MIN(start_date)   AS first_date, MAX(start_date)   AS last_date FROM campaigns
UNION ALL SELECT 'campaigns.end_date',        MIN(end_date),      MAX(end_date)      FROM campaigns
UNION ALL SELECT 'daily_spend.spend_date',    MIN(spend_date),    MAX(spend_date)    FROM daily_spend
UNION ALL SELECT 'leads.created_at',          MIN(created_at),    MAX(created_at)    FROM leads
UNION ALL SELECT 'conversions.converted_at',  MIN(converted_at),  MAX(converted_at)  FROM conversions;

-- ---------------------------------------------------------------------
-- 3.2  DATA QUALITY CHECKS
-- ---------------------------------------------------------------------

-- Check 1: number of records in each table
SELECT 'campaigns'   AS table_name, COUNT(*) AS n_rows FROM campaigns
UNION ALL SELECT 'daily_spend', COUNT(*) FROM daily_spend
UNION ALL SELECT 'leads',       COUNT(*) FROM leads
UNION ALL SELECT 'conversions', COUNT(*) FROM conversions;

-- Check 2: missing values (NULL or empty string) per column
SELECT 'campaigns' AS table_name,
       SUM(campaign_id   IS NULL OR TRIM(campaign_id)   = '') AS campaign_id,
       SUM(campaign_name IS NULL OR TRIM(campaign_name) = '') AS campaign_name,
       SUM(channel       IS NULL OR TRIM(channel)       = '') AS channel,
       SUM(objective     IS NULL OR TRIM(objective)     = '') AS objective,
       SUM(start_date    IS NULL OR TRIM(start_date)    = '') AS start_date,
       SUM(end_date      IS NULL OR TRIM(end_date)      = '') AS end_date,
       SUM(budget        IS NULL)                              AS budget
FROM campaigns;

SELECT 'daily_spend' AS table_name,
       SUM(spend_id    IS NULL) AS spend_id,   SUM(campaign_id IS NULL) AS campaign_id,
       SUM(spend_date  IS NULL) AS spend_date, SUM(impressions IS NULL) AS impressions,
       SUM(clicks      IS NULL) AS clicks,     SUM(spend       IS NULL) AS spend
FROM daily_spend;

SELECT 'leads' AS table_name,
       SUM(lead_id     IS NULL) AS lead_id,     SUM(campaign_id IS NULL) AS campaign_id,
       SUM(created_at  IS NULL) AS created_at,  SUM(lead_source IS NULL) AS lead_source,
       SUM(lead_score  IS NULL) AS lead_score
FROM leads;

SELECT 'conversions' AS table_name,
       SUM(conversion_id   IS NULL) AS conversion_id,   SUM(lead_id IS NULL) AS lead_id,
       SUM(converted_at    IS NULL) AS converted_at,    SUM(conversion_type IS NULL) AS conversion_type,
       SUM(revenue         IS NULL) AS revenue
FROM conversions;

-- Check 3: duplicate IDs (every query should return 0)
SELECT 'campaigns.campaign_id'     AS id_column, COUNT(*) - COUNT(DISTINCT campaign_id)   AS duplicates FROM campaigns
UNION ALL SELECT 'daily_spend.spend_id',        COUNT(*) - COUNT(DISTINCT spend_id)        FROM daily_spend
UNION ALL SELECT 'leads.lead_id',               COUNT(*) - COUNT(DISTINCT lead_id)         FROM leads
UNION ALL SELECT 'conversions.conversion_id',   COUNT(*) - COUNT(DISTINCT conversion_id)   FROM conversions
UNION ALL SELECT 'daily_spend (campaign_id, spend_date)',
                (SELECT COUNT(*) FROM (SELECT campaign_id, spend_date FROM daily_spend
                                        GROUP BY 1, 2 HAVING COUNT(*) > 1))
UNION ALL SELECT 'conversions.lead_id (one conversion per lead?)',
                COUNT(*) - COUNT(DISTINCT lead_id) FROM conversions;

-- Check 4: campaign IDs must match between tables (orphan records; expected 0)
SELECT 'daily_spend -> campaigns' AS relationship, COUNT(*) AS orphan_rows
FROM daily_spend d LEFT JOIN campaigns c ON c.campaign_id = d.campaign_id
WHERE c.campaign_id IS NULL
UNION ALL
SELECT 'leads -> campaigns', COUNT(*)
FROM leads l LEFT JOIN campaigns c ON c.campaign_id = l.campaign_id
WHERE c.campaign_id IS NULL
UNION ALL
SELECT 'conversions -> leads', COUNT(*)
FROM conversions v LEFT JOIN leads l ON l.lead_id = v.lead_id
WHERE l.lead_id IS NULL
UNION ALL
SELECT 'campaigns without any spend row', COUNT(*)
FROM campaigns c LEFT JOIN daily_spend d ON d.campaign_id = c.campaign_id
WHERE d.campaign_id IS NULL;

-- Check 5: date formats (valid ISO 'YYYY-MM-DD' and parsable) - expected 0 invalid
SELECT 'campaigns.start_date' AS column_name,
       SUM(DATE(start_date) IS NULL OR LENGTH(start_date) <> 10) AS invalid_dates FROM campaigns
UNION ALL SELECT 'campaigns.end_date',       SUM(DATE(end_date)      IS NULL OR LENGTH(end_date)      <> 10) FROM campaigns
UNION ALL SELECT 'daily_spend.spend_date',   SUM(DATE(spend_date)    IS NULL OR LENGTH(spend_date)    <> 10) FROM daily_spend
UNION ALL SELECT 'leads.created_at',         SUM(DATE(created_at)    IS NULL OR LENGTH(created_at)    <> 10) FROM leads
UNION ALL SELECT 'conversions.converted_at', SUM(DATE(converted_at)  IS NULL OR LENGTH(converted_at) <> 10) FROM conversions;

-- Check 6: negative / zero / invalid spending and revenue values (expected 0)
SELECT 'daily_spend.spend < 0'          AS check_name, COUNT(*) AS violations FROM daily_spend WHERE spend < 0
UNION ALL SELECT 'daily_spend.spend = 0',              COUNT(*) FROM daily_spend WHERE spend = 0
UNION ALL SELECT 'daily_spend.impressions < 0',        COUNT(*) FROM daily_spend WHERE impressions < 0
UNION ALL SELECT 'daily_spend.clicks < 0',             COUNT(*) FROM daily_spend WHERE clicks < 0
UNION ALL SELECT 'campaigns.budget <= 0',              COUNT(*) FROM campaigns WHERE budget <= 0
UNION ALL SELECT 'conversions.revenue < 0',            COUNT(*) FROM conversions WHERE revenue < 0
UNION ALL SELECT 'leads.lead_score outside 0-100',     COUNT(*) FROM leads WHERE lead_score NOT BETWEEN 0 AND 100;

-- Check 7: logical consistency of the funnel (expected 0 violations)
SELECT 'clicks > impressions (daily)' AS check_name, COUNT(*) AS violations
FROM daily_spend WHERE clicks > impressions
UNION ALL
SELECT 'campaign end_date < start_date', COUNT(*) FROM campaigns WHERE end_date < start_date
UNION ALL
SELECT 'spend dated outside the campaign window', COUNT(*)
FROM daily_spend d JOIN campaigns c USING (campaign_id)
WHERE d.spend_date < c.start_date OR d.spend_date > c.end_date
UNION ALL
SELECT 'lead dated outside the campaign window', COUNT(*)
FROM leads l JOIN campaigns c USING (campaign_id)
WHERE l.created_at < c.start_date OR l.created_at > c.end_date
UNION ALL
SELECT 'conversion dated before its lead', COUNT(*)
FROM conversions v JOIN leads l USING (lead_id)
WHERE v.converted_at < l.created_at
UNION ALL
SELECT 'lead_source differs from campaign channel', COUNT(*)
FROM leads l JOIN campaigns c USING (campaign_id)
WHERE l.lead_source <> c.channel
UNION ALL
SELECT 'campaign total spend > campaign budget', COUNT(*)
FROM (SELECT c.campaign_id FROM campaigns c JOIN daily_spend d USING (campaign_id)
      GROUP BY c.campaign_id HAVING SUM(d.spend) > MAX(c.budget));

-- Check 8: funnel order at campaign level  (clicks >= leads >= conversions)
SELECT COUNT(*) AS campaigns_with_illogical_funnel
FROM (
  SELECT c.campaign_id,
         (SELECT SUM(clicks) FROM daily_spend d WHERE d.campaign_id = c.campaign_id) AS clicks,
         (SELECT COUNT(*)    FROM leads l       WHERE l.campaign_id = c.campaign_id) AS leads,
         (SELECT COUNT(*)    FROM conversions v JOIN leads l2 USING (lead_id)
           WHERE l2.campaign_id = c.campaign_id)                                    AS conversions
  FROM campaigns c
) WHERE leads > clicks OR conversions > leads;

-- Check 9: business rule - which conversion types carry revenue?
-- (finding: 'trial' conversions always have revenue = 0, 'purchase' always > 0)
SELECT conversion_type,
       COUNT(*)                                   AS n_conversions,
       SUM(revenue = 0)                           AS zero_revenue_rows,
       ROUND(SUM(revenue), 2)                     AS total_revenue,
       ROUND(AVG(revenue), 2)                     AS avg_revenue
FROM conversions
GROUP BY conversion_type;

-- Check 10: inconsistent campaign names / categories (case, spaces, duplicates)
SELECT COUNT(*) AS names_with_extra_spaces_or_case_dupes
FROM (SELECT LOWER(TRIM(campaign_name)) AS n FROM campaigns GROUP BY n HAVING COUNT(*) > 1)
UNION ALL
SELECT COUNT(*) FROM campaigns WHERE channel <> LOWER(TRIM(channel)) OR objective <> LOWER(TRIM(objective));
