#!/bin/bash

# Set variables
STACK_NAME="ds4300-s3-triggers"
TEMPLATE_FILE="cloudformation/s3-triggers.yaml"
REGION="us-east-2"

# Create/Update CloudFormation stack
aws cloudformation deploy \
    --template-file $TEMPLATE_FILE \
    --stack-name $STACK_NAME \
    --region $REGION \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides \
        RawBucketName=ds4300-ananya-raw-transactions \
        CleanedBucketName=ds4300-ananya-cleaned-transactions \
        ProcessFunctionName=ds4300-func \
        CategorizeFunctionName=ds4300-categorize-func

# Check stack status
aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].StackStatus' \
    --output text 