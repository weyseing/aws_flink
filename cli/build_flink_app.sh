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
S3_LIBS_PREFIX="flink_libs"

# Generate unique names
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BASE_JAR_NAME="flink-kafka-iceberg-app-${TIMESTAMP}"
FULL_JAR_NAME="${BASE_JAR_NAME}.jar"

echo "======================================"
echo "🚀 AWS Flink Application Deployment"
echo "======================================"
echo "Application: $FLINK_APP_NAME"
echo "App JAR: $FULL_JAR_NAME"
echo "S3 Location: s3://$S3_BUCKET/$S3_APP_PREFIX/"
echo "======================================"

# Check if libraries JAR was deployed
cd flink_libs
if [ -f ./target/last_libs_jar ]; then
    LIBS_JAR=$(cat ./target/last_libs_jar)
    echo "📚 Using libraries JAR: $LIBS_JAR"
else
    echo "⚠️  Warning: No libraries JAR found. Did you run build-and-deploy-libs.sh?"
    echo ""
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    LIBS_JAR=""
fi
cd ..

# Function to get previous JAR
get_current_jar() {
    aws kinesisanalyticsv2 describe-application \
        --application-name "$FLINK_APP_NAME" \
        --query 'ApplicationDetail.ApplicationConfigurationDescription.ApplicationCodeConfigurationDescription.CodeContentDescription.S3ApplicationCodeLocationDescription.FileKey' \
        --output text 2>/dev/null || echo ""
}

# Step 1: Build the application JAR
echo ""
echo "📦 Step 1: Building application JAR..."
cd flink_app

mvn clean package -DskipTests -Djar.name="$BASE_JAR_NAME"

if [ ! -f "target/$FULL_JAR_NAME" ]; then
    echo "❌ Error: JAR file not found at target/$FULL_JAR_NAME"
    exit 1
fi

JAR_SIZE=$(du -h "target/$FULL_JAR_NAME" | cut -f1)
echo "✅ Application JAR built successfully: $FULL_JAR_NAME ($JAR_SIZE)"

# Step 2: Upload to S3
echo ""
echo "☁️  Step 2: Uploading application JAR to S3..."
aws s3 cp "target/$FULL_JAR_NAME" "s3://$S3_BUCKET/$S3_APP_PREFIX/$FULL_JAR_NAME"

if [ $? -ne 0 ]; then
    echo "❌ Failed to upload JAR to S3"
    cd ..
    exit 1
fi
echo "✅ Application JAR uploaded successfully"

cd ..

# Step 3: Get current application version
echo ""
echo "🔍 Step 3: Getting current application version..."
CURRENT_VERSION=$(aws kinesisanalyticsv2 describe-application \
    --application-name "$FLINK_APP_NAME" \
    --query 'ApplicationDetail.ApplicationVersionId' \
    --output text 2>/dev/null)

if [ -z "$CURRENT_VERSION" ] || [ "$CURRENT_VERSION" == "None" ]; then
    echo "❌ Error: Could not retrieve application version. Does the application exist?"
    echo "Application name: $FLINK_APP_NAME"
    exit 1
fi
echo "✅ Current version: $CURRENT_VERSION"

# Save current JAR for rollback
PREVIOUS_JAR=$(get_current_jar)
echo "📝 Current JAR: $PREVIOUS_JAR"

# Step 4: Check and stop if running
echo ""
echo "⏸️  Step 4: Checking application status..."
APP_STATUS=$(aws kinesisanalyticsv2 describe-application \
    --application-name "$FLINK_APP_NAME" \
    --query 'ApplicationDetail.ApplicationStatus' \
    --output text)

echo "Current status: $APP_STATUS"

if [ "$APP_STATUS" == "RUNNING" ]; then
    echo "⚠️  Stopping application..."
    aws kinesisanalyticsv2 stop-application \
        --application-name "$FLINK_APP_NAME" \
        > /dev/null 2>&1
    
    echo "⏳ Waiting for application to stop (max 5 minutes)..."
    for i in {1..30}; do
        CURRENT_STATUS=$(aws kinesisanalyticsv2 describe-application \
            --application-name "$FLINK_APP_NAME" \
            --query 'ApplicationDetail.ApplicationStatus' \
            --output text)
        
        if [ "$CURRENT_STATUS" == "READY" ]; then
            echo "✅ Application stopped"
            break
        fi
        
        if [ $i -eq 30 ]; then
            echo "❌ Timeout waiting for application to stop"
            exit 1
        fi
        
        echo "   Status: $CURRENT_STATUS (${i}/30)"
        sleep 10
    done
    
    # Get updated version after stop
    CURRENT_VERSION=$(aws kinesisanalyticsv2 describe-application \
        --application-name "$FLINK_APP_NAME" \
        --query 'ApplicationDetail.ApplicationVersionId' \
        --output text)
    
    echo "📝 Version after stop: $CURRENT_VERSION"
fi

# Step 5: Update application code and dependencies
echo ""
echo "🔄 Step 5: Updating application..."

