#!/usr/bin/env bash
set -e

# Configuration variables
AWS_PROFILE=ds4300-ananya
BUCKET_RAW="ds4300-ananya-raw-transactions"
BUCKET_CLEAN="ds4300-ananya-cleaned-transactions"
LAMBDA_FUNCTION="ds4300-func"

# RDS and EC2 variables
RDS_HOST="ds4300-aces-rds.ctka88maap7u.us-east-2.rds.amazonaws.com"
RDS_PORT="3306"
RDS_DB_IDENTIFIER="ds4300-aces-rds"
RDS_DB="finance_db"
RDS_USER="admin"
RDS_PASSWORD="admin606*"
EC2_HOST="ec2-3-145-98-200.us-east-2.compute.amazonaws.com"
EC2_USER="ubuntu"
SSH_KEY="/Users/anyueow/Desktop/DS4300/personal finance tracker/ds4300-ananya-key.pem"

# Set AWS profile
export AWS_PROFILE=$AWS_PROFILE

echo "Starting setup and validation process..."

# 1. Create S3 buckets if they don't exist
echo "Creating S3 buckets..."
aws s3api create-bucket --bucket $BUCKET_RAW --region us-east-2 --create-bucket-configuration LocationConstraint=us-east-2 || true
aws s3api create-bucket --bucket $BUCKET_CLEAN --region us-east-2 --create-bucket-configuration LocationConstraint=us-east-2 || true

# 2. Configure S3 Event Notifications
echo "Configuring S3 event notifications..."

# Get Lambda function ARN
LAMBDA_ARN=$(aws lambda get-function --function-name $LAMBDA_FUNCTION --query 'Configuration.FunctionArn' --output text)

# Configure raw bucket notification
aws s3api put-bucket-notification-configuration \
    --bucket $BUCKET_RAW \
    --notification-configuration '{
        "LambdaFunctionConfigurations": [
            {
                "LambdaFunctionArn": "'$LAMBDA_ARN'",
                "Events": ["s3:ObjectCreated:*"]
            }
        ]
    }'

# 3. Configure Lambda Environment Variables
echo "Configuring Lambda environment variables..."

# Update Lambda function environment variables
aws lambda update-function-configuration \
    --function-name $LAMBDA_FUNCTION \
    --environment "Variables={
        RAW_BUCKET=$BUCKET_RAW,
        CLEANED_BUCKET=$BUCKET_CLEAN,
        RDS_HOST=$RDS_HOST,
        RDS_PORT=$RDS_PORT,
        RDS_DB=$RDS_DB,
        RDS_USER=$RDS_USER,
        RDS_PASSWORD=$RDS_PASSWORD
    }"

# 4. Validate Lambda
echo "Validating Lambda function..."

# Create and upload test file
echo "Creating and uploading test file..."
printf "date,desc,amount\n2025-04-01,TEST,10.00" > test.csv
aws s3 cp test.csv s3://$BUCKET_RAW/raw/test.csv

# Wait for processing
echo "Waiting for Lambda processing..."
sleep 5

# Check cleaned bucket
echo "Checking cleaned bucket contents..."
aws s3 ls s3://$BUCKET_CLEAN/cleaned/

# Check Lambda logs
echo "Checking Lambda logs..."
aws logs tail /aws/lambda/$LAMBDA_FUNCTION --max-items 10

# Verify RDS data
echo "Verifying RDS data..."
mysql -h $RDS_HOST -P $RDS_PORT -u $RDS_USER -p$RDS_PASSWORD $RDS_DB -e "SELECT COUNT(*) FROM transactions_enriched;"

# 5. Deploy Streamlit App
echo "Deploying Streamlit app..."

# SSH into EC2 and deploy app
ssh -i $SSH_KEY $EC2_USER@$EC2_HOST << 'EOF'
cd ~
if [ -d "streamlit_app" ]; then
    cd streamlit_app
    git pull
else
    git clone <your-repo-url> streamlit_app
    cd streamlit_app
fi

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export RAW_BUCKET=$BUCKET_RAW
export CLEANED_BUCKET=$BUCKET_CLEAN
export RDS_HOST=$RDS_HOST
export RDS_PORT=$RDS_PORT
export RDS_DB=$RDS_DB
export RDS_USER=$RDS_USER
export RDS_PASSWORD=$RDS_PASSWORD

# Start Streamlit app
nohup streamlit run app.py --server.port 80 &
EOF

# Verify Streamlit app
echo "Verifying Streamlit app..."
curl -I http://$EC2_HOST

# 6. Set up CloudWatch Alarms
echo "Setting up CloudWatch alarms..."

# Create alarm for Lambda errors
aws cloudwatch put-metric-alarm \
    --alarm-name "${LAMBDA_FUNCTION}-Errors" \
    --alarm-description "Alarm when Lambda errors exceed threshold" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions <your-sns-topic-arn> \
    --dimensions "Name=FunctionName,Value=$LAMBDA_FUNCTION"

echo "Setup and validation complete!"

# GitHub Actions instructions
echo "
To automate this process with GitHub Actions, add the following to your workflow file:

name: Deploy and Validate
on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: \${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: \${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-2
      - name: Run setup and validation
        run: |
          chmod +x setup_and_validate.sh
          ./setup_and_validate.sh
" 