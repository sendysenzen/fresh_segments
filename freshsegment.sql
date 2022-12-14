-- update the null values
UPDATE interest_map
SET interest_summary = NULL
WHERE interest_summary = '';

-- update NULL values
UPDATE interest_metrics
SET _month = CASE WHEN _month = 'NULL' THEN NULL::INTEGER ELSE _month::INTEGER END;

UPDATE interest_metrics
SET _year = CASE WHEN _year = 'NULL' THEN NULL::INTEGER ELSE _year::INTEGER END;

UPDATE interest_metrics
SET month_year = NULL
WHERE month_year = 'NULL';

UPDATE interest_metrics
SET interest_id = NULL
WHERE interest_id = 'NULL';

SELECT * FROM interest_metrics ; 
SELECT * FROM interest_map;

-- PART A. EDA & Cleansing

-- 1. month_year column update 
UPDATE interest_metrics
SET month_year = TO_DATE(month_year, 'MM-YYYY');

ALTER TABLE interest_metrics
ALTER month_year TYPE DATE USING month_year::DATE;


-- 2.What is count of records in the interest_metrics for each month_year 
-- value sorted in chronological order (earliest to latest) with the null values appearing first?
SELECT
  month_year,
  COUNT(*) record_count
FROM interest_metrics
GROUP BY 1
ORDER BY 1 NULLS FIRST;

-- 3. What do you think we should do with these null values in the interest_metrics?
-- check the null before deciding

SELECT * FROM interest_metrics 
WHERE month_year IS NULL;

-- after seeing all these null values, since it is especially a  case where we want to analyze 
-- based on timeframe, these rows are not useful and need to be deleted.

SELECT count(*) FROM interest_metrics;
-- 14273

DELETE FROM interest_metrics
WHERE NOT (interest_metrics IS NOT NULL);

SELECT count(*) FROM interest_metrics;
-- now its 13079

-- 4. How many interest_id values exist in the interest_metrics table but not in the 
-- interest_map table? What about the other way around?
-- how to make it in one query?

SELECT 
    count(distinct imet.interest_id) count_id_imetrics,
    count(distinct imap.id) count_id_imap, 
    SUM(CASE WHEN imet.interest_id::INTEGER IS NULL THEN 1 ELSE 0 END) not_in_imetrics,
    SUM(CASE WHEN imap.id IS NULL THEN 1 ELSE 0 END) not_in_imap
FROM interest_metrics imet
FULL OUTER JOIN interest_map imap
ON imet.interest_id::INTEGER = imap.id;
-- important to update interest_id into INTEGER first :)


-- 5. Summarise the id values in the fresh_segments.interest_map by its total record count in this table
SELECT imap.id,
    count(imet.*) total_record
FROM interest_map imap
LEFT JOIN interest_metrics imet
ON imap.id = imet.interest_id
GROUP BY 1
ORDER BY 1;

-- 6.What sort of table join should we perform for our analysis and why? 
-- Check your logic by checking the rows where interest_id = 21246 in your joined output and include all columns from 
-- fresh_segments.interest_metrics and all columns from fresh_segments.interest_map except from the id column.
-- INNER JOIN OR LEFT JOIN with interest_metrics as the LEFT table as there are 7 id's with no data from interest_metrics table

SELECT 
    imap.interest_name,
    imap.interest_summary,
    imap.created_at, 
    imap.last_modified,
    imet.*
FROM interest_map imap
INNER JOIN interest_metrics imet
ON imap.id = imet.interest_id
WHERE imet.interest_id = 21246;

-- 7.Are there any records in your joined table where the month_year value is before the created_at value from 
-- the fresh_segments.interest_map table? Do you think these values are valid and why?

WITH cte AS ( 
SELECT 
    imap.interest_name,
    imap.interest_summary,
    imap.created_at :: DATE, 
    imap.last_modified,
    imet.*
FROM interest_map imap
INNER JOIN interest_metrics imet
ON imap.id = imet.interest_id
)
SELECT 
    count(*)
FROM cte 
WHERE month_year < created_at
GROUP BY 1;
-- there are 188 records

-- In theory, these values should not be valid, however in this case, 
-- when we modified the month_year before, we put the first day of the month, 
-- so definitely there will always be records earlier than created_at. 
-- that is why we can assume that the raw data records in interest_metrics is not detailed enough, 
-- supposedly it has to be recorded in day

-- B. INTEREST ANALYSIS
-----------------------

-- B.1 Which interests have been present in all month_year dates in our dataset?
-- first, how many month_year do we have? is there any gap month where no interest at all? 

SELECT
  COUNT(DISTINCT month_year) ,
  MIN(month_year),
  MAX(month_year),
  EXTRACT(year FROM age(MAX(month_year),MIN(month_year)))* 12 + EXTRACT(month FROM age(MAX(month_year),MIN(month_year))) range
FROM interest_metrics;
-- there is 14 months with range of 13. range will always be lower (n-1). so this means no gap month.

SELECT
    interest_id,
    count(DISTINCT month_year) total_months
