SET SESSION lakekeeper.compression_codec = 'ZSTD';
CREATE TABLE IF NOT EXISTS lakekeeper.bronze.lineitem
WITH (
    format = 'PARQUET',
    partitioning = ARRAY['year(shipdate)']
)
AS
SELECT *
FROM tpch.sf10.lineitem;
