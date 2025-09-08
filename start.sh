#!/bin/bash
# This script starts both the Python backend and the Julia backend servers.

echo "Starting Julia server in the background..."
# Run the Julia server, activating the project environment in its directory
# Redirect stdout and stderr to a log file.
julia --project=julia_server julia_server/server.jl > julia_server.log 2>&1 &
JULIA_PID=$!
echo "Julia server started with PID: $JULIA_PID"

echo "Starting Python server in the background..."
# Run the Python Flask server
# Redirect stdout and stderr to a log file.
python backend/app.py > backend.log 2>&1 &
PYTHON_PID=$!
echo "Python server started with PID: $PYTHON_PID"

echo "Both servers are running. You can view logs in backend.log and julia_server.log"
echo "Access the web application at http://127.0.0.1:5000"
