-- 01_load.sql
-- Load the Our World in Data COVID-19 snapshot (to 30 April 2021) into MySQL.
-- Empty strings in the CSV become NULL via NULLIF, so "not reported" stays distinct from 0.
--
-- Run from the repo root:
--   mysql --local-infile=1 -u root -p < sql/01_load.sql

DROP DATABASE IF EXISTS covid;
CREATE DATABASE covid CHARACTER SET utf8mb4;
USE covid;

CREATE TABLE daily (
    iso_code                VARCHAR(10),
    continent               VARCHAR(20),
    location                VARCHAR(60),
    report_date             DATE,
    new_cases               INT,
    new_deaths              INT,
    total_cases             BIGINT,
    total_deaths            BIGINT,
    new_tests               BIGINT,
    total_tests             BIGINT,
    tests_per_case          DECIMAL(12,1),
    people_vaccinated       BIGINT,
    people_fully_vaccinated BIGINT,
    total_vaccinations      BIGINT,
    population              BIGINT,
    PRIMARY KEY (location, report_date)
);

LOAD DATA LOCAL INFILE 'data/owid_covid_2021-04-30.csv'
INTO TABLE daily
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(@iso, @cont, @loc, @dt, @nc, @nd, @tc, @td, @nt, @tt, @tpc, @pv, @pfv, @tv, @pop)
SET iso_code                = @iso,
    continent               = NULLIF(@cont, ''),
    location                = @loc,
    report_date             = @dt,
    new_cases               = NULLIF(@nc, ''),
    new_deaths              = NULLIF(@nd, ''),
    total_cases             = NULLIF(@tc, ''),
    total_deaths            = NULLIF(@td, ''),
    new_tests               = NULLIF(@nt, ''),
    total_tests             = NULLIF(@tt, ''),
    tests_per_case          = NULLIF(@tpc, ''),
    people_vaccinated       = NULLIF(@pv, ''),
    people_fully_vaccinated = NULLIF(@pfv, ''),
    total_vaccinations      = NULLIF(@tv, ''),
    population              = NULLIF(@pop, '');

-- OWID mixes countries with aggregate rows (World, Africa, High income, ...).
-- Aggregates have no continent and an OWID_ code; keep a flag rather than deleting them.
ALTER TABLE daily ADD COLUMN is_country TINYINT(1)
    AS (continent IS NOT NULL AND iso_code NOT LIKE 'OWID%') STORED;

SELECT COUNT(*) AS rows_loaded,
       SUM(is_country) AS country_rows,
       COUNT(DISTINCT CASE WHEN is_country = 1 THEN location END) AS countries,
       MIN(report_date) AS first_day, MAX(report_date) AS last_day
FROM daily;
