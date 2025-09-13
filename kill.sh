#!/bin/bash
# This script stops both the ExtJS frontend and Julia servers.

echo "Attempting to stop the ExtJS frontend server..."
# Find and kill the Python HTTP server process
EXTJS_PID=$(pgrep -f "python3 -m http.server --directory extjs_app 8000")
if [ -z "$EXTJS_PID" ]; then
    echo "ExtJS server does not appear to be running."
else
    kill $EXTJS_PID
    echo "ExtJS server (PID: $EXTJS_PID) stopped."
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
