#!/bin/bash

# load env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
    echo "✅ .env file loaded."
else
    echo "❌ Error: .env file not found."
    exit 1
fi

# build jars file
cd flink_libs
rm -rf jars
mvn dependency:copy-dependencies -DoutputDirectory=jars

# upload to s3
aws s3 cp jars/ s3://$S3_BUCKET_FLINK_LIBS/flink_libs/ \
    --recursive \
    --exclude "*" \
    --include "flink-sql-connector-kafka-1.15.4.jar" \
    --include "iceberg-flink-runtime-1.15-1.4.3.jar" \
    --include "iceberg-aws-bundle-1.4.3.jar" \
    --include "hadoop-common-2.8.5.jar" \
    --include "hadoop-hdfs-client-2.8.5.jar" \
    --include "hadoop-hdfs-2.8.5.jar"

cd ..