-- Analysis queries for Power BI reports based on the cleaned retail views:
--   ucitwo.online_retail_ii_2009_2010_clean
--   ucitwo.online_retail_ii_2010_2011_clean
--
-- These are read-only SELECT queries. They do not change the source tables or
-- views. Run each query separately to inspect its result. For Power BI, the
-- recommended model is to load the combined fact query in section 1 and create
-- measures in Power BI, or import the summary queries as separate tables.
--
-- Definitions used below:
--   Gross sales = positive quantity * positive price, excluding C invoices.
--   Net sales   = quantity * price across all rows, retaining returns/credits.
-- Confirm these definitions and currency with the business before publishing.

-- 1. Combined transaction-line fact dataset for Power BI.
-- Append both periods and add a source label. Use this as the central fact table.
SELECT
    '2009-2010' AS SourcePeriod,
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    Price,
    `Customer ID`,
    Country,
    Quantity * Price AS LineNetAmount,
    CASE
        WHEN Invoice LIKE 'C%' OR Quantity < 0 OR Price < 0 THEN 1
        ELSE 0
    END AS IsReturnOrCredit,
    CASE
        WHEN Invoice LIKE 'C%' THEN 1
        ELSE 0
    END AS IsCancellationInvoice
FROM ucitwo.online_retail_ii_2009_2010_clean

UNION ALL

SELECT
    '2010-2011' AS SourcePeriod,
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    Price,
    `Customer ID`,
    Country,
    Quantity * Price AS LineNetAmount,
    CASE
        WHEN Invoice LIKE 'C%' OR Quantity < 0 OR Price < 0 THEN 1
        ELSE 0
    END AS IsReturnOrCredit,
    CASE
        WHEN Invoice LIKE 'C%' THEN 1
        ELSE 0
    END AS IsCancellationInvoice
FROM ucitwo.online_retail_ii_2010_2011_clean;

-- 2. Executive overview by source period.
-- Use for KPI cards and a period comparison table. Net sales retains signed rows.
SELECT
    SourcePeriod,
    COUNT(*) AS InvoiceLines,
    COUNT(DISTINCT Invoice) AS DistinctInvoices,
    COUNT(DISTINCT `Customer ID`) AS IdentifiedCustomers,
    SUM(CASE WHEN `Customer ID` IS NULL THEN 1 ELSE 0 END) AS LinesWithoutCustomerID,
    SUM(CASE WHEN Quantity > 0 AND Price > 0 AND Invoice NOT LIKE 'C%'
             THEN Quantity * Price ELSE 0 END) AS GrossSales,
    SUM(Quantity * Price) AS NetSales,
    SUM(CASE WHEN Quantity > 0 AND Invoice NOT LIKE 'C%' THEN Quantity ELSE 0 END) AS PositiveUnits,
    SUM(CASE WHEN Quantity < 0 OR Invoice LIKE 'C%' THEN 1 ELSE 0 END) AS ReturnOrCancellationLines
FROM (
    SELECT '2009-2010' AS SourcePeriod, Invoice, Quantity, Price, `Customer ID`
    FROM ucitwo.online_retail_ii_2009_2010_clean
    UNION ALL
    SELECT '2010-2011', Invoice, Quantity, Price, `Customer ID`
    FROM ucitwo.online_retail_ii_2010_2011_clean
) AS Retail
GROUP BY SourcePeriod
ORDER BY SourcePeriod;

-- 3. Monthly sales trend.
-- Use as a line chart with MonthStart on the axis and SourcePeriod as legend.
SELECT
    SourcePeriod,
    DATE_FORMAT(InvoiceDate, '%Y-%m-01') AS MonthStart,
    SUM(CASE WHEN Quantity > 0 AND Price > 0 AND Invoice NOT LIKE 'C%'
             THEN Quantity * Price ELSE 0 END) AS GrossSales,
    SUM(Quantity * Price) AS NetSales,
    COUNT(DISTINCT Invoice) AS DistinctInvoices
