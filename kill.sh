#!/bin/bash
# This script stops both the Streamlit and Julia servers.

echo "Attempting to stop the Streamlit server..."
# Find and kill the Streamlit process
STREAMLIT_PID=$(pgrep -f "streamlit run streamlit_app/app.py")
if [ -z "$STREAMLIT_PID" ]; then
    echo "Streamlit server does not appear to be running."
else
    kill $STREAMLIT_PID
    echo "Streamlit server (PID: $STREAMLIT_PID) stopped."
fi

echo "Attempting to stop the Julia server..."
# Find and kill the Julia process
JULIA_PID=$(pgrep -f "julia_server/server.jl")
if [ -z "$JULIA_PID" ]; then
    echo "Julia server does not appear to be running."
else
    kill $JULIA_PID
    echo "Julia server (PID: $JULIA_PID) stopped."
fi

echo "Cleanup complete."
