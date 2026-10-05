ALTER TABLE lakekeeper.silver.order_lines
ADD COLUMN order_year INTEGER;

UPDATE lakekeeper.silver.order_lines
SET order_year = year(orderdate);
