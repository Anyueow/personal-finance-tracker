#!/bin/bash

# Create deployment package
cd lambda_functions
zip -r ../deployment.zip .

# Deploy to Lambda
aws lambda update-function-code \
    --function-name ds4300-func \
    --zip-file fileb://../deployment.zip \
    --region us-east-2

# Update environment variables
aws lambda update-function-configuration \
    --function-name ds4300-func \
    --environment "Variables={RAW_BUCKET=ds4300-ananya-raw-transactions,CLEANED_BUCKET=ds4300-ananya-cleaned-transactions}" \
    --region us-east-2

# Clean up
rm ../deployment.zip 