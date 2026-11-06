-- Cleaning and profiling queries for:
--   ucitwo.online_retail_ii_2010_2011
--
-- The source table is not modified. Section 3 creates/replaces a regular view
-- in schema ucitwo; the view remains until it is dropped. Review profiling,
-- duplicate, return/cancellation, and outlier results before excluding data.

-- 1. Baseline data quality profile.
SELECT
    COUNT(*) AS total_rows,
    SUM(Invoice IS NULL OR TRIM(Invoice) = '') AS missing_invoice,
    SUM(StockCode IS NULL OR TRIM(StockCode) = '') AS missing_stock_code,
    SUM(Description IS NULL OR TRIM(Description) = '') AS blank_description,
    SUM(InvoiceDate IS NULL OR TRIM(InvoiceDate) = '') AS missing_invoice_date,
    SUM(Price IS NULL) AS missing_price,
    SUM(`Customer ID` IS NULL OR TRIM(`Customer ID`) = '') AS missing_customer_id,
    SUM(Country IS NULL OR TRIM(Country) = '') AS missing_country,
    SUM(Quantity < 0) AS negative_quantity_rows,
    SUM(Quantity = 0) AS zero_quantity_rows,
    SUM(Price < 0) AS negative_price_rows,
    SUM(Price = 0) AS zero_price_rows,
    SUM(Invoice LIKE 'C%') AS cancellation_invoice_rows,
    SUM(Description <> TRIM(Description)) AS description_outer_whitespace,
    SUM(StockCode <> TRIM(StockCode)) AS stock_code_outer_whitespace
FROM ucitwo.online_retail_ii_2010_2011;

-- 2. Validate dates against the source format m/d/yyyy h:mm.
-- Expected result is zero rows. Investigate any values returned.
SELECT InvoiceDate
FROM ucitwo.online_retail_ii_2010_2011
WHERE InvoiceDate IS NOT NULL
  AND TRIM(InvoiceDate) <> ''
  AND STR_TO_DATE(TRIM(InvoiceDate), '%m/%d/%Y %H:%i') IS NULL
GROUP BY InvoiceDate
ORDER BY InvoiceDate;

-- 3. Create a cleaned view without changing/deleting source rows.
-- Trims text, turns empty strings into NULL, parses InvoiceDate, and converts
-- Customer ID from text to an integer where numeric. Non-numeric IDs become NULL.
-- Returns, cancellations, and numeric extremes remain in the view.
CREATE OR REPLACE VIEW ucitwo.online_retail_ii_2010_2011_clean AS
SELECT
    NULLIF(TRIM(Invoice), '') AS Invoice,
    NULLIF(TRIM(StockCode), '') AS StockCode,
    NULLIF(TRIM(Description), '') AS Description,
    Quantity,
    STR_TO_DATE(TRIM(InvoiceDate), '%m/%d/%Y %H:%i') AS InvoiceDate,
    Price,
    CASE
        WHEN TRIM(`Customer ID`) REGEXP '^[0-9]+$'
        THEN CAST(TRIM(`Customer ID`) AS UNSIGNED)
        ELSE NULL
    END AS `Customer ID`,
    NULLIF(TRIM(Country), '') AS Country
FROM ucitwo.online_retail_ii_2010_2011;

-- 4. Check for non-numeric customer identifiers before relying on the numeric
-- conversion in the view. Any values returned become NULL in the view.
SELECT `Customer ID`, COUNT(*) AS rows_with_value
FROM ucitwo.online_retail_ii_2010_2011
WHERE `Customer ID` IS NOT NULL
  AND TRIM(`Customer ID`) <> ''
  AND TRIM(`Customer ID`) NOT REGEXP '^[0-9]+$'
GROUP BY `Customer ID`
ORDER BY rows_with_value DESC, `Customer ID`;

-- 5. Review groups of exact duplicate rows. Identical records may be valid
-- repeated invoice lines; confirm duplicate imports before removing anything.
SELECT
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    Price,
    `Customer ID`,
    Country,
    COUNT(*) AS copies
FROM ucitwo.online_retail_ii_2010_2011
GROUP BY
    Invoice, StockCode, Description, Quantity,
    InvoiceDate, Price, `Customer ID`, Country
HAVING COUNT(*) > 1
ORDER BY copies DESC, Invoice, StockCode;

