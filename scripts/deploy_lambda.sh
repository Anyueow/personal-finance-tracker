#!/bin/bash

# Set variables
PROCESS_FUNC="ds4300-func"
CATEGORIZE_FUNC="ds4300-categorize-func"
RAW_BUCKET="ds4300-ananya-raw-transactions"
CLEANED_BUCKET="ds4300-ananya-cleaned-transactions"
REGION="us-east-2"

echo "Creating deployment packages..."

# Create deployment package for process_transactions
cd lambda_functions
zip -r ../process_deployment.zip process_transactions.py
cd ..

# Create deployment package for categorize_transactions
cd lambda_functions
zip -r ../categorize_deployment.zip categorize_transactions.py
cd ..

echo "Deploying process_transactions Lambda..."

# Deploy process_transactions Lambda
aws lambda update-function-code \
    --function-name $PROCESS_FUNC \
    --zip-file fileb://process_deployment.zip \
    --region $REGION

# Update process_transactions environment variables
aws lambda update-function-configuration \
    --function-name $PROCESS_FUNC \
    --environment "Variables={RAW_BUCKET=$RAW_BUCKET,CLEANED_BUCKET=$CLEANED_BUCKET}" \
    --region $REGION

echo "Creating/Updating categorize_transactions Lambda..."

# Check if categorize function exists, if not create it
if ! aws lambda get-function --function-name $CATEGORIZE_FUNC --region $REGION 2>/dev/null; then
    echo "Creating new categorize_transactions Lambda function..."
    aws lambda create-function \
        --function-name $CATEGORIZE_FUNC \
        --runtime python3.9 \
        --handler categorize_transactions.lambda_handler \
        --role arn:aws:iam::340752810672:role/ds4300-role \
        --zip-file fileb://categorize_deployment.zip \
        --environment "Variables={CLEANED_BUCKET=$CLEANED_BUCKET}" \
        --region $REGION
else
    echo "Updating existing categorize_transactions Lambda function..."
    aws lambda update-function-code \
        --function-name $CATEGORIZE_FUNC \
        --zip-file fileb://categorize_deployment.zip \
        --region $REGION

    aws lambda update-function-configuration \
        --function-name $CATEGORIZE_FUNC \
        --environment "Variables={CLEANED_BUCKET=$CLEANED_BUCKET}" \
        --region $REGION
fi

echo "Setting up S3 triggers..."

# Add S3 trigger for process_transactions (raw bucket -> process Lambda)
aws s3api put-bucket-notification-configuration \
    --bucket $RAW_BUCKET \
    --notification-configuration "{
        \"LambdaFunctionConfigurations\": [{
            \"LambdaFunctionArn\": \"arn:aws:lambda:$REGION:340752810672:function:$PROCESS_FUNC\",
            \"Events\": [\"s3:ObjectCreated:*\"],
            \"Filter\": {
                \"Key\": {
                    \"FilterRules\": [{
                        \"Name\": \"suffix\",
                        \"Value\": \".csv\"
                    }]
                }
            }
        }]
    }"

# Add S3 trigger for categorize_transactions (cleaned bucket -> categorize Lambda)
aws s3api put-bucket-notification-configuration \
    --bucket $CLEANED_BUCKET \
    --notification-configuration "{
        \"LambdaFunctionConfigurations\": [{
            \"LambdaFunctionArn\": \"arn:aws:lambda:$REGION:340752810672:function:$CATEGORIZE_FUNC\",
            \"Events\": [\"s3:ObjectCreated:*\"],
            \"Filter\": {
                \"Key\": {
                    \"FilterRules\": [{
                        \"Name\": \"prefix\",
                        \"Value\": \"cleaned_\"
                    }, {
                        \"Name\": \"suffix\",
                        \"Value\": \".csv\"
                    }]
                }
            }
        }]
    }"

echo "Adding Lambda permissions for S3 triggers..."

# Add permissions for S3 to invoke Lambdas
aws lambda add-permission \
    --function-name $PROCESS_FUNC \
    --statement-id S3InvokeFunction \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn "arn:aws:s3:::$RAW_BUCKET" \
    --region $REGION

aws lambda add-permission \
    --function-name $CATEGORIZE_FUNC \
    --statement-id S3InvokeFunction \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn "arn:aws:s3:::$CLEANED_BUCKET" \
    --region $REGION

# Clean up
rm process_deployment.zip categorize_deployment.zip

echo "Deployment completed successfully!" 