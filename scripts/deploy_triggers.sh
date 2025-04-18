#!/bin/bash

# Load environment variables
source ../.env

# Set AWS region
export AWS_REGION=us-east-2

# Set variables
REGION="us-east-2"
ACCOUNT_ID="340752810672"
RAW_BUCKET="ds4300-ananya-raw-transactions"
CLEANED_BUCKET="ds4300-ananya-cleaned-transactions"
PROCESS_FUNC="ds4300-func"
CATEGORIZE_FUNC="ds4300-categorize-func"

echo "Adding Lambda permissions for S3 triggers..."

# Add permissions for S3 to invoke process Lambda
aws lambda add-permission \
    --function-name $PROCESS_FUNC \
    --statement-id S3InvokeProcessFunction \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn "arn:aws:s3:::$RAW_BUCKET" \
    --region $REGION || true  # Continue if permission already exists

# Add permissions for S3 to invoke categorize Lambda
aws lambda add-permission \
    --function-name $CATEGORIZE_FUNC \
    --statement-id S3InvokeCategorizeFunction \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn "arn:aws:s3:::$CLEANED_BUCKET" \
    --region $REGION || true  # Continue if permission already exists

echo "Configuring S3 event triggers..."

# Configure raw bucket notifications
echo "Configuring raw bucket notifications..."
aws s3api put-bucket-notification-configuration \
    --region $AWS_REGION \
    --bucket $RAW_BUCKET \
    --notification-configuration file://raw-notif.json

# Configure cleaned bucket notifications
echo "Configuring cleaned bucket notifications..."
aws s3api put-bucket-notification-configuration \
    --region $AWS_REGION \
    --bucket $CLEANED_BUCKET \
    --notification-configuration file://cleaned-notif.json

echo "Verifying configurations..."

# Verify raw bucket configuration
echo "Raw bucket ($RAW_BUCKET) notification configuration:"
aws s3api get-bucket-notification-configuration \
    --region $AWS_REGION \
    --bucket $RAW_BUCKET

echo -e "\nCleaned bucket ($CLEANED_BUCKET) notification configuration:"
aws s3api get-bucket-notification-configuration \
    --region $AWS_REGION \
    --bucket $CLEANED_BUCKET

echo "Setup completed!" 