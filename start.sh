#!/bin/bash
# This script starts the ExtJS frontend and the Julia backend server.

echo "Installing Julia dependencies..."
julia --project=julia_server -e 'using Pkg; Pkg.instantiate()'

echo "Starting Julia server in the background..."
# Run the Julia server, activating the project environment in its directory
# Redirect stdout and stderr to a log file.
julia --project=julia_server julia_server/server.jl > julia_server.log 2>&1 &
JULIA_PID=$!
echo "Julia server started with PID: $JULIA_PID"

echo "Waiting for Julia server to be ready on port 8081..."
while ! nc -z 127.0.0.1 8081; do
  # Check if the Julia process is still alive
  if ! ps -p $JULIA_PID > /dev/null; then
    echo "Julia server process died unexpectedly. Check julia_server.log for details."
    exit 1
  fi
  sleep 1 # wait for 1 second before checking again
done
echo "Julia server is ready."

echo "Starting ExtJS frontend server in the background..."
# Serve the extjs_app directory on port 8000
python3 -m http.server --directory extjs_app 8000 > extjs_server.log 2>&1 &
EXTJS_PID=$!
echo "ExtJS server started with PID: $EXTJS_PID"

echo "Both servers are running. You can view logs in extjs_server.log and julia_server.log"
echo "Access the web application at http://localhost:8000"
