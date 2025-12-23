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
S3_BUCKET="${S3_BUCKET_FLINK_LIBS}"
S3_LIBS_PREFIX="flink_libs"

# Generate unique names
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BASE_JAR_NAME="iceberg-connector-${TIMESTAMP}"
FULL_JAR_NAME="${BASE_JAR_NAME}.jar"

echo "======================================"
echo "📚 Building Custom Libraries JAR"
echo "======================================"
echo "JAR Name: $FULL_JAR_NAME"
echo "S3 Location: s3://$S3_BUCKET/$S3_LIBS_PREFIX/"
echo "======================================"

# Step 1: Build the libraries JAR
echo ""
echo "📦 Step 1: Building libraries JAR..."
cd flink_libs

mvn clean package -DskipTests -Djar.name="$BASE_JAR_NAME"

if [ ! -f "target/$FULL_JAR_NAME" ]; then
    echo "❌ Error: JAR file not found at target/$FULL_JAR_NAME"
    exit 1
fi

JAR_SIZE=$(du -h "target/$FULL_JAR_NAME" | cut -f1)
echo "✅ Libraries JAR built successfully: $FULL_JAR_NAME ($JAR_SIZE)"

# Step 2: Upload to S3
echo ""
echo "☁️  Step 2: Uploading libraries JAR to S3..."
aws s3 cp "target/$FULL_JAR_NAME" "s3://$S3_BUCKET/$S3_LIBS_PREFIX/$FULL_JAR_NAME"

if [ $? -ne 0 ]; then
    echo "❌ Failed to upload JAR to S3"
    cd ..
    exit 1
fi
echo "✅ JAR uploaded successfully"


# Save the JAR name to a file for the app deployment script to use
echo "$S3_LIBS_PREFIX/$FULL_JAR_NAME" > target/last_libs_jar

cd ..
echo ""
echo "======================================"
echo "✨ Libraries JAR Deployment Complete!"
echo "======================================"
echo "JAR: s3://$S3_BUCKET/$S3_LIBS_PREFIX/$FULL_JAR_NAME"
echo "======================================"
echo ""
echo "💡 Next step: Run ./build-and-deploy-app.sh to deploy your application"
echo "======================================"