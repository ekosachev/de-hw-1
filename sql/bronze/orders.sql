SET SESSION lakekeeper.compression_codec = 'ZSTD';
CREATE TABLE IF NOT EXISTS lakekeeper.bronze.orders
WITH (
    format = 'PARQUET'
)
AS
SELECT *
FROM tpch.sf10.orders
