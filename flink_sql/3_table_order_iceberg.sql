USE CATALOG catalog_glue;
USE iceberg_db1;

CREATE TABLE IF NOT EXISTS table_order_iceberg (
  `id` INT,
  `product` STRING,
  `amount` INT,
  `buyer_id` INT,
  `create_date` STRING,
  `update_date` STRING,
  PRIMARY KEY (`id`) NOT ENFORCED
) WITH (
  'format-version' = '2',
  'write.upsert.enabled' = 'true'
);
