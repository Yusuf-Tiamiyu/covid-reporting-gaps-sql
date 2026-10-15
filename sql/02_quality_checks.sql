-- 02_quality_checks.sql
-- What is wrong with the daily series before any of it is analysed.
-- Country rows only (is_country = 1); OWID aggregates like "World" are excluded.

USE covid;
SET SESSION cte_max_recursion_depth = 1000;

-- ---------------------------------------------------------------------------
-- 1. Dates missing from a country's series.
--    A recursive CTE builds one row per calendar day from each country's first
--    to last report; a LEFT JOIN back to the data shows which days never arrived.
-- ---------------------------------------------------------------------------
WITH RECURSIVE spine AS (
    SELECT location, MIN(report_date) AS d, MAX(report_date) AS last_day
    FROM daily
    WHERE is_country = 1
    GROUP BY location
    UNION ALL
    SELECT location, d + INTERVAL 1 DAY, last_day
    FROM spine
    WHERE d < last_day
)
SELECT s.location,
       COUNT(*)    AS missing_days,
       MIN(s.d)    AS first_missing,
       MAX(s.d)    AS last_missing
FROM spine s
LEFT JOIN daily x ON x.location = s.location AND x.report_date = s.d
WHERE x.location IS NULL
GROUP BY s.location
ORDER BY missing_days DESC;

-- ---------------------------------------------------------------------------
-- 2. Values that cannot be literal daily counts.
--    Negative new cases/deaths are corrections to earlier over-counts.
--    Total tests below total cases means the testing series is incomplete.
-- ---------------------------------------------------------------------------
SELECT 'Days with negative new cases'  AS issue, COUNT(*) AS rows_affected, COUNT(DISTINCT location) AS countries
FROM daily WHERE is_country = 1 AND new_cases < 0
UNION ALL
SELECT 'Days with negative new deaths', COUNT(*), COUNT(DISTINCT location)
FROM daily WHERE is_country = 1 AND new_deaths < 0
UNION ALL
SELECT 'Days where cumulative tests < cumulative cases', COUNT(*), COUNT(DISTINCT location)
FROM daily WHERE is_country = 1 AND total_tests < total_cases
UNION ALL
SELECT 'Countries with no testing data at all', COUNT(*), COUNT(*)
FROM (SELECT location FROM daily WHERE is_country = 1 GROUP BY location HAVING MAX(total_tests) IS NULL) t;

-- ---------------------------------------------------------------------------
-- 3. Days reported as zero after a country's first case.
--    A high share suggests cases are being reported in weekly or irregular
--    batches rather than genuinely falling to zero. Countries with at least
--    10,000 cases only, so small outbreaks with real zero days are left out.
-- ---------------------------------------------------------------------------
WITH s AS (
    SELECT location, continent, report_date, new_cases,
           MIN(CASE WHEN new_cases > 0 THEN report_date END) OVER (PARTITION BY location) AS first_case
    FROM daily
    WHERE is_country = 1
)
SELECT location, continent,
       ROUND(100 * AVG(new_cases = 0), 1) AS pct_zero_days,
       SUM(new_cases)                     AS total_cases
FROM s
WHERE report_date >= first_case
GROUP BY location, continent
HAVING SUM(new_cases) >= 10000 AND AVG(new_cases = 0) >= 0.25
ORDER BY pct_zero_days DESC;
