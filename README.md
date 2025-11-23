# Setup Guide
- S3 Bucket
- Glue Database
- IAM role (s3, glue, cloudwatch logs)
- apt install maven
- dummy app
    - dummyapp.java
    - pom.xml
    - mvn clean package -q
jars
    - pom.xml
    - rm -rf jars && mvn dependency:copy-dependencies -DoutputDirectory=jars
- upload jars file to s3
- AWS Flink > configure > runtime properties
    - pipeline.classpaths
    - s3://poc-iceberg-107698500998/jars/flink-connector-kafka-3.3.0-1.20.jar;s3://poc-iceberg-107698500998/jars/flink-sql-connector-kafka-3.3.0-1.20.jar;s3://poc-iceberg-107698500998/jars/flink-json-1.20.0.jar;s3://poc-iceberg-107698500998/jars/iceberg-flink-runtime-1.20-1.8.0.jar;s3://poc-iceberg-107698500998/jars/iceberg-aws-bundle-1.8.0.jar
- run flink app
- flink dashboard