FROM interest_metrics
GROUP BY 1
HAVING count(DISTINCT month_year) = 14;

-- B.2 Using this same total_months measure - calculate the cumulative percentage of all records starting at 14 months - 
-- which total_months value passes the 90% cumulative percentage value?
-- key words: ALL RECORDS 

WITH cte AS (
SELECT
    interest_id,
    count(DISTINCT month_year) total_months
FROM interest_metrics
GROUP BY 1
)
SELECT 
    total_months,
    COUNT(total_months) count_interest_id,
    ROUND(100*SUM(COUNT(total_months)) OVER(ORDER BY total_months DESC)/SUM(COUNT(total_months)) OVER(),2) AS cumm_percentage
FROM cte
GROUP BY 1
ORDER BY 1 DESC;

-- 3. If we were to remove all interest_id values which are lower than the total_months value we found in the previous question - 
-- how many total data points would we be removing?

-- the question is unclear. 
SELECT 
    COUNT(*) 
FROM interest_metrics
WHERE interest_id IN (
    SELECT
        interest_id
    FROM interest_metrics
    GROUP BY 1
    HAVING count(DISTINCT month_year) < 14;
    ) -- this is for example if we want to remove datapoint that dont have 14 months data. 

-- 4. Does this decision make sense to remove these data points from a business perspective? 
-- Use an example where there are all 14 months present to a removed interest example for your arguments - 
-- think about what it means to have less months present from a segment perspective.

-- in my opinion it depends on the type of analysis that we want to achieve. if consistency in data is required and that we 
-- need to see the time series based data, we may want to exclude this. But in other many cases, these 'incomplete'
-- monthly data may present different insights that can be required for the business. 


-- 5. If we include all of our interests regardless of their counts - 
-- how many unique interests are there for each month?

SELECT
    month_year, 
    COUNT(DISTINCT interest_id) interest_per_month
FROM interest_metrics
GROUP BY 1;
    
    
-- C. SEGMENT ANALYSIS

-- C.1 Using the complete dataset - which are the top 10 and bottom 10 interests which have the largest composition values 
-- in any month_year? Only use the maximum composition value for each interest but you must keep the corresponding month_year

-- key word: bottom 10 with largest & any month_year (its not bottom 10 with the smallest! I misunderstood this the first time)

WITH cte_compo AS (
SELECT
    interest_id,
    month_year,
    composition,
    RANK() OVER(PARTITION BY interest_id ORDER BY composition DESC) as rank_num
FROM interest_metrics
), top_10 AS ( 
SELECT 
    month_year,
    interest_id,
    composition
FROM cte_compo
WHERE rank_num = 1 
ORDER BY composition DESC
LIMIT 10
), bottom_10 AS ( 
SELECT 
    month_year,
    interest_id,
    composition
FROM cte_compo
WHERE rank_num = 1 
ORDER BY composition 
LIMIT 10    
)
SELECT * FROM top_10
UNION 
SELECT * FROM bottom_10
ORDER BY 3 DESC;
-- just join with interest_map to get the name


-- C.2 Which 5 interests had the lowest average ranking value?
SELECT 
    t1.interest_id,
    t2.interest_name,
    ROUND(AVG(t1.ranking),2) avg_rank,
    COUNT(t1.*) rec_count
FROM interest_metrics t1
INNER JOIN interest_map t2
    ON t1.interest_id = t2.id
GROUP BY 1,2
ORDER BY 3
LIMIT 5;


-- C.3 Which 5 interests had the largest standard deviation in their percentile_ranking value?
SELECT 
    t1.interest_id,
    t2.interest_name,
    ROUND(STDDEV(t1.percentile_ranking::NUMERIC),1) std_deviation,
    max(t1.percentile_ranking),
    min(t1.percentile_ranking),
    COUNT(t1.*) rec_count
FROM interest_metrics t1
INNER JOIN interest_map t2
    ON t1.interest_id = t2.id
GROUP BY 1,2
HAVING COUNT(t1.*) > 1 -- std dev with 1 record only provides null output
ORDER BY 3 DESC
LIMIT 5;


-- C.4 For the 5 interests found in the previous question - what was minimum and maximum percentile_ranking values 
-- for each interest and its corresponding year_month value? Can you describe what is happening for these 5 interests?

SELECT
    t2.interest_name,
    t1.interest_id,
    t1.month_year,
    t1.ranking,
    t1.percentile_ranking,
    t1.composition
FROM interest_metrics t1
INNER JOIN interest_map t2
    ON t1.interest_id = t2.id
WHERE t1.interest_id IN (SELECT interest_id FROM temp_std_dev)
ORDER BY
  t2.interest_name, t1.month_year;


-- similar insight is that all of these interest dropped significantly during early period vs the end period

-- C.5 How would you describe our customers in this segment based off their composition and ranking values? 
-- What sort of products or services should we show to these customers and what should we avoid?


