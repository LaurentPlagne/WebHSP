#!/bin/bash
# This script stops both the Vue.js frontend and Julia servers.

echo "Attempting to stop the Vue.js frontend server..."
# Find and kill the Julia process for the Vue frontend
VUE_SERVER_PID=$(pgrep -f "vues_app/app.jl")
if [ -z "$VUE_SERVER_PID" ]; then
    echo "Vue.js frontend server does not appear to be running."
else
    kill $VUE_SERVER_PID
    echo "Vue.js frontend server (PID: $VUE_SERVER_PID) stopped."
fi

echo "Attempting to stop the Julia simulation server..."
# Find and kill the Julia process for the simulation backend
JULIA_PID=$(pgrep -f "julia_server/server.jl")
if [ -z "$JULIA_PID" ]; then
    echo "Julia simulation server does not appear to be running."
else
    kill $JULIA_PID
    echo "Julia simulation server (PID: $JULIA_PID) stopped."
fi

echo "Cleanup complete."