FROM (
    SELECT '2009-2010' AS SourcePeriod, Invoice, Quantity, Price, InvoiceDate
    FROM ucitwo.online_retail_ii_2009_2010_clean
    UNION ALL
    SELECT '2010-2011', Invoice, Quantity, Price, InvoiceDate
    FROM ucitwo.online_retail_ii_2010_2011_clean
) AS Retail
GROUP BY SourcePeriod, DATE_FORMAT(InvoiceDate, '%Y-%m-01')
ORDER BY MonthStart, SourcePeriod;

-- 4. Product sales by period.
-- Use for a horizontal bar chart. Apply a Power BI Top N filter by GrossSales.
-- Keeping all product-period rows lets the SourcePeriod slicer recalculate Top N.
SELECT
    SourcePeriod,
    StockCode,
    COALESCE(NULLIF(TRIM(Description), ''), '(blank)') AS ProductDescription,
    SUM(Quantity) AS UnitsSold,
    SUM(Quantity * Price) AS GrossSales,
    COUNT(DISTINCT Invoice) AS InvoiceCount
FROM (
    SELECT '2009-2010' AS SourcePeriod, Invoice, StockCode, Description, Quantity, Price
    FROM ucitwo.online_retail_ii_2009_2010_clean
    WHERE Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
    UNION ALL
    SELECT '2010-2011', Invoice, StockCode, Description, Quantity, Price
    FROM ucitwo.online_retail_ii_2010_2011_clean
    WHERE Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
) AS RetailSales
GROUP BY SourcePeriod, StockCode, COALESCE(NULLIF(TRIM(Description), ''), '(blank)')
ORDER BY SourcePeriod, GrossSales DESC;

-- 5. Sales by country and period.
-- Use as a bar chart or map. A map may need country-name normalization in Power BI.
SELECT
    SourcePeriod,
    Country,
    SUM(Quantity * Price) AS GrossSales,
    COUNT(DISTINCT Invoice) AS InvoiceCount,
    COUNT(DISTINCT `Customer ID`) AS IdentifiedCustomers
FROM (
    SELECT '2009-2010' AS SourcePeriod, Country, Invoice, Quantity, Price, `Customer ID`
    FROM ucitwo.online_retail_ii_2009_2010_clean
    WHERE Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
    UNION ALL
    SELECT '2010-2011', Country, Invoice, Quantity, Price, `Customer ID`
    FROM ucitwo.online_retail_ii_2010_2011_clean
    WHERE Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
) AS RetailSales
GROUP BY SourcePeriod, Country
ORDER BY SourcePeriod, GrossSales DESC;

-- 6. Customer performance.
-- Customer ID is missing for some rows, so this only covers identified customers.
-- Use a bar chart for top customers and a table for detail.
SELECT
    SourcePeriod,
    `Customer ID`,
    COUNT(DISTINCT Invoice) AS InvoiceCount,
    SUM(Quantity * Price) AS GrossSales,
    SUM(Quantity) AS UnitsPurchased,
    COUNT(*) AS InvoiceLines
FROM (
    SELECT '2009-2010' AS SourcePeriod, Invoice, `Customer ID`, Quantity, Price
    FROM ucitwo.online_retail_ii_2009_2010_clean
    WHERE `Customer ID` IS NOT NULL
      AND Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
    UNION ALL
    SELECT '2010-2011', Invoice, `Customer ID`, Quantity, Price
    FROM ucitwo.online_retail_ii_2010_2011_clean
    WHERE `Customer ID` IS NOT NULL
      AND Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
) AS CustomerSales
GROUP BY SourcePeriod, `Customer ID`
ORDER BY GrossSales DESC;

-- 7. Returns and cancellation summary by period.
-- Negative quantities/prices and C-prefixed invoices are retained for net analysis.
SELECT
    SourcePeriod,
    SUM(CASE WHEN Quantity < 0 THEN 1 ELSE 0 END) AS NegativeQuantityLines,
    SUM(CASE WHEN Price < 0 THEN 1 ELSE 0 END) AS NegativePriceLines,
    SUM(CASE WHEN Invoice LIKE 'C%' THEN 1 ELSE 0 END) AS CancellationInvoiceLines,
    SUM(CASE WHEN Quantity < 0 OR Invoice LIKE 'C%' THEN Quantity * Price ELSE 0 END) AS ReturnOrCreditNetAmount,
    SUM(Quantity * Price) AS NetAmountAllLines
