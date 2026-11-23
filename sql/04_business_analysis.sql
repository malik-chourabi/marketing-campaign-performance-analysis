-- =====================================================================
-- 04_business_analysis.sql
-- Stage 3.4 : Business-analysis queries (one per business question of the guideline)
-- Requires 02_data_cleaning.sql and 03_marketing_kpis.sql to have been run.
-- SQL skills shown: aggregations, joins, CTEs, subqueries, window functions
--                   (RANK, PERCENT_RANK, LAG, SUM OVER, NTILE-style tiers)
-- =====================================================================

-- Query 01: Total advertising spend (overall investment)
SELECT ROUND(SUM(spend), 2) AS total_spend,
       COUNT(DISTINCT campaign_id) AS campaigns,
       MIN(spend_date) AS first_day, MAX(spend_date) AS last_day
FROM campaign_daily;

-- Query 02: Total impressions and clicks (advertising reach)
SELECT SUM(impressions) AS total_impressions,
       SUM(clicks)      AS total_clicks,
       ROUND(100.0 * SUM(clicks) / SUM(impressions), 2) AS ctr_pct,
       ROUND(SUM(spend) / SUM(clicks), 3)               AS cpc
FROM campaign_daily;

-- Query 03: Total leads and conversions (acquisition)
SELECT SUM(leads)       AS total_leads,
       SUM(conversions) AS total_conversions,
       SUM(purchases)   AS total_purchases,
       SUM(conversions) - SUM(purchases) AS free_trials,
       ROUND(100.0 * SUM(conversions) / SUM(leads), 2)  AS lead_to_conversion_pct,
       ROUND(100.0 * SUM(purchases)   / SUM(conversions), 2) AS purchase_share_of_conversions_pct
FROM campaign_daily;

-- Query 04: Revenue by campaign (top 15 revenue generators, with share of total and rank)
SELECT RANK() OVER (ORDER BY revenue DESC)                       AS revenue_rank,
       campaign_name, channel, objective,
       spend, revenue,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 2)          AS pct_of_total_revenue,
       roas
FROM campaign_kpis
ORDER BY revenue DESC
LIMIT 15;

-- Query 05: Revenue by channel (with share of spend vs share of revenue)
SELECT channel, campaigns, spend, revenue,
       ROUND(100.0 * spend   / SUM(spend)   OVER (), 1) AS pct_of_spend,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 1) AS pct_of_revenue,
       RANK() OVER (ORDER BY revenue DESC)              AS revenue_rank
FROM channel_kpis
ORDER BY revenue DESC;

-- Query 06: Conversions by campaign (top 10)
SELECT RANK() OVER (ORDER BY conversions DESC) AS conversion_rank,
       campaign_name, channel, objective, spend, conversions, purchases, cpa
FROM campaign_kpis
ORDER BY conversions DESC
LIMIT 10;

-- Query 07: CPA by campaign - the 10 cheapest acquisitions (lowest CPA)
SELECT RANK() OVER (ORDER BY cpa ASC) AS cpa_rank,
       campaign_name, channel, objective, spend, conversions, cpa, cost_per_purchase
FROM campaign_kpis
ORDER BY cpa ASC
LIMIT 10;

-- Query 08: CPA by campaign - the 10 most expensive acquisitions
SELECT RANK() OVER (ORDER BY cpa DESC) AS cpa_rank_worst,
       campaign_name, channel, objective, spend, conversions, cpa, cost_per_purchase
FROM campaign_kpis
ORDER BY cpa DESC
LIMIT 10;

-- Query 09: ROAS (and the other KPIs) by channel
SELECT channel, spend, revenue, roas, roi_pct, cpa, cost_per_purchase, ctr_pct, cpc, conv_rate_pct,
       RANK() OVER (ORDER BY roas DESC) AS roas_rank
FROM channel_kpis
ORDER BY roas DESC;