-- 6. Calculate 1.5 x IQR fences for positive quantities and prices from
-- non-cancellation invoices. Returns, cancellations, zeroes, and negative
-- values are excluded from this threshold population. They remain in the view.
-- Quartiles use nearest-rank values and may differ slightly from interpolated
-- percentile implementations.
WITH eligible AS (
    SELECT Quantity, Price
    FROM ucitwo.online_retail_ii_2010_2011_clean
    WHERE Invoice NOT LIKE 'C%'
      AND Quantity > 0
      AND Price > 0
),
ranked AS (
    SELECT
        Quantity,
        Price,
        ROW_NUMBER() OVER (ORDER BY Quantity) AS quantity_rank,
        ROW_NUMBER() OVER (ORDER BY Price) AS price_rank,
        COUNT(*) OVER () AS row_count
    FROM eligible
),
quartiles AS (
    SELECT
        MAX(CASE WHEN quantity_rank = CEIL(0.25 * row_count) THEN Quantity END) AS q1_quantity,
        MAX(CASE WHEN quantity_rank = CEIL(0.75 * row_count) THEN Quantity END) AS q3_quantity,
        MAX(CASE WHEN price_rank = CEIL(0.25 * row_count) THEN Price END) AS q1_price,
        MAX(CASE WHEN price_rank = CEIL(0.75 * row_count) THEN Price END) AS q3_price
    FROM ranked
)
SELECT
    q1_quantity,
    q3_quantity,
    q1_quantity - 1.5 * (q3_quantity - q1_quantity) AS quantity_lower_fence,
    q3_quantity + 1.5 * (q3_quantity - q1_quantity) AS quantity_upper_fence,
    q1_price,
    q3_price,
    q1_price - 1.5 * (q3_price - q1_price) AS price_lower_fence,
    q3_price + 1.5 * (q3_price - q1_price) AS price_upper_fence
FROM quartiles;

-- 7. Count and list rows flagged by the same IQR fences. These are candidates
-- for review, not automatic errors. A row can be an outlier for both measures.
WITH eligible AS (
    SELECT *
    FROM ucitwo.online_retail_ii_2010_2011_clean
    WHERE Invoice NOT LIKE 'C%'
      AND Quantity > 0
      AND Price > 0
),
ranked AS (
    SELECT
        eligible.*,
        ROW_NUMBER() OVER (ORDER BY Quantity) AS quantity_rank,
        ROW_NUMBER() OVER (ORDER BY Price) AS price_rank,
        COUNT(*) OVER () AS row_count
    FROM eligible
),
quartiles AS (
    SELECT
        MAX(CASE WHEN quantity_rank = CEIL(0.25 * row_count) THEN Quantity END) AS q1_quantity,
        MAX(CASE WHEN quantity_rank = CEIL(0.75 * row_count) THEN Quantity END) AS q3_quantity,
        MAX(CASE WHEN price_rank = CEIL(0.25 * row_count) THEN Price END) AS q1_price,
        MAX(CASE WHEN price_rank = CEIL(0.75 * row_count) THEN Price END) AS q3_price
    FROM ranked
),
fences AS (
    SELECT
        q1_quantity - 1.5 * (q3_quantity - q1_quantity) AS quantity_low,
        q3_quantity + 1.5 * (q3_quantity - q1_quantity) AS quantity_high,
        q1_price - 1.5 * (q3_price - q1_price) AS price_low,
        q3_price + 1.5 * (q3_price - q1_price) AS price_high
    FROM quartiles
)
SELECT
    r.Invoice,
    r.StockCode,
    r.Description,
    r.Quantity,
    r.InvoiceDate,
    r.Price,
    r.`Customer ID`,
    r.Country,
    CASE
        WHEN r.Quantity < f.quantity_low OR r.Quantity > f.quantity_high THEN 1
        ELSE 0
    END AS quantity_outlier,
    CASE
        WHEN r.Price < f.price_low OR r.Price > f.price_high THEN 1
        ELSE 0
    END AS price_outlier
FROM ranked AS r
CROSS JOIN fences AS f
WHERE r.Quantity < f.quantity_low
   OR r.Quantity > f.quantity_high
   OR r.Price < f.price_low
   OR r.Price > f.price_high
ORDER BY r.InvoiceDate, r.Invoice;

-- 8. Optional sales-only population for gross sales analyses. For net-sales
-- analysis, use the full cleaned view so return/cancellation records remain.
SELECT *
FROM ucitwo.online_retail_ii_2010_2011_clean
WHERE Invoice NOT LIKE 'C%'
  AND Quantity > 0
  AND Price > 0;
