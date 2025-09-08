#!/bin/bash
# This script stops both the Python and Julia backend servers.

echo "Attempting to stop the Julia server..."
# Use pkill to find and kill the process running the Julia server script.
# The '-f' flag matches against the full command line.
pkill -f "julia --project=julia_server julia_server/server.jl"
if [ $? -eq 0 ]; then
    echo "Julia server stopped."
else
    echo "Julia server not found or already stopped."
fi

echo "Attempting to stop the Python server..."
# Use pkill to find and kill the process running the Python server script.
pkill -f "python backend/app.py"
if [ $? -eq 0 ]; then
    echo "Python server stopped."
else
    echo "Python server not found or already stopped."
fi

echo "Cleanup complete."
