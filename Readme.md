# Retail Business Intelligence: Sales Performance, Customer Behaviour and Data Quality

The project prepares the UCI Online Retail II transaction data in the MySQL `ucitwo` schema for data-quality review and Power BI reporting. The SQL scripts inspect the imported data, create cleaned views without deleting source rows, and provide transaction-level and summary queries for analysis.

## Database objects

| Object | Type | Description |
  |---|---|---|
  | `ucitwo.online_retail_ii_2009_2010` | Source table | Imported transaction lines for 2009–2010. |
  | `ucitwo.online_retail_ii_2010_2011` | Source table | Imported transaction lines for 2010–2011. |
  | `ucitwo.online_retail_ii_2009_2010_clean` | View | Trimmed and normalized view over the 2009–2010 source table. |
  | `ucitwo.online_retail_ii_2010_2011_clean` | View | Trimmed and normalized view over the 2010–2011 source table. |
  
  Each cleaned view exposes these fields:
  
  | Column | Meaning |
  |---|---|
  | `Invoice` | Invoice identifier. IDs beginning with `C` indicate cancellation invoices. |
  | `StockCode` | Product/stock identifier. |
  | `Description` | Product description. |
  | `Quantity` | Units on the invoice line; negative values can indicate returns or credits. |
  | `InvoiceDate` | Parsed transaction date and time. |
  | `Price` | Unit price. |
  | `Customer ID` | Customer identifier; missing or non-numeric values can be `NULL`. |
  | `Country` | Customer country. |
  
  The cleaned 2010–2011 view casts numeric customer IDs to an unsigned integer; the 2009–2010 view preserves the source customer-ID type. Treat the field as an identifier, not a quantity.

## SQL files

| File | Purpose |
  |---|---|
  | [`online_retail_ii_2009_2010_cleaning.sql`](online_retail_ii_2009_2010_cleaning.sql) | Profiles the 2009–2010 source, checks date strings, creates its cleaned view, reviews duplicates and IQR outliers, and selects a positive-sales population. |
  | [`online_retail_ii_2010_2011_cleaning.sql`](online_retail_ii_2010_2011_cleaning.sql) | Performs the corresponding 2010–2011 profile, date validation, cleaned-view creation, customer-ID validation, duplicate review, and IQR outlier analysis. |
  | [`online_retail_power_bi_analysis.sql`](online_retail_power_bi_analysis.sql) | Supplies read-only combined and summary queries for Power BI reporting. |
  
## Cleaning and data-quality behavior
  
  The cleaning scripts do not update or delete source rows. They create or replace regular views that:
  
  - Trim surrounding whitespace from text fields and convert empty text to `NULL`.
- Parse `InvoiceDate` from the source format `m/d/yyyy h:mm` using `STR_TO_DATE`.
- Convert numeric 2010–2011 customer IDs to an unsigned integer; non-numeric IDs become `NULL` and are separately reported.
- Retain missing customer IDs, returns, cancellations, zero/negative values, and numeric extremes for review.

The baseline profile reports missing/blank fields, negative and zero quantities/prices, cancellation invoice lines, and selected whitespace issues. Date validation returns source date strings that could not be parsed. Duplicate results are candidates only: identical invoice lines can be legitimate repeated records.

The outlier scripts calculate nearest-rank quartiles and 1.5 × IQR fences for positive quantities and prices on non-cancellation invoices. They flag candidate records for review; they do not remove or cap them. Returns, cancellations, zeroes, and negative values remain available in the cleaned views but are excluded from the positive-sales threshold population.

## Power BI analysis query catalog

`online_retail_power_bi_analysis.sql` contains these read-only queries:
  
  1. **Combined transaction-line fact** — appends the two cleaned views and adds `SourcePeriod`, line net amount, return/credit flag, and cancellation flag.
2. **Executive overview by period** — invoice lines, distinct invoices, identified customers, customer-ID coverage count, gross sales, net sales, positive units, and return/cancellation lines.
3. **Monthly sales trend** — gross sales, net sales, and distinct invoices by month and source period.
4. **Product sales by period** — units, sales, and invoices by stock code and description.
5. **Country sales by period** — sales, invoices, and identified customers by country.
6. **Customer performance** — sales and activity for rows with identified customer IDs.
7. **Returns and cancellations by period** — negative quantity/price lines, cancellation lines, return/credit amount, and net amount.
8. **Invoice value distribution** — invoice-level sales values, line counts, and distinct products.
9. **Data-quality summary** — row counts, missing customer IDs, blank descriptions, negative values, and cancellation lines.
10. **Outlier review dataset** — positive-sale rows flagged by period-specific IQR fences.
11. **Customer coverage** — identified customer lines and coverage percentage by period.
12. **Repeat customer activity** — repeat-customer counts and sales contribution for identified customers.
13. **Basket patterns** — line count, distinct products, units, and gross sales per invoice.
14. **Monthly return/cancellation trend** — negative quantity/price lines, cancellation lines, return/credit amount, and net amount by month.
15. **Exact duplicate summary** — duplicate groups and excess copies by period.

## Metric definitions

The Power BI SQL comments use the following conventions:
  
  - **Gross sales:** `Quantity * Price` for positive quantity and price, excluding invoices beginning with `C`.
- **Net sales:** signed `Quantity * Price` across all rows, retaining returns and credits.
- **Positive units:** positive quantities on non-cancellation invoices.
- **Cancellation:** an invoice identifier beginning with `C`.
- **Possible return/credit:** a negative quantity and/or a cancellation invoice, depending on the specific query. The dataset does not provide a dedicated return-status field.

Confirm the currency and metric definitions with the business before publishing. The invoice count in the executive query is a distinct invoice count and includes cancellation invoice identifiers; filter cancellations in Power BI if the report needs sales invoices only.

## Suggested Power BI pages

### Executive overview

- Cards for gross sales, net sales, positive units, and distinct invoice count.
- Line chart with `MonthStart` on the X-axis, gross/net sales as values, and `SourcePeriod` as legend.
- Period slicer using `SourcePeriod`.

### Products and countries

- Clustered bar chart for top products: product description or stock code against gross sales; use a visual-level Top N filter.
- Clustered bar chart for country comparison: country against gross sales with `SourcePeriod` as legend.
- Period and optional country slicers.

### Returns and data quality

- Line chart for monthly negative-quantity lines and cancellation invoice lines.
- Bar chart for missing-field counts or quality flags by period.
- Cards for duplicate groups and excess duplicate rows from query 15.
- Detail tables for duplicate candidates and outlier records; use a drill-through page for large detail sets.