FROM (
    SELECT '2009-2010' AS SourcePeriod, Invoice, Quantity, Price
    FROM ucitwo.online_retail_ii_2009_2010_clean
    UNION ALL
    SELECT '2010-2011', Invoice, Quantity, Price
    FROM ucitwo.online_retail_ii_2010_2011_clean
) AS Retail
GROUP BY SourcePeriod
ORDER BY SourcePeriod;

-- 8. Invoice/order value distribution for gross sales.
-- Use a histogram in Power BI after loading these invoice-level values.
SELECT
    SourcePeriod,
    Invoice,
    MIN(InvoiceDate) AS InvoiceDate,
    SUM(Quantity * Price) AS InvoiceGrossValue,
    COUNT(*) AS InvoiceLines,
    COUNT(DISTINCT StockCode) AS DistinctProducts
FROM (
    SELECT '2009-2010' AS SourcePeriod, Invoice, InvoiceDate, Quantity, Price, StockCode
    FROM ucitwo.online_retail_ii_2009_2010_clean
    WHERE Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
    UNION ALL
    SELECT '2010-2011', Invoice, InvoiceDate, Quantity, Price, StockCode
    FROM ucitwo.online_retail_ii_2010_2011_clean
    WHERE Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
) AS RetailSales
GROUP BY SourcePeriod, Invoice
ORDER BY InvoiceDate, Invoice;

-- 9. Data quality summary for report cards or a quality table.
SELECT
    SourcePeriod,
    COUNT(*) AS TotalRows,
    SUM(`Customer ID` IS NULL) AS MissingCustomerIDRows,
    SUM(Description IS NULL OR TRIM(Description) = '') AS BlankDescriptionRows,
    SUM(Quantity < 0) AS NegativeQuantityRows,
    SUM(Price < 0) AS NegativePriceRows,
    SUM(Invoice LIKE 'C%') AS CancellationInvoiceRows
FROM (
    SELECT '2009-2010' AS SourcePeriod, Invoice, Description, Quantity, Price, `Customer ID`
    FROM ucitwo.online_retail_ii_2009_2010_clean
    UNION ALL
    SELECT '2010-2011', Invoice, Description, Quantity, Price, `Customer ID`
    FROM ucitwo.online_retail_ii_2010_2011_clean
) AS Retail
GROUP BY SourcePeriod
ORDER BY SourcePeriod;

-- 10. Outlier review dataset from both periods.
-- These thresholds apply only to positive quantity/price rows from non-C invoices.
-- The output flags candidate outliers; it does not remove or cap them.
-- Consider keeping the detailed output as a drill-through table rather than
-- importing every row into a report page.
WITH eligible AS (
    SELECT SourcePeriod, Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Country
    FROM (
        SELECT '2009-2010' AS SourcePeriod, Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Country
        FROM ucitwo.online_retail_ii_2009_2010_clean
        WHERE Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
        UNION ALL
        SELECT '2010-2011', Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Country
        FROM ucitwo.online_retail_ii_2010_2011_clean
        WHERE Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
    ) AS CombinedSales
),
ranked AS (
    SELECT
        eligible.*,
        ROW_NUMBER() OVER (PARTITION BY SourcePeriod ORDER BY Quantity) AS quantity_rank,
        ROW_NUMBER() OVER (PARTITION BY SourcePeriod ORDER BY Price) AS price_rank,
        COUNT(*) OVER (PARTITION BY SourcePeriod) AS row_count
    FROM eligible
),
quartiles AS (
    SELECT
        SourcePeriod,
        MAX(CASE WHEN quantity_rank = CEIL(0.25 * row_count) THEN Quantity END) AS q1_quantity,
        MAX(CASE WHEN quantity_rank = CEIL(0.75 * row_count) THEN Quantity END) AS q3_quantity,
        MAX(CASE WHEN price_rank = CEIL(0.25 * row_count) THEN Price END) AS q1_price,
        MAX(CASE WHEN price_rank = CEIL(0.75 * row_count) THEN Price END) AS q3_price
    FROM ranked
    GROUP BY SourcePeriod
),
fences AS (
    SELECT
        SourcePeriod,
        q1_quantity - 1.5 * (q3_quantity - q1_quantity) AS quantity_low,
        q3_quantity + 1.5 * (q3_quantity - q1_quantity) AS quantity_high,
        q1_price - 1.5 * (q3_price - q1_price) AS price_low,
        q3_price + 1.5 * (q3_price - q1_price) AS price_high
    FROM quartiles
)
SELECT
    r.SourcePeriod,
    r.Invoice,
    r.StockCode,
    r.Description,
    r.Quantity,
    r.InvoiceDate,
    r.Price,
    r.Country,
    CASE WHEN r.Quantity < f.quantity_low OR r.Quantity > f.quantity_high THEN 1 ELSE 0 END AS QuantityOutlier,
    CASE WHEN r.Price < f.price_low OR r.Price > f.price_high THEN 1 ELSE 0 END AS PriceOutlier
