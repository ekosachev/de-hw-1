SET SESSION lakekeeper.compression_codec = 'ZSTD';
CREATE TABLE IF NOT EXISTS lakekeeper.silver.order_lines
WITH (
    format = 'PARQUET'
)
AS
SELECT
    o.orderkey,
    o.orderdate,
    o.shippriority,
    l.extendedprice,
    l.discount,
    l.shipdate
FROM lakekeeper.bronze.customer AS c
JOIN lakekeeper.bronze.orders AS o
    ON c.custkey = o.custkey
JOIN lakekeeper.bronze.lineitem AS l
    ON o.orderkey = l.orderkey
WHERE c.mktsegment = 'BUILDING'
    AND l.shipdate > DATE '1995-03-15'
    AND o.orderdate <= DATE '1995-03-15';