-- D. Index Analysis
---------------------
-- 1. What is the top 10 interests by the average composition for each month?
/*
Note : 
See the information details in the case : 
In July 2018, the composition metric is 11.89, meaning that 11.89% of the client???s customer list 
interacted with the interest interest_id = 32486 - we can link interest_id to a separate mapping table 
to find the segment name called ???Vacation Rental Accommodation Researchers???

The index_value is 6.19, means that the composition value is 6.19x the average composition value for all 
Fresh Segments clients??? customer for this particular interest in the month of July 2018.

The index_value is a measure which can be used to reverse calculate the average composition for Fresh Segments??? clients.
Average composition can be calculated by dividing the composition column by the index_value column rounded to 2 decimal places.

*/



WITH cte AS (
SELECT
    t1.interest_id,
    t2.interest_name,
    t1.month_year,
    ROUND(t1.composition::NUMERIC / t1.index_value::NUMERIC,2) index_compo,
    RANK() OVER(PARTITION BY month_year ORDER BY t1.composition::NUMERIC / t1.index_value::NUMERIC DESC) rank_num
FROM interest_metrics t1
    INNER JOIN interest_map t2
    ON t1.interest_id = t2.id
GROUP BY 1,2,3,t1.composition, t1.index_value
ORDER BY 3,4 DESC
)
SELECT * FROM cte 
WHERE rank_num BETWEEN 1 AND 10;

-- 2. For all of these top 10 interests - which interest appears the most often?

WITH cte AS (
SELECT
    t1.interest_id,
    t2.interest_name,
    t1.month_year,
    ROUND(t1.composition::NUMERIC / t1.index_value::NUMERIC,2) index_compo,
    RANK() OVER(PARTITION BY month_year ORDER BY t1.composition::NUMERIC / t1.index_value::NUMERIC DESC) rank_num
FROM interest_metrics t1
    INNER JOIN interest_map t2
    ON t1.interest_id = t2.id
GROUP BY 1,2,3,t1.composition, t1.index_value
ORDER BY 3,4 DESC
)
SELECT 
    interest_name,
    COUNT(*) total_appearance
FROM cte 
WHERE rank_num BETWEEN 1 AND 10
GROUP BY 1
ORDER BY 2 DESC;

-- 3. What is the average of the average composition for the top 10 interests for each month?
-- grouping the interest and remove the month

WITH cte AS (
SELECT
    t1.interest_id,
    t2.interest_name,
    t1.month_year,
    ROUND(t1.composition::NUMERIC / t1.index_value::NUMERIC,2) index_compo,
    RANK() OVER(PARTITION BY month_year ORDER BY t1.composition::NUMERIC / t1.index_value::NUMERIC DESC) rank_num
FROM interest_metrics t1
    INNER JOIN interest_map t2
    ON t1.interest_id = t2.id
GROUP BY 1,2,3,t1.composition, t1.index_value
ORDER BY 3,4 DESC   
)
SELECT 
    month_year,
    ROUND(AVG(index_compo),2) avg_avg 
FROM cte 
WHERE rank_num BETWEEN 1 AND 10
GROUP BY 1
ORDER BY 1;

-- 4. What is the 3 month rolling average of the max average composition value from September 2018 to August 2019 
-- and include the previous top ranking interests in the same output shown below.

WITH cte_get_max AS (
SELECT
    t1.interest_id,
    t2.interest_name,
    t1.month_year,
    ROUND(t1.composition::NUMERIC / t1.index_value::NUMERIC,2) index_compo,
    RANK() OVER(PARTITION BY month_year ORDER BY t1.composition::NUMERIC / t1.index_value::NUMERIC DESC) rank_num
FROM interest_metrics t1
    INNER JOIN interest_map t2
    ON t1.interest_id = t2.id
GROUP BY 1,2,3,t1.composition, t1.index_value
ORDER BY 3,4 DESC 
), cte_max_list AS ( 
SELECT * FROM cte_get_max
WHERE rank_num =1
), cte_roll AS (
SELECT 
    month_year,
    interest_name, 
    index_compo,
    LAG(interest_name,2) OVER(ORDER BY month_year) lag_2_name,
    LAG(index_compo,2) OVER(ORDER BY month_year) lag_2,
    LAG(interest_name,1) OVER(ORDER BY month_year) lag_1_name,
    LAG(index_compo,1) OVER(ORDER BY month_year) lag_1,
    ROUND(AVG(index_compo) OVER(ORDER BY month_year RANGE BETWEEN '3 MONTHS' PRECEDING AND CURRENT ROW),2) roll_3
FROM cte_max_list
)
SELECT 
    month_year,
    interest_name, 
    index_compo AS month_max_index_compo,
    roll_3 AS "3_months_mov_avg",
    lag_1_name || ': ' || lag_1 AS last_month,
    lag_2_name || ': ' || lag_2 AS "2_months_ago"
FROM cte_roll 
WHERE lag_2 IS NOT NULL ; 


-- 5. Provide a possible reason why the max average composition might change from month to month? 
-- Could it signal something is not quite right with the overall business model for Fresh Segments?