-- Query 10: Campaign objectives - which perform best?
SELECT objective, campaigns, spend, revenue, conversions, roas, roi_pct, cpa, ctr_pct, conv_rate_pct
FROM objective_kpis
ORDER BY roas DESC;

-- Query 11: Channel x objective matrix (ROAS) - does the best objective depend on the channel?
SELECT channel, objective, COUNT(*) AS campaigns,
       ROUND(SUM(spend), 0) AS spend, ROUND(SUM(revenue), 0) AS revenue,
       ROUND(SUM(revenue) / SUM(spend), 2) AS roas,
       ROUND(SUM(spend) / SUM(conversions), 2) AS cpa
FROM campaign_kpis
GROUP BY channel, objective
ORDER BY channel, roas DESC;

-- Query 12: Monthly performance (all channels) with month-over-month change (LAG) and running revenue
SELECT month, spend, revenue, conversions, roas,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
                   / NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 1) AS revenue_mom_pct,
       ROUND(SUM(revenue) OVER (ORDER BY month), 0)                    AS cumulative_revenue
FROM monthly_kpis
ORDER BY month;

-- Query 13: Monthly campaign performance by channel (feeds the trend charts)
SELECT month, channel,
       ROUND(SUM(spend), 2)   AS spend,
       ROUND(SUM(revenue), 2) AS revenue,
       SUM(conversions)       AS conversions,
       ROUND(SUM(revenue) / SUM(spend), 3) AS roas
FROM campaign_daily
GROUP BY month, channel
ORDER BY month, channel;

-- Query 14: Does performance change over time? Quarterly ROAS by channel + stability
WITH q AS (
    SELECT channel,
           SUBSTR(month, 1, 4) || '-Q' || ((CAST(SUBSTR(month, 6, 2) AS INT) + 2) / 3) AS quarter,
           SUM(spend) AS spend, SUM(revenue) AS revenue
    FROM campaign_daily
    GROUP BY channel, quarter
),
r AS (SELECT channel, quarter, revenue / spend AS roas FROM q WHERE spend > 10000)   -- ignore tiny partial quarters
SELECT channel,
       COUNT(*)                         AS quarters,
       ROUND(MIN(roas), 2)              AS min_quarter_roas,
       ROUND(AVG(roas), 2)              AS avg_quarter_roas,
       ROUND(MAX(roas), 2)              AS max_quarter_roas,
       ROUND(SQRT(AVG(roas * roas) - AVG(roas) * AVG(roas)) / AVG(roas), 3) AS roas_variation_coef
FROM r
GROUP BY channel
ORDER BY roas_variation_coef;

-- Query 15: Top 10 campaigns by ROAS (strongest performers)
SELECT RANK() OVER (ORDER BY roas DESC) AS roas_rank,
       campaign_name, channel, objective, spend, revenue, roas, cpa, conversions
FROM campaign_kpis
ORDER BY roas DESC
LIMIT 10;

-- Query 16: Lowest-performing campaigns (bottom 10 by ROAS)
SELECT RANK() OVER (ORDER BY roas ASC) AS roas_rank_worst,
       campaign_name, channel, objective, spend, revenue, roas, cpa, conversions
FROM campaign_kpis
ORDER BY roas ASC
LIMIT 10;

-- Query 17: Campaigns spending too much without converting enough
--           (spend above the average campaign AND conversions below the average campaign)
WITH avg_c AS (SELECT AVG(spend) AS avg_spend, AVG(conversions) AS avg_conv,
                      SUM(spend) / SUM(conversions) AS portfolio_cpa
               FROM campaign_kpis)
SELECT k.campaign_name, k.channel, k.objective, k.spend, k.conversions, k.cpa,
       ROUND(k.cpa / a.portfolio_cpa, 2) AS cpa_vs_portfolio, k.roas
FROM campaign_kpis k, avg_c a
WHERE k.spend > a.avg_spend AND k.conversions < a.avg_conv
ORDER BY k.cpa DESC;

