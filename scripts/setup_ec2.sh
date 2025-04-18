#!/bin/bash

# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install Python and pip
sudo apt-get install -y python3 python3-pip python3-venv

# Install MySQL client
sudo apt-get install -y mysql-client

# Create virtual environment
python3 -m venv /home/ubuntu/venv
source /home/ubuntu/venv/bin/activate

# Install required packages
pip install -r /home/ubuntu/ec2_processor/requirements.txt

# Create systemd service for the processor
sudo tee /etc/systemd/system/finance-processor.service << EOF
[Unit]
Description=Finance Data Processor
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/ec2_processor
Environment="PATH=/home/ubuntu/venv/bin"
ExecStart=/home/ubuntu/venv/bin/python processor.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for Streamlit
sudo tee /etc/systemd/system/finance-dashboard.service << EOF
[Unit]
Description=Finance Dashboard
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/streamlit_app
Environment="PATH=/home/ubuntu/venv/bin"
ExecStart=/home/ubuntu/venv/bin/streamlit run app.py --server.port=8501 --server.address=0.0.0.0
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable services
sudo systemctl daemon-reload
sudo systemctl enable finance-processor
sudo systemctl enable finance-dashboard

# Start services
sudo systemctl start finance-processor
sudo systemctl start finance-dashboard

# Configure firewall
sudo ufw allow 8501/tcp
sudo ufw enable

# Create log directory
sudo mkdir -p /var/log/finance
sudo chown ubuntu:ubuntu /var/log/finance

# Create .env file
sudo tee /home/ubuntu/.env << EOF
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=us-east-2
S3_BUCKET_RAW=ds4300-ananya-raw-transactions
S3_BUCKET_CLEANED=ds4300-ananya-cleaned-transactions
RDS_HOST=your_rds_host
RDS_USER=your_rds_user
RDS_PASSWORD=your_rds_password
RDS_DB=finance_tracker
EOF

# Set permissions
sudo chown ubuntu:ubuntu /home/ubuntu/.env
sudo chmod 600 /home/ubuntu/.env 