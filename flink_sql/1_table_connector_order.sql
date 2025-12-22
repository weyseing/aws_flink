USE CATALOG default_catalog;
USE default_database;

CREATE TABLE table_connector_order (
  id INT,
  product STRING,
  amount INT,
  buyer_id INT,
  create_date STRING,
  update_date STRING,
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'upsert-kafka',
  'topic' = 'stream_order_intake',
  'key.format' = 'json',
  'value.format' = 'json',
  'properties.bootstrap.servers' = 'broker:29092',
  'properties.group.id' = 'kafka_source_order'
);