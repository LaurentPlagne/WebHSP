#!/bin/bash
# This script starts the Vue.js frontend and the Julia backend server.

echo "Installing Julia dependencies for the simulation server..."
julia --project=julia_server -e 'using Pkg; Pkg.instantiate()'

echo "Installing Julia dependencies for the Vue.js frontend server..."
julia --project=vues_app -e 'using Pkg; Pkg.instantiate()'

echo "Installing Node.js dependencies for the Vue.js app..."
(cd vues_app && npm install)

echo "Starting Julia simulation server in the background..."
# Run the Julia server, activating the project environment in its directory
# Redirect stdout and stderr to a log file.
julia --project=julia_server julia_server/server.jl > julia_simulation_server.log 2>&1 &
JULIA_SIM_PID=$!
echo "Julia simulation server started with PID: $JULIA_SIM_PID"

echo "Starting Vue.js frontend server in the background..."
# Run the Julia server for the frontend
# Redirect stdout and stderr to a log file.
julia --project=vues_app vues_app/app.jl > vue_frontend_server.log 2>&1 &
VUE_SERVER_PID=$!
echo "Vue.js frontend server started with PID: $VUE_SERVER_PID"

echo "Both servers are running. You can view logs in julia_simulation_server.log and vue_frontend_server.log"
echo "Access the web application at http://localhost:8080"
