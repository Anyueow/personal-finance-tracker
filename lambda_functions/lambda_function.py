import json
import boto3
import pandas as pd
from datetime import datetime
import logging
import io
import os

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS client
s3 = boto3.client('s3')

def process_transactions(df):
    """Process and clean transaction data"""
    try:
        # Convert dates to datetime
        df['date'] = pd.to_datetime(df['date'])
        
        # Remove rows with missing values
        df = df.dropna()
        
        # Convert amounts to float and ensure positive
        df['amount'] = df['amount'].astype(float).abs()
        
        # Standardize category names to lowercase
        if 'category' in df.columns:
            df['category'] = df['category'].str.lower()
        
        # Add processing timestamp
        df['processed_at'] = datetime.now()
        
        return df
    except Exception as e:
        logger.error(f"Error processing transactions: {str(e)}")
        raise

def lambda_handler(event, context):
    """Process files from raw bucket to cleaned bucket"""
    try:
        # Get bucket names from environment variables
        raw_bucket = os.environ['RAW_BUCKET']
        cleaned_bucket = os.environ['CLEANED_BUCKET']
        
        # Process each file that triggered the Lambda
        for record in event['Records']:
            # Get file details
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            # Skip if not from raw bucket
            if bucket != raw_bucket:
                continue
            
            # Download file from raw bucket
            response = s3.get_object(Bucket=bucket, Key=key)
            file_content = response['Body'].read()
            
            # Convert to DataFrame
            if key.lower().endswith('.csv'):
                df = pd.read_csv(io.BytesIO(file_content))
            else:
                raise ValueError(f"Unsupported file type: {key}")
            
            # Process and clean the data
            df = process_transactions(df)
            
            # Convert to CSV
            output = io.StringIO()
            df.to_csv(output, index=False)
            
            # Upload to cleaned bucket
            cleaned_key = f"cleaned_{os.path.basename(key)}"
            s3.put_object(
                Bucket=cleaned_bucket,
                Key=cleaned_key,
                Body=output.getvalue()
            )
            
            logger.info(f"Successfully processed {key} to {cleaned_key}")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Processing completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error in Lambda handler: {str(e)}")
        raise 