import streamlit as st
import boto3
import mysql.connector
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime
import os
from dotenv import load_dotenv
import logging
import json
import time
from botocore.exceptions import ClientError
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
import numpy as np

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Initialize session state for processing status
if 'processing_status' not in st.session_state:
    st.session_state.processing_status = None
if 'processing_log' not in st.session_state:
    st.session_state.processing_log = []

# Initialize AWS client
s3 = boto3.client('s3',
    aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
    aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY'),
    region_name=os.getenv('AWS_REGION')
)

def log_processing_step(message, status="info"):
    """Add a processing step to the log with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = {"timestamp": timestamp, "message": message, "status": status}
    st.session_state.processing_log.append(log_entry)
    logger.info(f"{timestamp} - {message}")

def display_processing_log():
    """Display the processing log in the UI"""
    if st.session_state.processing_log:
        st.sidebar.subheader("Processing Log")
        for entry in st.session_state.processing_log:
            if entry["status"] == "error":
                st.sidebar.error(f"{entry['timestamp']}: {entry['message']}")
            elif entry["status"] == "success":
                st.sidebar.success(f"{entry['timestamp']}: {entry['message']}")
            else:
                st.sidebar.info(f"{entry['timestamp']}: {entry['message']}")

def check_file_processing_status(file_name):
    """Check if file has been processed in cleaned bucket"""
    try:
        cleaned_key = f"processed/{file_name}"
        s3.head_object(
            Bucket=os.getenv('S3_BUCKET_CLEANED'),
            Key=cleaned_key
        )
        return True
    except ClientError:
        return False

def get_latest_uploaded_filename():
    """Get the filename of the latest uploaded file from processing log"""
    for entry in reversed(st.session_state.processing_log):
        if "Starting upload of file:" in entry["message"]:
            start_idx = entry["message"].find("Starting upload of file: ") + len("Starting upload of file: ")
            end_idx = entry["message"].find(" (Size:")
            if start_idx > -1 and end_idx > -1:
                return entry["message"][start_idx:end_idx]
    return None

def monitor_processing():
    """Monitor the processing status of uploaded files"""
    if st.session_state.processing_status == "monitoring":
        filename = get_latest_uploaded_filename()
        if not filename:
            log_processing_step("Could not determine the uploaded file name", "error")
            st.session_state.processing_status = "error"
            return False
            
        log_processing_step(f"Monitoring processing for file: {filename}")
        
        with st.spinner('Monitoring processing status...'):
            for i in range(30):  # Check for 30 seconds
                try:
                    if check_file_processing_status(filename):
                        log_processing_step(f"File processed successfully: {filename}", "success")
                        st.session_state.processing_status = "completed"
                        return True
                    time.sleep(1)
                except Exception as e:
                    log_processing_step(f"Error checking processing status: {str(e)}", "error")
                    st.session_state.processing_status = "error"
                    return False
            
            log_processing_step(f"Processing timeout for file: {filename}", "error")
            st.session_state.processing_status = "timeout"
            return False

def upload_to_s3(file, goal, annual_income):
    """Upload file to S3 and store goal with enhanced logging"""
    try:
        # Reset processing status at start of new upload
        st.session_state.processing_status = None
        
        # Log file details
        file_size = file.size
        file_type = file.type
        log_processing_step(f"Starting upload of file: {file.name} (Size: {file_size} bytes, Type: {file_type})")
        
        # Upload file to raw transactions bucket
        raw_key = f"raw/{file.name}"
        log_processing_step(f"Uploading to raw bucket: {os.getenv('S3_BUCKET_RAW')}/{raw_key}")
        
        s3.upload_fileobj(
            file,
            os.getenv('S3_BUCKET_RAW'),
            raw_key
        )
        log_processing_step(f"File uploaded successfully to raw bucket", "success")
        
        # Store goal and income
        goal_key = f"goals/{file.name}.goal"
        goal_metadata = {
            "goal": goal,
            "annual_income": annual_income,
            "timestamp": datetime.now().isoformat(),
            "file_name": file.name
        }
        
        log_processing_step(f"Storing goal metadata")
        s3.put_object(
            Bucket=os.getenv('S3_BUCKET_RAW'),
            Key=goal_key,
            Body=json.dumps(goal_metadata).encode()
        )
        log_processing_step(f"Goal metadata stored successfully", "success")
        
        # Start monitoring processing status
        st.session_state.processing_status = "monitoring"
        log_processing_step(f"Starting processing monitoring for {file.name}")
        
        return True
        
    except Exception as e:
        error_msg = f"Error during upload: {str(e)}"
        log_processing_step(error_msg, "error")
        st.sidebar.error(error_msg)
        return False

def get_db_connection():
    try:
        return mysql.connector.connect(
            host=os.getenv('RDS_HOST'),
            user=os.getenv('RDS_USER'),
            password=os.getenv('RDS_PASSWORD'),
            database=os.getenv('RDS_DB')
        )
    except mysql.connector.Error as err:
        st.error(f"Database connection failed: {err}")
        return None

def execute_query(query, fetch=True):
    """Execute a query and return results"""
    conn = None
    try:
        conn = get_db_connection()
        if conn:
            df = pd.read_sql(query, conn) if fetch else pd.DataFrame()
            return df
    except Exception as e:
        st.error(f"Query execution failed: {e}")
        return pd.DataFrame()
    finally:
        if conn:
            conn.close()

def get_monthly_spending():
    """Get monthly spending data from RDS"""
    query = """
        SELECT 
            DATE_FORMAT(month, '%Y-%m') as month,
            category,
            total_amount,
            income_bracket
        FROM monthly_spend_summary
        ORDER BY month, category
    """
    df = execute_query(query)
    if not df.empty:
        df['month'] = pd.to_datetime(df['month'])
    return df

def get_benchmark_data():
    """Get benchmark data from RDS"""
    query = """
        SELECT 
            income_bracket,
            category,
            average_percentage
        FROM benchmark_by_income
    """
    return execute_query(query)

def get_savings_recommendations():
    """Get latest savings recommendations from RDS"""
    query = """
        SELECT 
            current_savings_rate,
            benchmark_savings_rate,
            suggested_areas,
            created_at
        FROM savings_recommendations
        ORDER BY created_at DESC
        LIMIT 1
    """
    return execute_query(query)

def display_spending_trends(df):
    """Display spending trends over time"""
    if df.empty:
        st.warning("No spending data available.")
        return

    # Monthly total spending trend
    monthly_total = df.groupby('month')['total_amount'].sum().reset_index()
    fig = px.line(monthly_total, 
                  x='month', 
                  y='total_amount',
                  title='Monthly Total Spending Trend')
    fig.update_xaxes(title='Month')
    fig.update_yaxes(title='Total Amount ($)')
    st.plotly_chart(fig, use_container_width=True)
    
    # Category-wise spending
    category_spending = df.groupby('category')['total_amount'].sum().reset_index()
    fig = px.pie(category_spending, 
                 values='total_amount', 
                 names='category',
                 title='Spending by Category')
    st.plotly_chart(fig, use_container_width=True)

def display_benchmark_comparison(spending_df, benchmark_df):
    """Display comparison with benchmark data"""
    if spending_df.empty or benchmark_df.empty:
        st.warning("No benchmark data available.")
        return

    try:
        # Get user's income bracket
        income_bracket = spending_df['income_bracket'].iloc[0]
        
        # Calculate user's percentages
        total_spending = spending_df['total_amount'].sum()
        user_percentages = (spending_df.groupby('category')['total_amount'].sum() / total_spending * 100).reset_index()
        
        # Get benchmark percentages for user's income bracket
        benchmark_percentages = benchmark_df[benchmark_df['income_bracket'] == income_bracket]
        
        # Create comparison chart
        fig = go.Figure(data=[
            go.Bar(name='Your Spending', x=user_percentages['category'], y=user_percentages['total_amount']),
            go.Bar(name='Benchmark', x=benchmark_percentages['category'], y=benchmark_percentages['average_percentage'])
        ])
        
        fig.update_layout(
            title='Your Spending vs Benchmark',
            barmode='group',
            yaxis_title='Percentage of Total Spending',
            showlegend=True
        )
        
        st.plotly_chart(fig, use_container_width=True)
    except Exception as e:
        st.error(f"Error displaying benchmark comparison: {e}")

def display_savings_recommendations(recommendations_df):
    """Display savings recommendations"""
    if recommendations_df.empty:
        st.info("No savings recommendations available yet.")
        return

    try:
        latest_rec = recommendations_df.iloc[0]
        
        # Display savings rate comparison
        col1, col2 = st.columns(2)
        with col1:
            st.metric(
                "Your Current Savings Rate",
                f"{latest_rec['current_savings_rate']:.1f}%",
                f"{latest_rec['current_savings_rate'] - latest_rec['benchmark_savings_rate']:.1f}% vs benchmark"
            )
        with col2:
            st.metric(
                "Recommended Savings Rate",
                f"{latest_rec['benchmark_savings_rate']:.1f}%",
                "Based on your income bracket"
            )
        
        # Display suggested areas for savings
        st.subheader("Suggested Areas for Savings")
        suggested_areas = json.loads(latest_rec['suggested_areas'])
        
        for area in suggested_areas:
            with st.expander(f"{area['category']} - Potential Savings: ${area['potential_savings']:.2f}"):
                st.write(f"Current Spending: ${area['current_spending']:.2f}")
                st.write(f"Benchmark Spending: ${area['benchmark_spending']:.2f}")
                st.write(f"Percentage Above Benchmark: {area['percentage_above_benchmark']:.1f}%")
                
    except Exception as e:
        st.error(f"Error displaying savings recommendations: {e}")

def main():
    st.set_page_config(
        page_title="Personal Finance Tracker",
        layout="wide",
        initial_sidebar_state="expanded"
    )
    
    # Sidebar - File Upload and Processing Status
    with st.sidebar:
        st.title("Upload Transactions")
        
        # File upload
        uploaded_file = st.file_uploader(
            "Choose your bank statement",
            type=['pdf', 'csv'],
            help="Upload your bank statement in PDF or CSV format"
        )
        
        # Annual income input
        annual_income = st.number_input(
            "Annual Income ($)",
            min_value=0,
            value=50000,
            step=1000,
            help="Enter your annual income for personalized recommendations"
        )
        
        # Goal input
        financial_goal = st.text_area(
            "Financial Goal",
            placeholder="e.g., Save $5000 for emergency fund",
            help="Enter your financial goal for personalized recommendations"
        )
        
        if uploaded_file and financial_goal:
            if st.button("Upload and Analyze"):
                if upload_to_s3(uploaded_file, financial_goal, annual_income):
                    st.success("Upload initiated successfully!")
        
        # Display processing log
        display_processing_log()
        
        if st.session_state.processing_status == "monitoring":
            monitor_processing()
    
    # Main content - Dashboard
    st.title("Personal Finance Dashboard")
    
    try:
        # Load data
        spending_data = get_monthly_spending()
        benchmark_data = get_benchmark_data()
        savings_recommendations = get_savings_recommendations()
        
        if not spending_data.empty:
            # Display summary metrics
            col1, col2, col3 = st.columns(3)
            
            total_spending = spending_data['total_amount'].sum()
            avg_monthly = spending_data.groupby('month')['total_amount'].sum().mean()
            num_months = spending_data['month'].nunique()
            
            col1.metric("Total Spending", f"${total_spending:,.2f}")
            col2.metric("Average Monthly", f"${avg_monthly:,.2f}")
            col3.metric("Months Analyzed", num_months)
            
            # Display savings recommendations
            st.header("Savings Recommendations")
            display_savings_recommendations(savings_recommendations)
            
            # Display spending trends
            st.header("Spending Analysis")
            display_spending_trends(spending_data)
            
            # Display benchmark comparison
            st.header("Benchmark Comparison")
            display_benchmark_comparison(spending_data, benchmark_data)
            
        else:
            st.info("No transaction data available yet. Please upload your bank statement.")
            
    except Exception as e:
        error_msg = f"Error loading dashboard: {str(e)}"
        log_processing_step(error_msg, "error")
        st.error(error_msg)

if __name__ == "__main__":
    main() 