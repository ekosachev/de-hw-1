SET SESSION lakekeeper.compression_codec = 'ZSTD';
CREATE TABLE IF NOT EXISTS lakekeeper.bronze.customer
WITH (
    format = 'PARQUET'
)
AS
SELECT *
FROM tpch.sf10.customer;
