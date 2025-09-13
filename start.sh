#!/bin/bash
# This script starts the Streamlit frontend and the Julia backend server.

echo "Installing Python dependencies for the Streamlit app..."
pip install -r streamlit_app/requirements.txt

echo "Instantiating Julia environment..."
# Ensure that the 'julia' executable is in your system's PATH.
julia --project=julia_server -e 'import Pkg; Pkg.instantiate()'

echo "Starting Julia server in the background..."
# Run the Julia server, activating the project environment in its directory
# Redirect stdout and stderr to a log file.
julia --project=julia_server julia_server/server.jl > julia_server.log 2>&1 &
JULIA_PID=$!
echo "Julia server started with PID: $JULIA_PID"

echo "Starting Streamlit server in the background..."
# Run the Streamlit server
# Redirect stdout and stderr to a log file.
streamlit run streamlit_app/app.py --server.headless true > streamlit.log 2>&1 &
STREAMLIT_PID=$!
echo "Streamlit server started with PID: $STREAMLIT_PID"

echo "Both servers are running. You can view logs in streamlit.log and julia_server.log"
echo "Access the web application at the URL provided by Streamlit (usually http://localhost:8501)"
