
--  Business Context:
--  An online retail company wants to understand how well it
--  retains customers over time, which acquisition cohorts
--  perform best, and where churn is highest so marketing
--  and CX teams can intervene early.
--
-- SETUP: Create & load the table 
--
--  CREATE TABLE online_retail (
--      invoice       VARCHAR(20),
--      stock_code    VARCHAR(20),
--      description   VARCHAR(255),
--      quantity      INT,
--      invoice_date  DATETIME,
--      unit_price    DECIMAL(10,2),
--      customer_id   VARCHAR(20),
--      country       VARCHAR(100)
--  );
--
--  -- bulk load (update data location path as needed):
--  BULK INSERT online_retail
--  FROM 'C:\data\online_retail_II.csv'
--  WITH (FORMAT = 'CSV', FIRSTROW = 2,
--        FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK);
--
-- ============================================================

-- QUERY 2 - COHORT RETENTION RATE TABLE
--
--  Business Question:
--  "What % of customers from each monthly cohort are still
--   purchasing in months 1, 2, 3 … after acquisition?"
-- ============================================================
WITH clean_orders AS (
    SELECT
        customer_id,
        CAST(invoice_date AS DATE)                              AS order_date,
        YEAR(invoice_date)                                      AS order_year,
        MONTH(invoice_date)                                     AS order_month_num,
        DATEFROMPARTS(YEAR(invoice_date), MONTH(invoice_date), 1) AS order_month_start,
        quantity * unit_price                                   AS revenue,
        country
    FROM  online_retail
    WHERE customer_id  IS NOT NULL
      AND quantity      > 0
      AND unit_price    > 0
      AND invoice NOT LIKE 'C%'
),

customer_cohorts AS (
    SELECT
        customer_id,
        MIN(order_month_start)  AS cohort_month
    FROM  clean_orders
    GROUP BY customer_id
),

cohort_activity AS (
    SELECT
        co.customer_id,
        cc.cohort_month,
        co.order_month_start                                                AS activity_month,
        (YEAR(co.order_month_start)  * 12 + MONTH(co.order_month_start))
        - (YEAR(cc.cohort_month)     * 12 + MONTH(cc.cohort_month))        AS period_index,
        co.revenue
    FROM  clean_orders      co
    JOIN  customer_cohorts  cc  ON co.customer_id = cc.customer_id
),

cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_id) AS cohort_size
    FROM  cohort_activity
    WHERE period_index = 0
    GROUP BY cohort_month
),

cohort_retention_counts AS (
    SELECT
        cohort_month,
        period_index,
        COUNT(DISTINCT customer_id) AS active_customers
    FROM  cohort_activity
    GROUP BY cohort_month, period_index
)

SELECT
    crc.cohort_month,
    cs.cohort_size,
    crc.period_index,
    crc.active_customers,
    ROUND(
        CAST(crc.active_customers AS DECIMAL(10,4))
        / NULLIF(cs.cohort_size, 0) * 100, 2
    )                                       AS retention_rate_pct
FROM  cohort_retention_counts  crc
JOIN  cohort_sizes              cs  ON crc.cohort_month = cs.cohort_month
ORDER BY crc.cohort_month, crc.period_index;


-- ============================================================
-- QUERY 2 — MONTHLY ACTIVE CUSTOMERS & REVENUE TREND
--
--  Business Question:
--  "How is the active customer count and total revenue trending
--   month over month? Are we growing or declining?"
-- ============================================================
WITH clean_orders AS (
    SELECT
        customer_id,
        DATEFROMPARTS(YEAR(invoice_date), MONTH(invoice_date), 1) AS order_month,
        quantity * unit_price                                     AS revenue
    FROM  online_retail
    WHERE customer_id IS NOT NULL
      AND quantity   > 0
      AND unit_price > 0
      AND invoice NOT LIKE 'C%'
),

monthly_summary AS (
    SELECT
        order_month,
        COUNT(DISTINCT customer_id)  AS active_customers,
        ROUND(SUM(revenue), 2)       AS total_revenue
    FROM  clean_orders
    GROUP BY order_month
)

