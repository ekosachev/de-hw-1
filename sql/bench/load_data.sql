SET SESSION lakekeeper.compression_codec = 'ZSTD';
CREATE TABLE IF NOT EXISTS lakekeeper.bench.customer_zstd
WITH (
    format = 'PARQUET'
)
AS
SELECT *
FROM tpch.sf10.customer;

CREATE TABLE IF NOT EXISTS lakekeeper.bench.orders_zstd
WITH (
    format = 'PARQUET'
)
AS
SELECT *
FROM tpch.sf10.orders;

CREATE TABLE IF NOT EXISTS lakekeeper.bench.lineitem_zstd
WITH (
    format = 'PARQUET',
    partitioning = ARRAY['year(shipdate)']
)
AS
SELECT *
FROM tpch.sf10.lineitem;

SET SESSION lakekeeper.compression_codec = 'SNAPPY';
CREATE TABLE IF NOT EXISTS lakekeeper.bench.customer_snappy
WITH (
    format = 'PARQUET'
)
AS
SELECT *
FROM tpch.sf10.customer;

CREATE TABLE IF NOT EXISTS lakekeeper.bench.orders_snappy
WITH (
    format = 'PARQUET'
)
AS
SELECT *
FROM tpch.sf10.orders;

CREATE TABLE IF NOT EXISTS lakekeeper.bench.lineitem_snappy
WITH (
    format = 'PARQUET',
    partitioning = ARRAY['year(shipdate)']
)
AS
SELECT *
FROM tpch.sf10.lineitem;

SET SESSION lakekeeper.compression_codec = 'GZIP';
CREATE TABLE IF NOT EXISTS lakekeeper.bench.customer_gzip
WITH (
    format = 'PARQUET'
)
AS
SELECT *
FROM tpch.sf10.customer;

CREATE TABLE IF NOT EXISTS lakekeeper.bench.orders_gzip
WITH (
    format = 'PARQUET'
)
AS
SELECT *
FROM tpch.sf10.orders;

CREATE TABLE IF NOT EXISTS lakekeeper.bench.lineitem_gzip
WITH (
    format = 'PARQUET',
    partitioning = ARRAY['year(shipdate)']
)
AS
SELECT *
FROM tpch.sf10.lineitem;
