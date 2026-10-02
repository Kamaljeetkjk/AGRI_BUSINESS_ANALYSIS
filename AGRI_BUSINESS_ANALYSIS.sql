-- CREATED DATABASE
CREATE DATABASE AGRI_BUSINESS_ANALYSIS;
USE AGRI_BUSINESS_ANALYSIS

--CREATED TABLE 
CREATE TABLE AGRI_TABLE(
    State_Name VARCHAR(255),
    District_Name VARCHAR(255),
    Crop_Year VARCHAR(50),
    Season VARCHAR(100),
    Crop VARCHAR(100),
    Area VARCHAR(100),
    Production VARCHAR(100)
);


-- IMPORTING DATASETS
BULK INSERT AGRI_TABLE
FROM 'C:\Users\HP\Desktop\AGRI_PLACMENT_PROJECT\AGRI_DATASETS.csv' 
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK
);





--Detect Non-Numeric Text Patterns
-- Find any non-numeric strings in Area or Production
SELECT Area, Production 
FROM AGRI_TABLE
WHERE TRY_CAST(Area AS INT) IS NULL AND Area IS NOT NULL
   OR TRY_CAST(Production AS INT) IS NULL AND Production IS NOT NULL;





--Identify Specific Invalid Tokens (NA, -, Blanks)

-- List unique invalid text entries
SELECT DISTINCT Area 
FROM AGRI_TABLE 
WHERE Area LIKE '%[a-zA-Z-]%' OR Area = '';

SELECT DISTINCT Production 
FROM AGRI_TABLE 
WHERE Production LIKE '%[a-zA-Z-]%' OR Production = '';





-- Check for commas or decimal points in numeric columns
SELECT Area, Production
FROM AGRI_TABLE
WHERE Area LIKE '%,%' OR Area LIKE '%.%'
   OR Production LIKE '%,%' OR Production LIKE '%.%';




--Before changing data types from VARCHAR to INT, I conducted a data profiling check using TRY_CAST
-- and string pattern queries. This revealed that the raw dataset contained missing value indicators 
--('NA', '-'), formatted numbers with commas ('12,500'), and decimal numbers ('120.50'). Identifying 
--these specific anomalies guided my cleaning strategy before executing the ALTER TABLE statement."

-- 1. Replace invalid text ('NA', '-', blanks, empty strings) with NULL
UPDATE AGRI_TABLE
SET Area = NULLIF(LTRIM(RTRIM(Area)), 'NA'),
    Production = NULLIF(LTRIM(RTRIM(Production)), 'NA');

UPDATE AGRI_TABLE
SET Area = NULLIF(LTRIM(RTRIM(Area)), '-'),
    Production = NULLIF(LTRIM(RTRIM(Production)), '-');

UPDATE AGRI_TABLE
SET Area = NULLIF(LTRIM(RTRIM(Area)), ''),
    Production = NULLIF(LTRIM(RTRIM(Production)), '');

-- 2. Remove commas if present (e.g., '12,500' -> '12500')
UPDATE AGRI_TABLE
SET Area = REPLACE(Area, ',', ''),
    Production = REPLACE(Production, ',', '');

-- 3. Round decimal strings and convert values to numbers
UPDATE AGRI_TABLE
SET Area = CAST(ROUND(CAST(Area AS FLOAT), 0) AS INT),
    Production = CAST(ROUND(CAST(Production AS FLOAT), 0) AS INT);

-- 4. Convert table columns permanently to INT for calculations
ALTER TABLE AGRI_TABLE ALTER COLUMN Area INT;
ALTER TABLE AGRI_TABLE ALTER COLUMN Production INT;

SELECT * FROM AGRI_TABLE








--------------SQL ANALYSIS---------------

--Calculate crop yield (production per unit area) to assess which crops are the most efficient in production.

SELECT 
    Crop,
    SUM(CAST(Area AS BIGINT)) AS Total_Area,
    SUM(CAST(Production AS BIGINT)) AS Total_Production,
    -- Convert to BIGINT and FLOAT to prevent overflow and preserve precision
    ROUND(
        CAST(SUM(CAST(Production AS BIGINT)) AS FLOAT) / 
        NULLIF(SUM(CAST(Area AS BIGINT)), 0), 2
    ) AS Crop_Yield_Per_Unit_Area
FROM AGRI_TABLE
GROUP BY Crop
HAVING SUM(CAST(Area AS BIGINT)) > 0 
ORDER BY Crop_Yield_Per_Unit_Area DESC;

--============COCONUT ARE HIGHEST  WITH 4579.77 CROP YIELD PER UNIT AREA which proves total production along can be misleading but
-- Crop Yield shows true land efficiency.=========================================






--Calculates the year-over-year percentage growth in crop production for each state and crop.