# Build the update configuration with CORRECT parameter names
if [ -n "$LIBS_JAR" ]; then
    echo "   ✅ Updating application code AND custom libraries"
    echo "   📦 App JAR: s3://$S3_BUCKET/$S3_APP_PREFIX/$FULL_JAR_NAME"
    echo "   📚 Libs JAR: s3://$S3_BUCKET/$LIBS_JAR"
    
    # Create temp file for the JSON config
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
        },
        {
          "PropertyGroupId": "pipeline.config",
          "PropertyMap": {
            "pipeline.classpaths": "s3://${S3_BUCKET}/${LIBS_JAR}"
          }
        }
      ]
    }
  }
}
EOF
    
else
    echo "   ⚠️  Updating application code only (no custom libraries)"
    
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
fi

# Debug: Show what we're sending
echo ""
echo "🔍 Debug: Update configuration:"
cat "$UPDATE_CONFIG_FILE" | jq '.'
echo ""

echo "🔧 Calling AWS API..."
echo "   Application: $FLINK_APP_NAME"
echo "   Version: $CURRENT_VERSION"

# Use --cli-input-json
aws kinesisanalyticsv2 update-application \
    --cli-input-json "file://$UPDATE_CONFIG_FILE" \
    > /tmp/update_output.json 2>&1

UPDATE_EXIT_CODE=$?

# Clean up temp file
rm -f "$UPDATE_CONFIG_FILE"

if [ $UPDATE_EXIT_CODE -ne 0 ]; then
    echo "❌ Failed to update application"
    echo "Exit code: $UPDATE_EXIT_CODE"
    echo "Output:"
    cat /tmp/update_output.json
    rm -f /tmp/update_output.json
    exit 1
fi

echo "✅ Application updated successfully"
echo ""
echo "📊 API Response:"
cat /tmp/update_output.json | jq '.'
rm -f /tmp/update_output.json

# Verify the update
echo ""
echo "🔍 Verifying update..."
sleep 3

NEW_VERSION=$(aws kinesisanalyticsv2 describe-application \
    --application-name "$FLINK_APP_NAME" \
    --query 'ApplicationDetail.ApplicationVersionId' \
    --output text)

NEW_JAR=$(aws kinesisanalyticsv2 describe-application \
    --application-name "$FLINK_APP_NAME" \
    --query 'ApplicationDetail.ApplicationConfigurationDescription.ApplicationCodeConfigurationDescription.CodeContentDescription.S3ApplicationCodeLocationDescription.FileKey' \
    --output text)

CLASSPATH=$(aws kinesisanalyticsv2 describe-application \
    --application-name "$FLINK_APP_NAME" \
    --query 'ApplicationDetail.ApplicationConfigurationDescription.EnvironmentPropertyDescriptions.PropertyGroupDescriptions[?PropertyGroupId==`pipeline.config`].PropertyMap' \
    --output json)

echo "   Previous version: $CURRENT_VERSION"
echo "   New version: $NEW_VERSION"
echo "   New JAR: $NEW_JAR"
echo "   Classpath config:"
echo "$CLASSPATH" | jq '.'

if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
    echo "✅ Version changed successfully"
else
    echo "⚠️  Warning: Version didn't change!"
fi

# Step 6: Start application
echo ""
echo "▶️  Step 6: Starting application..."
read -p "Start the application now? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    START_OUTPUT=$(aws kinesisanalyticsv2 start-application \
        --application-name "$FLINK_APP_NAME" \
        --run-configuration '{}' 2>&1)
    
    if [ $? -eq 0 ]; then
        echo "✅ Application start initiated"
        
        echo ""
        echo "⏳ Monitoring application startup..."
        for i in {1..30}; do
            CURRENT_STATUS=$(aws kinesisanalyticsv2 describe-application \
                --application-name "$FLINK_APP_NAME" \
                --query 'ApplicationDetail.ApplicationStatus' \
                --output text)
            
            if [ "$CURRENT_STATUS" == "RUNNING" ]; then
                echo "✅ Application is RUNNING"
                break
            elif [ "$CURRENT_STATUS" == "READY" ] || [ "$CURRENT_STATUS" == "STARTING" ]; then
                echo "   Status: $CURRENT_STATUS (${i}/30)"
                sleep 10
            else
                echo "⚠️  Unexpected status: $CURRENT_STATUS"
                break
            fi
        done
        
        REGION=$(aws configure get region)
        echo ""
        echo "📊 Monitor your application:"
        echo "   Console: https://console.aws.amazon.com/flink/home?region=${REGION}#/applications/$FLINK_APP_NAME"
        echo "   Logs: aws logs tail /aws/kinesis-analytics/$FLINK_APP_NAME --follow"
    else
        echo "❌ Failed to start application"
        echo "$START_OUTPUT"
        exit 1
    fi
else
    echo "⏸️  Application not started"
fi

echo ""
echo "======================================"
echo "✨ Deployment Complete!"
echo "======================================"
echo "App JAR: s3://$S3_BUCKET/$S3_APP_PREFIX/$FULL_JAR_NAME"
if [ -n "$LIBS_JAR" ]; then
    echo "Libs JAR: s3://$S3_BUCKET/$LIBS_JAR"
    echo "Classpath: Configured"
fi
echo "Application: $FLINK_APP_NAME"
FINAL_STATUS=$(aws kinesisanalyticsv2 describe-application --application-name "$FLINK_APP_NAME" --query 'ApplicationDetail.ApplicationStatus' --output text)
echo "Status: $FINAL_STATUS"
echo "Version: $NEW_VERSION"
echo "======================================"