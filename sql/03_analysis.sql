-- 03_analysis.sql
-- Four questions about how far the reported COVID-19 numbers (to 30 April 2021)
-- can be taken at face value. Country rows only.

USE covid;

-- ===========================================================================
-- Q1. Does the day of the week change how many cases get reported?
--     If reporting were neutral, each weekday would carry about 14.3% of cases.
--     From June 2020, once most countries were reporting daily.
-- ===========================================================================
SELECT DAYNAME(report_date)                                  AS weekday,
       SUM(new_cases)                                        AS cases_reported,
       ROUND(100 * SUM(new_cases) / SUM(SUM(new_cases)) OVER (), 2) AS pct_of_week,
       ROUND(100 * SUM(new_cases) / MAX(SUM(new_cases)) OVER () - 100, 1) AS pct_vs_busiest_day
FROM daily
WHERE is_country = 1 AND report_date >= '2020-06-01'
GROUP BY weekday, WEEKDAY(report_date)
ORDER BY WEEKDAY(report_date);

-- ===========================================================================
-- Q2. Spreading batch reports back over the days they cover.
--     In a batch-reporting country, a run of zero days followed by one large
--     report is really one report covering several days.
--
--     Gaps-and-islands: batch_id counts the positive reports BEFORE each day.
--     The zero days after report k and report k+1 itself share batch_id = k,
--     so averaging within a batch spreads each report over the days it covers.
--     Negative corrections are left on their own day and kept out of the
--     average, so each country's total is exactly the same after spreading.
-- ===========================================================================
DROP TEMPORARY TABLE IF EXISTS batch_reporters;
CREATE TEMPORARY TABLE batch_reporters AS
WITH s AS (
    SELECT location, report_date, new_cases,
           MIN(CASE WHEN new_cases > 0 THEN report_date END) OVER (PARTITION BY location) AS first_case
    FROM daily
    WHERE is_country = 1
)
SELECT location
FROM s
WHERE report_date >= s.first_case
GROUP BY location
HAVING SUM(new_cases) >= 10000 AND AVG(new_cases = 0) >= 0.25;

DROP TABLE IF EXISTS spread;
CREATE TABLE spread AS
WITH tagged AS (
    SELECT d.location, d.report_date, d.new_cases,
           COALESCE(SUM(d.new_cases > 0) OVER (
               PARTITION BY d.location ORDER BY d.report_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS batch_id
    FROM daily d
    JOIN batch_reporters b ON b.location = d.location
    WHERE d.new_cases IS NOT NULL
)
SELECT location, report_date, new_cases, batch_id,
       COUNT(CASE WHEN new_cases >= 0 THEN 1 END) OVER (PARTITION BY location, batch_id) AS days_in_batch,
       CASE WHEN new_cases < 0 THEN new_cases
            -- trailing zero days whose report hadn't arrived by 30 April: unknown, not zero
            WHEN MAX(new_cases) OVER (PARTITION BY location, batch_id) <= 0 AND new_cases = 0
                 AND batch_id = MAX(batch_id) OVER (PARTITION BY location) THEN NULL
            ELSE SUM(GREATEST(new_cases, 0)) OVER (PARTITION BY location, batch_id)
                 / COUNT(CASE WHEN new_cases >= 0 THEN 1 END) OVER (PARTITION BY location, batch_id)
       END                                                       AS cases_spread
FROM tagged;

-- Effect per country: same total, much smaller spikes and day-to-day swings
WITH diffs AS (
    SELECT location, new_cases, cases_spread,
           ABS(new_cases    - LAG(new_cases)    OVER (PARTITION BY location ORDER BY report_date)) AS jump_raw,
           ABS(cases_spread - LAG(cases_spread) OVER (PARTITION BY location ORDER BY report_date)) AS jump_spread
    FROM spread
)
SELECT location,
       SUM(new_cases)               AS total_cases,
       ROUND(SUM(cases_spread))     AS total_after_spreading,
       MAX(new_cases)               AS biggest_day_reported,
       ROUND(MAX(cases_spread))     AS biggest_day_spread,
       ROUND(AVG(jump_raw))         AS avg_daily_swing_reported,
       ROUND(AVG(jump_spread))      AS avg_daily_swing_spread,
       ROUND(100 * (1 - AVG(jump_spread) / AVG(jump_raw)), 0) AS pct_less_swing
FROM diffs
GROUP BY location
ORDER BY pct_less_swing DESC;

-- One batch in detail: Cameroon's largest single report and the days it covered
SELECT report_date, new_cases AS reported, ROUND(cases_spread) AS spread_over_batch, days_in_batch
FROM spread
WHERE location = 'Cameroon'
  AND batch_id = (SELECT batch_id FROM spread WHERE location = 'Cameroon' ORDER BY new_cases DESC LIMIT 1)
ORDER BY report_date;

-- ===========================================================================
-- Q3. Do countries that test less report higher death rates?
--     Case fatality rate (CFR) = deaths / confirmed cases at 30 April 2021.
--     Countries are split into quarters by tests per confirmed case. Rows where
--     tests < cases are dropped as incomplete testing series. Each country counts
--     once (simple average), so a few very large countries don't dominate.
-- ===========================================================================
WITH latest AS (
    SELECT location, MAX(total_cases) AS cases, MAX(total_deaths) AS deaths, MAX(total_tests) AS tests
    FROM daily
    WHERE is_country = 1
    GROUP BY location
), scored AS (
    SELECT location, tests / cases AS tests_per_case, deaths / cases AS cfr
    FROM latest
    WHERE cases >= 1000 AND deaths IS NOT NULL AND tests >= cases
)
SELECT testing_quarter,
       COUNT(*)                       AS countries,
       ROUND(MIN(tests_per_case), 1)  AS tests_per_case_from,
       ROUND(MAX(tests_per_case), 1)  AS tests_per_case_to,
       ROUND(100 * AVG(cfr), 2)       AS avg_cfr_pct
FROM (SELECT *, NTILE(4) OVER (ORDER BY tests_per_case) AS testing_quarter FROM scored) q
GROUP BY testing_quarter
ORDER BY testing_quarter;

-- ===========================================================================
-- Q4. How far behind was Africa on vaccination by 30 April 2021?
--     Share of the whole population with at least one dose. Countries with no
--     vaccination data count as zero, which is the honest reading for April 2021
--     (most had not started). The count of such countries is shown alongside.
-- ===========================================================================
WITH latest AS (
    SELECT location, continent, MAX(population) AS population, MAX(people_vaccinated) AS one_dose
    FROM daily
    WHERE is_country = 1
    GROUP BY location, continent
)
SELECT continent,
       ROUND(100 * SUM(one_dose) / SUM(population), 1) AS pct_one_dose,
       SUM(one_dose IS NULL)                           AS countries_without_data,
       COUNT(*)                                        AS countries
FROM latest
GROUP BY continent
ORDER BY pct_one_dose DESC;

SELECT location,
       MIN(CASE WHEN total_vaccinations > 0 THEN report_date END) AS first_doses_in_data,
       MAX(people_vaccinated)                                     AS one_dose,
       ROUND(100 * MAX(people_vaccinated) / MAX(population), 2)   AS pct_one_dose
FROM daily
WHERE location IN ('Nigeria', 'Ghana', 'Kenya', 'South Africa', 'India', 'United Kingdom', 'United States')
GROUP BY location
ORDER BY pct_one_dose DESC;