SELECT
    order_month,
    active_customers,
    total_revenue,
    ROUND(total_revenue / NULLIF(active_customers, 0), 2)           AS revenue_per_customer,
    LAG(active_customers) OVER (ORDER BY order_month)               AS prev_month_customers,
    ROUND(
        CAST(
            active_customers - LAG(active_customers) OVER (ORDER BY order_month) AS DECIMAL(10,4))
        / NULLIF(LAG(active_customers) OVER (ORDER BY order_month), 0)
        * 100, 2)                                                               AS mom_customer_growth_pct
FROM  monthly_summary
ORDER BY order_month;

-- ============================================================
-- QUERY 3 — NEW vs. RETURNING CUSTOMER SPLIT (MONTHLY)
--
--  Business Question:
--  "Each month, how many customers are brand new vs. returning?
--   Is growth driven by acquisition or retention?"
-- ============================================================
WITH clean_orders AS (
    SELECT
        customer_id,
        DATEFROMPARTS(YEAR(invoice_date), MONTH(invoice_date), 1) AS order_month
    FROM  online_retail
    WHERE customer_id IS NOT NULL
      AND quantity   > 0
      AND unit_price > 0
      AND invoice NOT LIKE 'C%'
),

first_orders AS (
    SELECT customer_id, MIN(order_month) AS first_month
    FROM  clean_orders
    GROUP BY customer_id
),

monthly_customers AS (
    SELECT DISTINCT customer_id, order_month
    FROM  clean_orders
)

SELECT
    mc.order_month,
    COUNT(mc.customer_id)                                               AS total_customers,
    SUM(CASE WHEN fo.first_month = mc.order_month THEN 1 ELSE 0 END)   AS new_customers,
    SUM(CASE WHEN fo.first_month < mc.order_month THEN 1 ELSE 0 END)   AS returning_customers,
    ROUND(
        CAST(SUM(CASE WHEN fo.first_month < mc.order_month
                      THEN 1 ELSE 0 END) AS DECIMAL(10,4))
        / NULLIF(COUNT(mc.customer_id), 0) * 100, 2)                   AS returning_pct
FROM  monthly_customers  mc
JOIN  first_orders        fo  ON mc.customer_id = fo.customer_id
GROUP BY mc.order_month
ORDER BY mc.order_month;

-- ============================================================
-- QUERY 4 — CUSTOMER CHURN IDENTIFICATION
--
--  Business Question:
--  "Which customers have gone silent for 90+ days?
--   Flag them so CRM can trigger a re-engagement campaign."
-- ============================================================
WITH clean_orders AS (
    SELECT
        customer_id,
        MAX(CAST(invoice_date AS DATE)) AS last_order_date
    FROM  online_retail
    WHERE customer_id IS NOT NULL
      AND quantity   > 0
      AND unit_price > 0
      AND invoice NOT LIKE 'C%'
    GROUP BY customer_id
),

dataset_max_date AS (
    SELECT MAX(last_order_date) AS max_date
    FROM  clean_orders
)

SELECT
    co.customer_id,
    co.last_order_date,
    dm.max_date                                             AS dataset_reference_date,
    DATEDIFF(DAY, co.last_order_date, dm.max_date)          AS days_since_last_order,
    CASE
        WHEN DATEDIFF(DAY, co.last_order_date, dm.max_date) > 90  THEN 'Churned'
        WHEN DATEDIFF(DAY, co.last_order_date, dm.max_date) > 30  THEN 'At Risk'
        ELSE 'Active'
    END                                                     AS customer_status
FROM  clean_orders       co
CROSS JOIN dataset_max_date  dm
ORDER BY days_since_last_order DESC;

-- ============================================================
-- QUERY 5 — COHORT REVENUE & CUMULATIVE ARPU
--
--  Business Question:
--  "Which acquisition cohorts generate the highest lifetime
--   revenue per customer (LTV proxy)?"
-- ============================================================
WITH clean_orders AS (
    SELECT
        customer_id,
        DATEFROMPARTS(YEAR(invoice_date), MONTH(invoice_date), 1) AS order_month,
        quantity * unit_price                                     AS revenue
    FROM  online_retail
    WHERE customer_id IS NOT NULL
      AND quantity   > 0
      AND unit_price > 0
      AND invoice NOT LIKE 'C%'
),

cohort_months AS (
    SELECT customer_id, MIN(order_month) AS cohort_month
    FROM  clean_orders
    GROUP BY customer_id
),

cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
    FROM  cohort_months
    GROUP BY cohort_month
),

