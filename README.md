# Setup Guide

- **Create S3 bucket**

![image](./assets/1.PNG)

- **Create Glue database**

![image](./assets/2.PNG)

- **Create IAM role** with permission
    - `AmazonS3FullAccess`
    - `AWSGlueConsoleFullAccess`
    - `CloudWatchLogsFullAccess`
    - `AmazonKinesisAnalyticsFullAccess`

![image](./assets/3.PNG)

- **Install Maven**
```bash
apt install maven
```

# Flink Ap
- **Create Flink App**

![image](./assets/6.PNG)
![image](./assets/7.PNG)

- **Build Flink Libs**
```bash
./cli/build_flink_libs.sh
```

- **Build Flink App**
    - Create Flink App code in `flink_app\`
```bash
./cli/build_flink_app.sh
```

- **Check log**
    - **CloudWatch LogGroup:** `/aws/kinesis-analytics/<FLINK-APP-NAME>`