WITH Yearly_Production AS (
    -- Step 1: Aggregate total production per State, Crop, and Year
    SELECT 
        State_Name,
        Crop,
        Crop_Year,
        SUM(CAST(Production AS BIGINT)) AS Current_Production
    FROM AGRI_TABLE
    GROUP BY State_Name, Crop, Crop_Year
),
YoY_Lag AS (
    -- Step 2: Fetch the previous year's production using LAG()
    SELECT 
        State_Name,
        Crop,
        Crop_Year,
        Current_Production,
        LAG(Current_Production) OVER (
            PARTITION BY State_Name, Crop 
            ORDER BY Crop_Year
        ) AS Previous_Production
    FROM Yearly_Production
)
-- Step 3: Compute YoY Percentage Growth
SELECT 
    State_Name,
    Crop,
    Crop_Year,
    Current_Production,
    Previous_Production,
    ROUND(
        (CAST(Current_Production - Previous_Production AS FLOAT) / 
        NULLIF(Previous_Production, 0)) * 100, 2
    ) AS YoY_Growth_Percentage
FROM YoY_Lag
ORDER BY State_Name, Crop, Crop_Year;



---  =======Outcomes: It will spot sudden growth caused by multiple reason( i.e climate change) it is matter because yoy normalise it and
-- reveal high performance regions and crops regardless of state size.===================================


--calculates each state's average yield (production per area) and identifies the top 5 states with the highest
-- average yield over multiple years.

SELECT TOP 5
    State_Name,
    SUM(CAST(Area AS BIGINT)) AS Total_Area,
    SUM(CAST(Production AS BIGINT)) AS Total_Production,
    -- Calculate overall state yield across all recorded years
    ROUND(
        CAST(SUM(CAST(Production AS BIGINT)) AS FLOAT) / 
        NULLIF(SUM(CAST(Area AS BIGINT)), 0), 2
    ) AS Average_State_Yield
FROM AGRI_TABLE
GROUP BY State_Name
-- Exclude states where total area is zero or missing
HAVING SUM(CAST(Area AS BIGINT)) > 0
ORDER BY Average_State_Yield DESC;

--===========Outcomes:identified Kerala,Andaman and nicobar puducheery as top performer by high yield crop production
----this benchmark helps to achieve high production including size land  & favorable climate =======================




--calculates the variance in production across different crops and states. (tip: use VAR function).

SELECT 
    State_Name,
    Crop,
    COUNT(Production) AS Sample_Size,
    AVG(CAST(Production AS FLOAT)) AS Avg_Production,
    -- Calculate sample variance in crop production across recorded years/districts
    ROUND(VAR(CAST(Production AS FLOAT)), 2) AS Production_Variance,
    -- Standard deviation (square root of variance) for easier interpretation
    ROUND(STDEV(CAST(Production AS FLOAT)), 2) AS Production_StdDev
FROM AGRI_TABLE
WHERE Production IS NOT NULL
GROUP BY State_Name, Crop
HAVING COUNT(Production) > 1 -- Variance requires at least 2 data points
ORDER BY Production_Variance DESC;



--====Outcomes: It measure the stability and risk across the regions findout  Kerala, AP, Tamilnadu has exterme
-- variance due to large farming.It identify to pinpoint farming instable agri-business regions. ===============




--Identifies states that have the largest increase in cultivated area for a specific crop between two years

WITH MinMaxYears AS (
    SELECT 
        MIN(Crop_Year) AS MinYr, 
        MAX(Crop_Year) AS MaxYr
    FROM AGRI_TABLE
),
Target_Years_Area AS (
    SELECT 
        a.State_Name,
        SUM(CASE WHEN a.Crop_Year = m.MinYr THEN CAST(a.Area AS BIGINT) ELSE 0 END) AS Area_Start_Year,
        SUM(CASE WHEN a.Crop_Year = m.MaxYr THEN CAST(a.Area AS BIGINT) ELSE 0 END) AS Area_End_Year
    FROM AGRI_TABLE a
    CROSS JOIN MinMaxYears m
    WHERE UPPER(LTRIM(RTRIM(a.Crop))) = 'WHEAT' 
    GROUP BY a.State_Name
)
SELECT 
    State_Name,
    Area_Start_Year,
    Area_End_Year,
    (Area_End_Year - Area_Start_Year) AS Absolute_Area_Increase,
    ROUND(
        (CAST(Area_End_Year - Area_Start_Year AS FLOAT) / 
        NULLIF(Area_Start_Year, 0)) * 100, 2
    ) AS Percentage_Area_Increase
FROM Target_Years_Area
WHERE (Area_End_Year - Area_Start_Year) > 0
ORDER BY Absolute_Area_Increase DESC;



--=========Outcomes: Identifying regional shift so I took wheat crop  and compare cultivated area between base year  and max years 
--and findout sikkim  has absolute area increase with 323 hectares where it start with zero and moving with 323  heactares units.


------------------------------------------------------------------

--Major Outcomes:
--1.From Business prespective high total production doesn't always equal high productivity.
--2.State with high acrege need to target yield improvement stratergies.
--3.Seasonal crops Require Regional Supplychain alignment.


----------------------------End of projects.---------------------------------------------------------