cohort_revenue AS (
    SELECT
        cm.cohort_month,
        (YEAR(co.order_month) * 12 + MONTH(co.order_month))
        - (YEAR(cm.cohort_month) * 12 + MONTH(cm.cohort_month))    AS period_index,
        SUM(co.revenue)                                             AS period_revenue,
        COUNT(DISTINCT co.customer_id)                              AS active_customers
    FROM  clean_orders   co
    JOIN  cohort_months  cm  ON co.customer_id = cm.customer_id
    GROUP BY
        cm.cohort_month,
        (YEAR(co.order_month) * 12 + MONTH(co.order_month))
        - (YEAR(cm.cohort_month) * 12 + MONTH(cm.cohort_month))
)

SELECT
    cr.cohort_month,
    cs.cohort_size,
    cr.period_index,
    ROUND(cr.period_revenue, 2)                                     AS period_revenue,
    ROUND(cr.period_revenue / NULLIF(cs.cohort_size, 0), 2)         AS arpu,
    ROUND(
        SUM(cr.period_revenue) OVER (
            PARTITION BY cr.cohort_month
            ORDER BY cr.period_index
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / NULLIF(cs.cohort_size, 0), 2
    )                                                               AS cumulative_arpu
FROM  cohort_revenue  cr
JOIN  cohort_sizes    cs  ON cr.cohort_month = cs.cohort_month
ORDER BY cr.cohort_month, cr.period_index;

-- ============================================================
-- QUERY 6 — ROLLING 3-MONTH RETENTION RATE
--
--  Business Question:
--  "Smooth out month-to-month noise — what is the 3-month
--   rolling average retention rate for each cohort?"
-- ============================================================
WITH clean_orders AS (
    SELECT
        customer_id,
        DATEFROMPARTS(YEAR(invoice_date), MONTH(invoice_date), 1) AS order_month
    FROM  online_retail
    WHERE customer_id IS NOT NULL
      AND quantity   > 0
      AND unit_price > 0
      AND invoice NOT LIKE 'C%'
),

cohort_months AS (
    SELECT customer_id, MIN(order_month) AS cohort_month
    FROM  clean_orders
    GROUP BY customer_id
),

cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
    FROM  cohort_months
    GROUP BY cohort_month
),

monthly_activity AS (
    SELECT
        cm.cohort_month,
        co.order_month,
        COUNT(DISTINCT co.customer_id) AS active_customers
    FROM  clean_orders   co
    JOIN  cohort_months  cm  ON co.customer_id = cm.customer_id
    GROUP BY cm.cohort_month, co.order_month
),

retention_rates AS (
    SELECT
        ma.cohort_month,
        ma.order_month,
        cs.cohort_size,
        ma.active_customers,
        ROUND(
            CAST(ma.active_customers AS DECIMAL(10,4))
            / NULLIF(cs.cohort_size, 0) * 100, 2
        )                               AS retention_rate_pct
    FROM  monthly_activity  ma
    JOIN  cohort_sizes       cs  ON ma.cohort_month = cs.cohort_month
)

SELECT
    cohort_month,
    order_month,
    cohort_size,
    active_customers,
    retention_rate_pct,
    ROUND(
        AVG(retention_rate_pct) OVER (
            PARTITION BY cohort_month
            ORDER BY order_month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2
    )                                   AS rolling_3mo_retention_pct
FROM  retention_rates
ORDER BY cohort_month, order_month;


-- ============================================================
-- QUERY 7 — TOP 20% CUSTOMERS BY REVENUE (PARETO / RFM PREP)
--
--  Business Question:
--  "Which customers drive 80% of revenue? Identify high-value
--   customers for VIP or loyalty program targeting."
-- ============================================================
WITH clean_orders AS (
    SELECT
        customer_id,
        CAST(invoice_date AS DATE)  AS order_date,
        quantity * unit_price       AS revenue
    FROM  online_retail
    WHERE customer_id IS NOT NULL
      AND quantity   > 0
      AND unit_price > 0
      AND invoice NOT LIKE 'C%'
),

customer_summary AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_date)  AS total_orders,
        ROUND(SUM(revenue), 2)      AS total_revenue,
        MIN(order_date)             AS first_order_date,
        MAX(order_date)             AS last_order_date
    FROM  clean_orders
    GROUP BY customer_id
),

