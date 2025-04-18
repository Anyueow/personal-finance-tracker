import json
import boto3
import pandas as pd
import logging
import io
import os

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS client
s3 = boto3.client('s3')

def categorize_transactions(df):
    """Categorize transactions based on description"""
    try:
        # Convert description to lowercase for better matching
        df['description'] = df['description'].str.lower()
        
        # Define category rules
        category_rules = {
            'groceries': ['trader', 'whole foods', 'safeway', 'grocery'],
            'dining': ['restaurant', 'cafe', 'coffee', 'doordash', 'uber eats'],
            'transport': ['uber', 'lyft', 'transit', 'parking', 'gas'],
            'utilities': ['electricity', 'water', 'gas', 'internet', 'phone'],
            'entertainment': ['netflix', 'spotify', 'amazon prime', 'movie'],
            'shopping': ['amazon', 'target', 'walmart', 'costco'],
            'health': ['pharmacy', 'doctor', 'medical', 'fitness'],
            'travel': ['hotel', 'airline', 'airbnb', 'flight'],
        }
        
        # Function to find category based on description
        def find_category(description):
            for category, keywords in category_rules.items():
                if any(keyword in description for keyword in keywords):
                    return category
            return 'other'
        
        # Apply categorization
        df['auto_category'] = df['description'].apply(find_category)
        
        return df
    except Exception as e:
        logger.error(f"Error categorizing transactions: {str(e)}")
        raise

def lambda_handler(event, context):
    """Categorize transactions from cleaned bucket"""
    try:
        # Get bucket names from environment variables
        cleaned_bucket = os.environ['CLEANED_BUCKET']
        
        # Process each file that triggered the Lambda
        for record in event['Records']:
            # Get file details
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            # Skip if not from cleaned bucket
            if bucket != cleaned_bucket:
                continue
            
            # Download file from cleaned bucket
            response = s3.get_object(Bucket=bucket, Key=key)
            file_content = response['Body'].read()
            
            # Convert to DataFrame
            if key.lower().endswith('.csv'):
                df = pd.read_csv(io.BytesIO(file_content))
            else:
                raise ValueError(f"Unsupported file type: {key}")
            
            # Categorize the transactions
            df = categorize_transactions(df)
            
            # Convert to CSV
            output = io.StringIO()
            df.to_csv(output, index=False)
            
            # Upload back to cleaned bucket with categorized_ prefix
            categorized_key = f"categorized_{os.path.basename(key)}"
            s3.put_object(
                Bucket=cleaned_bucket,
                Key=categorized_key,
                Body=output.getvalue()
            )
            
            logger.info(f"Successfully categorized {key} to {categorized_key}")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Categorization completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error in Lambda handler: {str(e)}")
        raise 