FROM ranked AS r
JOIN fences AS f ON f.SourcePeriod = r.SourcePeriod
WHERE r.Quantity < f.quantity_low
   OR r.Quantity > f.quantity_high
   OR r.Price < f.price_low
   OR r.Price > f.price_high
ORDER BY r.SourcePeriod, r.InvoiceDate, r.Invoice;

-- 11. Customer coverage by period.
-- Put IdentifiedCustomerLines / TotalLines on a coverage card. Customer
-- contribution measures should be interpreted with this coverage in view.
SELECT
    SourcePeriod,
    COUNT(*) AS TotalLines,
    SUM(CASE WHEN `Customer ID` IS NOT NULL THEN 1 ELSE 0 END) AS IdentifiedCustomerLines,
    COUNT(DISTINCT CASE WHEN `Customer ID` IS NOT NULL THEN `Customer ID` END) AS IdentifiedCustomers,
    ROUND(100.0 * SUM(CASE WHEN `Customer ID` IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS IdentifiedCustomerLineCoveragePct
FROM (
    SELECT '2009-2010' AS SourcePeriod, `Customer ID` FROM ucitwo.online_retail_ii_2009_2010_clean
    UNION ALL
    SELECT '2010-2011', `Customer ID` FROM ucitwo.online_retail_ii_2010_2011_clean
) AS Retail
GROUP BY SourcePeriod
ORDER BY SourcePeriod;

-- 12. Repeat customer activity and contribution.
-- A repeat customer has purchases in at least two distinct invoices within the
-- same source period. Missing customer IDs are excluded by design.
SELECT
    SourcePeriod,
    COUNT(*) AS IdentifiedCustomers,
    SUM(CASE WHEN InvoiceCount >= 2 THEN 1 ELSE 0 END) AS RepeatCustomers,
    ROUND(100.0 * SUM(CASE WHEN InvoiceCount >= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS RepeatCustomerPct,
    SUM(GrossSales) AS IdentifiedCustomerGrossSales,
    SUM(CASE WHEN InvoiceCount >= 2 THEN GrossSales ELSE 0 END) AS RepeatCustomerGrossSales
FROM (
    SELECT SourcePeriod, `Customer ID`,
           COUNT(DISTINCT Invoice) AS InvoiceCount,
           SUM(Quantity * Price) AS GrossSales
    FROM (
        SELECT '2009-2010' AS SourcePeriod, Invoice, `Customer ID`, Quantity, Price
        FROM ucitwo.online_retail_ii_2009_2010_clean
        WHERE `Customer ID` IS NOT NULL AND Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
        UNION ALL
        SELECT '2010-2011', Invoice, `Customer ID`, Quantity, Price
        FROM ucitwo.online_retail_ii_2010_2011_clean
        WHERE `Customer ID` IS NOT NULL AND Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
    ) AS CustomerLines
    GROUP BY SourcePeriod, `Customer ID`
) AS CustomerSummary
GROUP BY SourcePeriod
ORDER BY SourcePeriod;

-- 13. Basket patterns at invoice level.
-- Import the output for basket-size distributions, average basket value, and
-- distinct products per order. Gross sales conditions exclude returns/credits.
SELECT
    SourcePeriod,
    Invoice,
    MIN(InvoiceDate) AS InvoiceDate,
    COUNT(*) AS LineCount,
    COUNT(DISTINCT StockCode) AS DistinctProducts,
    SUM(Quantity) AS UnitsInBasket,
    SUM(Quantity * Price) AS BasketGrossSales
FROM (
    SELECT '2009-2010' AS SourcePeriod, Invoice, InvoiceDate, StockCode, Quantity, Price
    FROM ucitwo.online_retail_ii_2009_2010_clean
    WHERE Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
    UNION ALL
    SELECT '2010-2011', Invoice, InvoiceDate, StockCode, Quantity, Price
    FROM ucitwo.online_retail_ii_2010_2011_clean
    WHERE Invoice NOT LIKE 'C%' AND Quantity > 0 AND Price > 0
) AS SalesLines
GROUP BY SourcePeriod, Invoice
ORDER BY InvoiceDate, Invoice;

-- 14. Monthly returns and cancellation trends.
-- Use MonthStart as the line-chart axis and SourcePeriod as legend. Signed
-- ReturnOrCreditNetAmount shows the net value of rows marked as return/credit.
SELECT
    SourcePeriod,
    DATE_FORMAT(InvoiceDate, '%Y-%m-01') AS MonthStart,
    SUM(CASE WHEN Quantity < 0 THEN 1 ELSE 0 END) AS NegativeQuantityLines,
    SUM(CASE WHEN Price < 0 THEN 1 ELSE 0 END) AS NegativePriceLines,
    SUM(CASE WHEN Invoice LIKE 'C%' THEN 1 ELSE 0 END) AS CancellationInvoiceLines,
    SUM(CASE WHEN Quantity < 0 OR Invoice LIKE 'C%' THEN Quantity * Price ELSE 0 END) AS ReturnOrCreditNetAmount,
    SUM(Quantity * Price) AS NetAmountAllLines
FROM (
    SELECT '2009-2010' AS SourcePeriod, Invoice, Quantity, Price, InvoiceDate
    FROM ucitwo.online_retail_ii_2009_2010_clean
    UNION ALL
    SELECT '2010-2011', Invoice, Quantity, Price, InvoiceDate
    FROM ucitwo.online_retail_ii_2010_2011_clean
) AS Retail
GROUP BY SourcePeriod, DATE_FORMAT(InvoiceDate, '%Y-%m-01')
ORDER BY MonthStart, SourcePeriod;

-- 15. Exact duplicate-candidate summary by source period.
-- This counts excess copies of fully identical rows. Treat as candidates for
-- review; repeated identical invoice lines can be legitimate.
SELECT
    SourcePeriod,
    COUNT(*) AS DuplicateGroups,
    SUM(copies - 1) AS ExcessDuplicateRows
FROM (
    SELECT '2009-2010' AS SourcePeriod, Invoice, StockCode, Description, Quantity,
           InvoiceDate, Price, `Customer ID`, Country, COUNT(*) AS copies
    FROM ucitwo.online_retail_ii_2009_2010_clean
    GROUP BY Invoice, StockCode, Description, Quantity, InvoiceDate, Price, `Customer ID`, Country
    HAVING COUNT(*) > 1
    UNION ALL
    SELECT '2010-2011', Invoice, StockCode, Description, Quantity,
           InvoiceDate, Price, `Customer ID`, Country, COUNT(*) AS copies
    FROM ucitwo.online_retail_ii_2010_2011_clean
    GROUP BY Invoice, StockCode, Description, Quantity, InvoiceDate, Price, `Customer ID`, Country
    HAVING COUNT(*) > 1
) AS DuplicateGroupsByPeriod
GROUP BY SourcePeriod
ORDER BY SourcePeriod;