revenue_ranked AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY total_revenue DESC)     AS revenue_quintile,
        ROUND(
            SUM(total_revenue) OVER (
                ORDER BY total_revenue DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            )
            / NULLIF(SUM(total_revenue) OVER (), 0) * 100, 2
        )                                               AS cumulative_revenue_pct
    FROM  customer_summary
)

SELECT
    customer_id,
    total_orders,
    total_revenue,
    first_order_date,
    last_order_date,
    revenue_quintile,
    cumulative_revenue_pct,
    CASE revenue_quintile
        WHEN 1 THEN 'VIP - Top 20%'
        WHEN 2 THEN 'High Value'
        WHEN 3 THEN 'Mid Value'
        WHEN 4 THEN 'Low Value'
        ELSE        'At-Risk / Dormant'
    END                                                 AS customer_segment
FROM  revenue_ranked
ORDER BY total_revenue DESC;

-- ============================================================
-- QUERY 8 — MONTH-OVER-MONTH COHORT CHURN RATE
--
--  Business Question:
--  "For each cohort, what fraction of last month's active
--   customers did NOT return this month?"
-- ============================================================
WITH clean_orders AS (
    SELECT
        customer_id,
        DATEFROMPARTS(YEAR(invoice_date), MONTH(invoice_date), 1) AS order_month
    FROM  online_retail
    WHERE customer_id IS NOT NULL
      AND quantity   > 0
      AND unit_price > 0
      AND invoice NOT LIKE 'C%'
),

cohort_months AS (
    SELECT customer_id, MIN(order_month) AS cohort_month
    FROM  clean_orders
    GROUP BY customer_id
),

period_counts AS (
    SELECT
        cm.cohort_month,
        co.order_month,
        COUNT(DISTINCT co.customer_id)                              AS active_this_month,
        LAG(COUNT(DISTINCT co.customer_id)) OVER (
            PARTITION BY cm.cohort_month
            ORDER BY co.order_month
        )                                                           AS active_last_month
    FROM  clean_orders   co
    JOIN  cohort_months  cm  ON co.customer_id = cm.customer_id
    GROUP BY cm.cohort_month, co.order_month
)

SELECT
    cohort_month,
    order_month,
    active_this_month,
    active_last_month,
    ISNULL(active_last_month - active_this_month, 0)    AS churned_customers,
    -- [MySQL]: IFNULL(active_last_month - active_this_month, 0)
    CASE
        WHEN active_last_month IS NULL THEN NULL
        ELSE ROUND(
            CAST(active_last_month - active_this_month AS DECIMAL(10,4))
            / NULLIF(active_last_month, 0) * 100, 2
        )
    END                                                 AS churn_rate_pct
FROM  period_counts
ORDER BY cohort_month, order_month;

-- ============================================================
-- QUERY 9 — COUNTRY-LEVEL RETENTION COMPARISON
--
--  Business Question:
--  "Do customers from certain countries retain better than
--   others? Should we localize our retention strategy?"
-- ============================================================
WITH clean_orders AS (
    SELECT
        customer_id,
        DATEFROMPARTS(YEAR(invoice_date), MONTH(invoice_date), 1) AS order_month,
        country
    FROM  online_retail
    WHERE customer_id IS NOT NULL
      AND quantity   > 0
      AND unit_price > 0
      AND invoice NOT LIKE 'C%'
),

customer_country_ranked AS (
    SELECT
        customer_id,
        country,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY COUNT(*) DESC
        )                           AS rn
    FROM  clean_orders
    GROUP BY customer_id, country
),

customer_country AS (
    SELECT customer_id, country
    FROM  customer_country_ranked
    WHERE rn = 1
),

top_countries AS (
    SELECT TOP 5 country         
    FROM  customer_country
    GROUP BY country
    ORDER BY COUNT(*) DESC
),

cohort_months AS (
    SELECT customer_id, MIN(order_month) AS cohort_month
    FROM  clean_orders
    GROUP BY customer_id
),

cohort_sizes AS (
    SELECT
        cm.cohort_month,
        cc.country,
        COUNT(DISTINCT cm.customer_id)  AS cohort_size
    FROM  cohort_months    cm
    JOIN  customer_country cc  ON cm.customer_id = cc.customer_id
    GROUP BY cm.cohort_month, cc.country
),

