SET SESSION lakekeeper.compression_codec = 'ZSTD';
CREATE TABLE IF NOT EXISTS lakekeeper.bench.order_lines_zstd
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
FROM lakekeeper.bench.customer_zstd AS c
JOIN lakekeeper.bench.orders_zstd AS o
    ON c.custkey = o.custkey
JOIN lakekeeper.bench.lineitem_zstd AS l
    ON o.orderkey = l.orderkey
WHERE c.mktsegment = 'BUILDING'
    AND l.shipdate > DATE '1995-03-15'
    AND o.orderdate <= DATE '1995-03-15';
