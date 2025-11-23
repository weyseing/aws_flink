# Setup Guide
- **Create S3 bucket**

![image](./assets/1.PNG)

- **Create Glue database**

![image](./assets/2.PNG)

- **Create IAM role** with permission
    - `AmazonS3FullAccess`
    - `AWSGlueConsoleFullAccess`
    - `CloudWatchLogsFullAccess`

![image](./assets/2.PNG)

- **Install Maven**
```bash
apt install maven
```

- **Flink jars file**
    - Download via Maven
    ```bash
    cd flink_libs
    rm -rf jars && mvn dependency:copy-dependencies -DoutputDirectory=jars
    ```
    - Upload to S3

    ![image](./assets/4.PNG)

- **Flink App**
    - Create app script in `flink_app_example\src\main\java\com\example\DummyApp.java`
    - Build app
    ```bash
    cd flink_app_example
    mvn clean package -q
    ```
    - Upload to S3


# WIP
- AWS Flink > configure > runtime properties
    - pipeline.classpaths
    - s3://poc-iceberg-107698500998/jars/flink-connector-kafka-3.3.0-1.20.jar;s3://poc-iceberg-107698500998/jars/flink-sql-connector-kafka-3.3.0-1.20.jar;s3://poc-iceberg-107698500998/jars/flink-json-1.20.0.jar;s3://poc-iceberg-107698500998/jars/iceberg-flink-runtime-1.20-1.8.0.jar;s3://poc-iceberg-107698500998/jars/iceberg-aws-bundle-1.8.0.jar
- run flink app
- flink dashboard