monthly_activity AS (
    SELECT
        cm.cohort_month,
        cc.country,
        co.order_month,
        COUNT(DISTINCT co.customer_id)                              AS active_customers,
        (YEAR(co.order_month)  * 12 + MONTH(co.order_month))
        - (YEAR(cm.cohort_month) * 12 + MONTH(cm.cohort_month))    AS period_index
    FROM  clean_orders    co
    JOIN  cohort_months   cm  ON co.customer_id = cm.customer_id
    JOIN  customer_country cc  ON co.customer_id = cc.customer_id
    GROUP BY cm.cohort_month, cc.country, co.order_month
)

SELECT
    ma.cohort_month,
    ma.country,
    cs.cohort_size,
    ma.period_index,
    ma.active_customers,
    ROUND(
        CAST(ma.active_customers AS DECIMAL(10,4))
        / NULLIF(cs.cohort_size, 0) * 100, 2
    )                                               AS retention_rate_pct
FROM  monthly_activity  ma
JOIN  cohort_sizes       cs  ON ma.cohort_month = cs.cohort_month
                             AND ma.country      = cs.country
WHERE cs.cohort_size >= 10
  AND ma.country IN (SELECT country FROM top_countries)
ORDER BY ma.country, ma.cohort_month, ma.period_index;

-- ============================================================
-- QUERY 10 — EXECUTIVE COHORT HEALTH SCORECARD
--
--  Business Question:
--  "Give leadership one row per cohort showing acquisition
--   size, M1/M3/M6 retention rates, and average LTV —
--   the single most important output in a retention review."
--
--  Uses: Conditional aggregation CASE inside COUNT(DISTINCT)
--        to pivot period data into a single scorecard row.
-- ============================================================
WITH clean_orders AS (
    SELECT
        customer_id,
        DATEFROMPARTS(YEAR(invoice_date), MONTH(invoice_date), 1) AS order_month,
        quantity * unit_price                                     AS revenue
    FROM  online_retail
    WHERE customer_id IS NOT NULL
      AND quantity   > 0
      AND unit_price > 0
      AND invoice NOT LIKE 'C%'
),

cohort_months AS (
    SELECT customer_id, MIN(order_month) AS cohort_month
    FROM  clean_orders
    GROUP BY customer_id
),

cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
    FROM  cohort_months
    GROUP BY cohort_month
),

cohort_activity AS (
    SELECT
        cm.cohort_month,
        co.customer_id,
        co.revenue,
        (YEAR(co.order_month)  * 12 + MONTH(co.order_month))
        - (YEAR(cm.cohort_month) * 12 + MONTH(cm.cohort_month))    AS period_index
    FROM  clean_orders   co
    JOIN  cohort_months  cm  ON co.customer_id = cm.customer_id
)

SELECT
    ca.cohort_month,
    cs.cohort_size,

    -- M1 Retention %
    ROUND(
        CAST(COUNT(DISTINCT CASE WHEN ca.period_index = 1
                                 THEN ca.customer_id END) AS DECIMAL(10,4))
        / NULLIF(cs.cohort_size, 0) * 100, 1
    )                                                       AS m1_retention_pct,

    -- M3 Retention %
    ROUND(
        CAST(COUNT(DISTINCT CASE WHEN ca.period_index = 3
                                 THEN ca.customer_id END) AS DECIMAL(10,4))
        / NULLIF(cs.cohort_size, 0) * 100, 1
    )                                                       AS m3_retention_pct,

    -- M6 Retention %
    ROUND(
        CAST(COUNT(DISTINCT CASE WHEN ca.period_index = 6
                                 THEN ca.customer_id END) AS DECIMAL(10,4))
        / NULLIF(cs.cohort_size, 0) * 100, 1
    )                                                       AS m6_retention_pct,

    -- Average revenue per cohort customer across all periods
    ROUND(SUM(ca.revenue) / NULLIF(cs.cohort_size, 0), 2)  AS avg_ltv_per_customer,

    -- Total revenue generated by the entire cohort
    ROUND(SUM(ca.revenue), 2)                               AS total_cohort_revenue

FROM  cohort_activity  ca
JOIN  cohort_sizes     cs  ON ca.cohort_month = cs.cohort_month
GROUP BY ca.cohort_month, cs.cohort_size
ORDER BY ca.cohort_month;
