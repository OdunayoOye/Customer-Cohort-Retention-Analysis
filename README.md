# Customer-Cohort-Retention-Analysis
End-to-end customer cohort &amp; retention analysis with SQL — tracking acquisition trends, churn risk, and lifetime value across 1M+ transactions


## Project Overview

This project performs a full-stack cohort and retention analysis on a real-world e-commerce transaction dataset containing **~1 million rows** spanning two years of order history from a UK-based online retailer.

The goal: answer the questions a VP of Marketing or Head of Customer Success would ask in a weekly business review like "Are we retaining customers? Which cohorts are healthiest? Where should we intervene?"

---

## Dataset

| Field | Description |
|---|---|
| `customer_id` | Unique customer identifier |
| `invoice` | Order ID (prefixed `C` = cancellation) |
| `invoice_date` | Timestamp of transaction |
| `quantity` | Units purchased |
| `unit_price` | Price per unit |
| `country` | Customer country |

**Setup:** Download from Kaggle, load into SQL Server as `online_retail`. No pre-processing required — all cleaning is handled within the SQL itself.

```sql
-- SQL Server
BULK INSERT online_retail
FROM 'C:\data\online_retail_II.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', TABLOCK);

-- MySQL 8+
LOAD DATA INFILE '/data/online_retail_II.csv'
INTO TABLE online_retail
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 ROWS;
```

---

## Analyses & Business Questions Answered

| Query | Business Question |
|---|---|
| **Q1 — Cohort Retention Table** | What % of each monthly cohort is still purchasing in months 1, 2, 3…? |
| **Q2 — Monthly Revenue & Customer Trend** | Is active customer count and revenue growing MoM? |
| **Q3 — New vs. Returning Customer Split** | Is growth driven by acquisition or retention? |
| **Q4 — Churn Identification** | Which customers have gone silent for 90+ days? |
| **Q5 — Cohort Revenue & Cumulative ARPU** | Which cohorts generate the highest lifetime value per customer? |
| **Q6 — Rolling 3-Month Retention** | What is the smoothed retention trend, removing month-to-month noise? |
| **Q7 — Top 20% Revenue Customers (Pareto)** | Which customers drive 80% of revenue? |
| **Q8 — MoM Cohort Churn Rate** | What fraction of last month's active users churned this month? |
| **Q9 — Country-Level Retention** | Do customers from certain countries retain better than others? |
| **Q10 — Executive Cohort Scorecard** | One-row-per-cohort summary: size, M1/M3/M6 retention, avg LTV |

---

## Advanced SQL Techniques Demonstrated

- **Multi-layered CTEs** — stacked 4–6 deep with clean separation of logic
- **Window Functions** — `LAG`, `NTILE`, `AVG OVER`, `SUM OVER`, `ROW_NUMBER`
- **Cohort Period Indexing** — month arithmetic to derive periods since acquisition
- **Conditional Aggregation** — `CASE WHEN` inside `COUNT/SUM` for pivot-style outputs
- **Rolling Averages** — `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW`
- **Cumulative Revenue** — running totals using `ORDER BY` inside window frames
- **DISTINCT ON** — PostgreSQL-native deduplication for customer-country assignment
- **CROSS JOIN** — for broadcasting a single reference date across all rows
- **NULL-safe division** — `NULLIF` to prevent division-by-zero errors
- **Date truncation & arithmetic** — `DATE_TRUNC`, `EXTRACT` for cohort month math

---

## 💡 Key Business Insights (Sample Findings)

> *Results will vary based on your dataset load. Below are representative findings typical of this dataset.*

- **Month-1 retention** averages ~20–25%, dropping sharply to ~10–15% by Month 3 — consistent with e-commerce industry benchmarks
- The **Nov–Dec 2010 cohorts** show significantly higher LTV per customer, likely driven by holiday-season purchasing behavior carrying into the following year
- **UK customers** represent ~85% of revenue but show lower M3 retention than Germany and France — suggesting an opportunity for localised retention campaigns in Continental Europe
- The **top 20% of customers** account for approximately 70–75% of total revenue, confirming the Pareto principle and validating a VIP tier strategy

---
