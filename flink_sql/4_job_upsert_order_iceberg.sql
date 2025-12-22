USE CATALOG catalog_glue;
USE iceberg_db1;

SET 'pipeline.name' = 'job_upsert_order_iceberg';
SET 'execution.checkpointing.interval' = '10s';
SET 'execution.checkpointing.mode' = 'EXACTLY_ONCE';

INSERT INTO catalog_glue.iceberg_db1.table_order_iceberg
SELECT * FROM default_catalog.default_database.table_connector_order;