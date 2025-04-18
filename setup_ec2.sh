#!/bin/bash

# Create app directory
mkdir -p ~/streamlit_app

# Copy application files
scp -i ds4300-ananya-key.pem -r streamlit_app/* ubuntu@18.116.20.166:~/streamlit_app/
scp -i ds4300-ananya-key.pem requirements.txt ubuntu@18.116.20.166:~/
scp -i ds4300-ananya-key.pem .env ubuntu@18.116.20.166:~/

# SSH into the instance and set up the environment
ssh -i ds4300-ananya-key.pem ubuntu@18.116.20.166 << 'EOF'
    # Update package list
    sudo apt-get update

    # Install Python and pip if not already installed
    sudo apt-get install -y python3-pip python3-venv

    # Create and activate virtual environment
    python3 -m venv venv
    source venv/bin/activate

    # Install requirements
    pip install -r requirements.txt

    # Run Streamlit app in the background
    cd ~/streamlit_app
    nohup streamlit run app.py --server.port 8501 --server.address 0.0.0.0 > streamlit.log 2>&1 &

    echo "Streamlit app is starting..."
    echo "You can access it at http://18.116.20.166:8501"
EOF 