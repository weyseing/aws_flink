CREATE CATALOG catalog_glue WITH (
    'type'='iceberg',
    'catalog-impl'='org.apache.iceberg.aws.glue.GlueCatalog',
    'warehouse'='s3://kafka-iceberg-107698500998/',
    'io-impl'='org.apache.iceberg.aws.s3.S3FileIO'
);