-- Query 18: Campaign tiers - composite score from ROAS rank and CPA rank (window functions)
--           score = average of PERCENT_RANK(ROAS asc) and PERCENT_RANK(CPA desc)  (0 = worst, 1 = best)
--           High >= 0.67 | Average between | Poor <= 0.33
CREATE VIEW IF NOT EXISTS campaign_tiers AS
WITH r AS (
    SELECT *, PERCENT_RANK() OVER (ORDER BY roas ASC) AS roas_pr,
              PERCENT_RANK() OVER (ORDER BY cpa  DESC) AS cpa_pr
    FROM campaign_kpis
)
SELECT campaign_id, campaign_name, channel, objective, spend, revenue, conversions, roas, cpa,
       ROUND((roas_pr + cpa_pr) / 2.0, 3) AS score,
       CASE WHEN (roas_pr + cpa_pr) / 2.0 >= 0.67 THEN 'High performer'
            WHEN (roas_pr + cpa_pr) / 2.0 <= 0.33 THEN 'Poor performer'
            ELSE 'Average performer' END AS tier
FROM r;

SELECT tier, COUNT(*) AS campaigns, ROUND(SUM(spend), 0) AS spend, ROUND(SUM(revenue), 0) AS revenue,
       SUM(conversions) AS conversions,
       ROUND(SUM(revenue) / SUM(spend), 2) AS roas, ROUND(SUM(spend) / SUM(conversions), 2) AS cpa,
       ROUND(100.0 * SUM(spend) / (SELECT SUM(spend) FROM campaign_tiers), 1) AS pct_of_spend
FROM campaign_tiers
GROUP BY tier
ORDER BY roas DESC;

-- Query 19: Tier mix inside every channel (where are the poor performers concentrated?)
SELECT channel,
       SUM(tier = 'High performer')    AS high,
       SUM(tier = 'Average performer') AS average,
       SUM(tier = 'Poor performer')    AS poor
FROM campaign_tiers
GROUP BY channel
ORDER BY high DESC;

-- Query 20: Scaling risk - do bigger campaigns earn less per dollar? (correlation of spend and ROAS per channel)
WITH s AS (
    SELECT channel, COUNT(*) AS n, AVG(spend) AS mx, AVG(roas) AS my,
           AVG(spend * roas) AS mxy, AVG(spend * spend) AS mxx, AVG(roas * roas) AS myy
    FROM campaign_kpis GROUP BY channel
)
SELECT channel, n AS campaigns,
       ROUND((mxy - mx * my) / SQRT((mxx - mx * mx) * (myy - my * my)), 2) AS corr_spend_vs_roas
FROM s
ORDER BY corr_spend_vs_roas;

-- Query 21: Budget utilisation by channel (how much of the allocated campaign budget was actually used?)
SELECT channel, ROUND(SUM(budget), 0) AS allocated_budget, ROUND(SUM(spend), 0) AS spent,
       ROUND(100.0 * SUM(spend) / SUM(budget), 1) AS budget_used_pct
FROM campaign_kpis
GROUP BY channel
ORDER BY budget_used_pct DESC;

-- Query 22: Lead quality - does lead_score predict conversion? (supports the funnel analysis)
SELECT CASE WHEN l.lead_score <= 20 THEN '01-20' WHEN l.lead_score <= 40 THEN '21-40'
            WHEN l.lead_score <= 60 THEN '41-60' WHEN l.lead_score <= 80 THEN '61-80'
            ELSE '81-100' END AS lead_score_band,
       COUNT(*) AS leads,
       COUNT(v.conversion_id) AS conversions,
       ROUND(100.0 * COUNT(v.conversion_id) / COUNT(*), 1) AS conversion_rate_pct
FROM clean_leads l
LEFT JOIN clean_conversions v ON v.lead_id = l.lead_id
GROUP BY lead_score_band
ORDER BY lead_score_band;
