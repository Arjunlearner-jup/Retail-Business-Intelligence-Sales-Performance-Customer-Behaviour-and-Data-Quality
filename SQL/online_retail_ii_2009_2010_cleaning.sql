SELECT
    COUNT(*) AS total_rows,
    SUM(Invoice IS NULL OR TRIM(Invoice) = '') AS missing_invoice,
    SUM(StockCode IS NULL OR TRIM(StockCode) = '') AS missing_stock_code,
    SUM(Description IS NULL OR TRIM(Description) = '') AS blank_description,
    SUM(InvoiceDate IS NULL OR TRIM(InvoiceDate) = '') AS missing_invoice_date,
    SUM(Price IS NULL) AS missing_price,
    SUM(`Customer ID` IS NULL) AS missing_customer_id,
    SUM(Country IS NULL OR TRIM(Country) = '') AS missing_country,
    SUM(Quantity < 0) AS negative_quantity_rows,
    SUM(Quantity = 0) AS zero_quantity_rows,
    SUM(Price < 0) AS negative_price_rows,
    SUM(Price = 0) AS zero_price_rows,
    SUM(Invoice LIKE 'C%') AS cancellation_invoice_rows
FROM ucitwo.online_retail_ii_2009_2010;

-- 2. Check date strings can be parsed using the dataset's m/d/yyyy h:mm format.
SELECT InvoiceDate
FROM ucitwo.online_retail_ii_2009_2010
WHERE InvoiceDate IS NOT NULL
  AND TRIM(InvoiceDate) <> ''
  AND STR_TO_DATE(TRIM(InvoiceDate), '%m/%d/%Y %H:%i') IS NULL
GROUP BY InvoiceDate
ORDER BY InvoiceDate;

-- 3. Create a cleaned view without changing or deleting source rows.
CREATE OR REPLACE VIEW ucitwo.online_retail_ii_2009_2010_clean AS
SELECT
    NULLIF(TRIM(Invoice), '') AS Invoice,
    NULLIF(TRIM(StockCode), '') AS StockCode,
    NULLIF(TRIM(Description), '') AS Description,
    Quantity,
    STR_TO_DATE(TRIM(InvoiceDate), '%m/%d/%Y %H:%i') AS InvoiceDate,
    Price,
    `Customer ID`,
    NULLIF(TRIM(Country), '') AS Country
FROM ucitwo.online_retail_ii_2009_2010;

-- 4. Review exact duplicate groups. Identical lines can be valid transaction
-- records; do not remove them without confirming they are duplicate imports.
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
FROM ucitwo.online_retail_ii_2009_2010
GROUP BY
    Invoice, StockCode, Description, Quantity,
    InvoiceDate, Price, `Customer ID`, Country
HAVING COUNT(*) > 1
ORDER BY copies DESC, Invoice, StockCode;

-- 5. Compute 1.5 x IQR outlier fences for positive sales quantities and prices.
-- Cancellations, returns, zeroes, and negative values are excluded from the
-- threshold calculation because they represent a different transaction type.
-- Quartiles use the nearest-rank method; thresholds can differ slightly from
-- software that interpolates between percentile values.
WITH eligible AS (
    SELECT Quantity, Price
    FROM ucitwo.online_retail_ii_2009_2010_clean
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

-- 6. List potential outlier rows for inspection, using the same population
-- and thresholds as section 5. This flags values; it does not delete or cap them.
WITH eligible AS (
    SELECT *
    FROM ucitwo.online_retail_ii_2009_2010_clean
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

-- 7. Optional sales-only analysis population.
-- Use this filter for gross sales calculations; retain the full clean view
-- when analyzing net sales, returns, or cancellations.
SELECT *
FROM ucitwo.online_retail_ii_2009_2010_clean
WHERE Invoice NOT LIKE 'C%'
  AND Quantity > 0
  AND Price > 0;
