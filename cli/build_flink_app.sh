#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found."
    exit 1
fi

# Configuration
FLINK_APP_NAME="poc_flinkapp"
S3_BUCKET="${S3_BUCKET_FLINK_LIBS}"
S3_APP_PREFIX="flink_app"

# Generate unique names
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BASE_JAR_NAME="flink-kafka-iceberg-app-${TIMESTAMP}"
FULL_JAR_NAME="${BASE_JAR_NAME}.jar"

echo "======================================"
echo "🚀 AWS Flink Application Deployment (Fat JAR Mode)"
echo "======================================"
echo "Application: $FLINK_APP_NAME"
echo "App JAR: $FULL_JAR_NAME"
echo "S3 Location: s3://$S3_BUCKET/$S3_APP_PREFIX/"
echo "======================================"

# Step 1: Build the application Fat JAR
echo ""
echo "📦 Step 1: Building application Fat JAR..."
cd flink_app

# Ensure we use the pom.xml with the Shade plugin and ServicesResourceTransformer
mvn clean package -DskipTests -Djar.name="$BASE_JAR_NAME"

if [ ! -f "target/$FULL_JAR_NAME" ]; then
    echo "❌ Error: JAR file not found at target/$FULL_JAR_NAME"
    exit 1
fi

JAR_SIZE=$(du -h "target/$FULL_JAR_NAME" | cut -f1)
echo "✅ Fat JAR built successfully: $FULL_JAR_NAME ($JAR_SIZE)"

# Step 2: Upload to S3
echo ""
echo "☁️  Step 2: Uploading Fat JAR to S3..."
aws s3 cp "target/$FULL_JAR_NAME" "s3://$S3_BUCKET/$S3_APP_PREFIX/$FULL_JAR_NAME"

cd ..

# Step 3: Get current application version
echo ""
echo "🔍 Step 3: Getting current application version..."
CURRENT_VERSION=$(aws kinesisanalyticsv2 describe-application \
    --application-name "$FLINK_APP_NAME" \
    --query 'ApplicationDetail.ApplicationVersionId' \
    --output text 2>/dev/null)

if [ -z "$CURRENT_VERSION" ] || [ "$CURRENT_VERSION" == "None" ]; then
    echo "❌ Error: Could not retrieve application version."
    exit 1
fi

# Step 4: Check and stop if running
echo ""
echo "⏸️  Step 4: Checking application status..."
APP_STATUS=$(aws kinesisanalyticsv2 describe-application \
    --application-name "$FLINK_APP_NAME" \
    --query 'ApplicationDetail.ApplicationStatus' \
    --output text)

if [ "$APP_STATUS" == "RUNNING" ]; then
    echo "⚠️  Stopping application..."
    aws kinesisanalyticsv2 stop-application --application-name "$FLINK_APP_NAME"
    
    echo "⏳ Waiting for application to stop..."
    while true; do
        STATUS=$(aws kinesisanalyticsv2 describe-application --application-name "$FLINK_APP_NAME" --query 'ApplicationDetail.ApplicationStatus' --output text)
        if [ "$STATUS" == "READY" ]; then break; fi
        sleep 10
    done
    
    # Refresh version after stop
    CURRENT_VERSION=$(aws kinesisanalyticsv2 describe-application --application-name "$FLINK_APP_NAME" --query 'ApplicationDetail.ApplicationVersionId' --output text)
fi

# Step 5: Update application (Consolidated Config)
echo ""
echo "🔄 Step 5: Updating application code and properties..."

UPDATE_CONFIG_FILE=$(mktemp)
cat > "$UPDATE_CONFIG_FILE" <<EOF
{
  "ApplicationName": "${FLINK_APP_NAME}",
  "CurrentApplicationVersionId": ${CURRENT_VERSION},
  "ApplicationConfigurationUpdate": {
    "ApplicationCodeConfigurationUpdate": {
      "CodeContentUpdate": {
        "S3ContentLocationUpdate": {
          "BucketARNUpdate": "arn:aws:s3:::${S3_BUCKET}",
          "FileKeyUpdate": "${S3_APP_PREFIX}/${FULL_JAR_NAME}"
        }
      }
    },
    "FlinkApplicationConfigurationUpdate": {
      "ParallelismConfigurationUpdate": {
        "ConfigurationTypeUpdate": "CUSTOM",
        "ParallelismUpdate": 2,
        "ParallelismPerKPUUpdate": 1,
        "AutoScalingEnabledUpdate": true
      }
    },
    "EnvironmentPropertyUpdates": {
      "PropertyGroups": [
        {
          "PropertyGroupId": "FlinkApplicationProperties",
          "PropertyMap": {
            "kafka.bootstrap.servers": "${KAFKA_BOOTSTRAP_SERVERS}",
            "kafka.topic": "${KAFKA_TOPIC}",
            "kafka.group.id": "${KAFKA_GROUP_ID:-flink-iceberg-consumer}",
            "iceberg.warehouse": "${ICEBERG_WAREHOUSE}",
            "iceberg.database": "${ICEBERG_DATABASE:-default}",
            "iceberg.table": "${ICEBERG_TABLE:-kafka_events}"
          }
        }
      ]
    }
  }
}
EOF

aws kinesisanalyticsv2 update-application --cli-input-json "file://$UPDATE_CONFIG_FILE" > /dev/null
rm -f "$UPDATE_CONFIG_FILE"
echo "✅ Application updated successfully"

# Step 6: Start application
echo ""
echo "▶️  Step 6: Starting application..."

echo "🚀 Sending start command..."
aws kinesisanalyticsv2 start-application --application-name "$FLINK_APP_NAME" --run-configuration '{}'
echo "⏳ Monitoring startup (this usually takes 1-3 minutes)..."

# Define timeout (30 checks * 10 seconds = 5 minutes)
MAX_RETRIES=30
COUNT=0

while [ $COUNT -lt $MAX_RETRIES ]; do
    # Fetch current status
    CURRENT_STATUS=$(aws kinesisanalyticsv2 describe-application \
        --application-name "$FLINK_APP_NAME" \
        --query 'ApplicationDetail.ApplicationStatus' \
        --output text)
    
    echo "   Current Status: $CURRENT_STATUS"
    
    if [ "$CURRENT_STATUS" == "RUNNING" ]; then
        echo "✅ Application is now RUNNING!"
        break
    elif [ "$CURRENT_STATUS" == "READY" ] && [ $COUNT -gt 1 ]; then
        # If it goes back to READY after we started it, it likely crashed
        echo "❌ Error: Application failed to start and returned to READY state."
        echo "💡 Check CloudWatch Logs for 'RestHandlerException' or 'ValidationException'."
        exit 1
    elif [ "$CURRENT_STATUS" == "UPDATING" ] || [ "$CURRENT_STATUS" == "STARTING" ]; then
        # Still in progress
        sleep 10
    else
        # Other statuses like DELETING or AUTOSCALING
        sleep 10
    fi
    
    COUNT=$((COUNT+1))
done

if [ $COUNT -eq $MAX_RETRIES ]; then
    echo "⌛ Timeout: Application is taking longer than 5 minutes to start."
    echo "Please check the AWS Console for progress."
fi
