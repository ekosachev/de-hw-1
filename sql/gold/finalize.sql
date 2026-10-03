SET SESSION lakekeeper.compression_codec = 'ZSTD';
CREATE TABLE IF NOT EXISTS lakekeeper.gold.most_profitable_orders
WITH (
    format = 'PARQUET'
)
AS
SELECT
    ol.orderkey,
    ol.orderdate,
    ol.shippriority,
    ol.shipdate,
    SUM(ol.extendedprice * (1 - ol.discount)) as revenue
FROM lakekeeper.silver.order_lines AS ol
GROUP BY ol.orderkey, ol.orderdate, ol.shipdate, ol.shippriority
ORDER BY revenue DESC
LIMIT 10;
