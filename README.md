# Personal Finance Tracker

A real-time personal finance tracking system with ML-powered insights.

## Architecture

The system consists of:
- S3 buckets for raw and cleaned data storage
- Lambda function for initial data processing
- EC2 instance running ML processor and Streamlit dashboard
- RDS database for storing processed data and insights

## Setup Instructions

### 1. RDS Setup

1. Create a MySQL RDS instance in AWS
2. Connect to the RDS instance:
   ```bash
   mysql -h <RDS_HOST> -u <RDS_USER> -p
   ```
3. Run the schema script:
   ```bash
   mysql -h <RDS_HOST> -u <RDS_USER> -p < sql/schema.sql
   ```

### 2. Lambda Deployment

1. Ensure AWS CLI is configured with appropriate credentials
2. Run the deployment script:
   ```bash
   chmod +x scripts/deploy_lambda.sh
   ./scripts/deploy_lambda.sh
   ```

### 3. EC2 Setup

1. Launch an EC2 instance (Ubuntu 20.04 recommended)
2. Copy the project files to the instance:
   ```bash
   scp -r . ubuntu@<EC2_IP>:/home/ubuntu/
   ```
3. SSH into the instance:
   ```bash
   ssh ubuntu@<EC2_IP>
   ```
4. Run the setup script:
   ```bash
   chmod +x scripts/setup_ec2.sh
   ./scripts/setup_ec2.sh
   ```
5. Edit the .env file with your credentials:
   ```bash
   nano /home/ubuntu/.env
   ```

### 4. Environment Variables

Create a `.env` file with the following variables:
```
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=us-east-2
S3_BUCKET_RAW=ds4300-ananya-raw-transactions
S3_BUCKET_CLEANED=ds4300-ananya-cleaned-transactions
RDS_HOST=your_rds_host
RDS_USER=your_rds_user
RDS_PASSWORD=your_rds_password
RDS_DB=finance_tracker
```

### 5. Accessing the Dashboard

1. The Streamlit dashboard will be available at:
   ```
   http://<EC2_IP>:8501
   ```
2. The ML processor runs as a background service

## Monitoring

- Check processor logs:
  ```bash
  journalctl -u finance-processor -f
  ```
- Check dashboard logs:
  ```bash
  journalctl -u finance-dashboard -f
  ```

## Troubleshooting

1. If the dashboard is not accessible:
   - Check EC2 security groups to ensure port 8501 is open
   - Verify the dashboard service is running:
     ```bash
     sudo systemctl status finance-dashboard
     ```

2. If data is not being processed:
   - Check Lambda function logs in CloudWatch
   - Verify S3 bucket permissions
   - Check processor logs on EC2

3. If database connection fails:
   - Verify RDS security group allows EC2 access
   - Check database credentials in .env file

## Features

- Upload bank statements (PDF/CSV)
- Automatic transaction categorization
- Monthly spending analysis
- Peer benchmarking by income bracket
- Financial goal tracking
- Interactive visualizations

## Security

- All sensitive data is encrypted at rest
- IAM roles with least privilege principle
- Environment variables for credentials
- Secure database connections
- S3 bucket policies for restricted access
- RDS security groups configured

## Project Structure
```
.
├── README.md
├── setup_and_validate.sh    # Main setup script
├── .env                     # Environment variables
├── requirements.txt         # Python dependencies
├── lambda_functions/        # AWS Lambda functions
│   ├── process_transactions.py
│   └── categorize_transactions.py
├── streamlit_app/          # Frontend application
└── sql/                    # Database schemas
```

## License

MIT License