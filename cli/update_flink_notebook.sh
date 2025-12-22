#!/bin/bash

# load env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found."
    exit 1
fi

# get app version
CURRENT_VERSION=$(aws kinesisanalyticsv2 describe-application \
    --application-name $FLINK_NOTEBOOK \
    --query 'ApplicationDetail.ApplicationVersionId' \
    --output text)
echo "Updating $FLINK_NOTEBOOK (Current Version: $CURRENT_VERSION)..."

# 3. update config
aws kinesisanalyticsv2 update-application \
    --no-cli-pager \
    --application-name $FLINK_NOTEBOOK \
    --current-application-version-id $CURRENT_VERSION \
    --application-configuration-update "{
        \"ZeppelinApplicationConfigurationUpdate\": {
            \"CustomArtifactsConfigurationUpdate\": [
                {
                    \"ArtifactType\": \"DEPENDENCY_JAR\",
                    \"S3ContentLocation\": {
                        \"BucketARN\": \"arn:aws:s3:::$S3_BUCKET_FLINK_LIBS\",
                        \"FileKey\": \"flink_libs/flink-sql-connector-kafka-1.15.4.jar\"
                    }
                },
                {
                    \"ArtifactType\": \"DEPENDENCY_JAR\",
                    \"S3ContentLocation\": {
                        \"BucketARN\": \"arn:aws:s3:::$S3_BUCKET_FLINK_LIBS\",
                        \"FileKey\": \"flink_libs/iceberg-flink-runtime-1.15-1.4.3.jar\"
                    }
                },
                {
                    \"ArtifactType\": \"DEPENDENCY_JAR\",
                    \"S3ContentLocation\": {
                        \"BucketARN\": \"arn:aws:s3:::$S3_BUCKET_FLINK_LIBS\",
                        \"FileKey\": \"flink_libs/iceberg-aws-bundle-1.4.3.jar\"
                    }
                },
                {
                    \"ArtifactType\": \"DEPENDENCY_JAR\",
                    \"S3ContentLocation\": {
                        \"BucketARN\": \"arn:aws:s3:::$S3_BUCKET_FLINK_LIBS\",
                        \"FileKey\": \"flink_libs/hadoop-common-2.8.5.jar\"
                    }
                },
                {
                    \"ArtifactType\": \"DEPENDENCY_JAR\",
                    \"S3ContentLocation\": {
                        \"BucketARN\": \"arn:aws:s3:::$S3_BUCKET_FLINK_LIBS\",
                        \"FileKey\": \"flink_libs/hadoop-hdfs-client-2.8.5.jar\"
                    }
                },
                {
                    \"ArtifactType\": \"DEPENDENCY_JAR\",
                    \"S3ContentLocation\": {
                        \"BucketARN\": \"arn:aws:s3:::$S3_BUCKET_FLINK_LIBS\",
                        \"FileKey\": \"flink_libs/hadoop-hdfs-2.8.5.jar\"
                    }
                }
            ]
        }
    }"
