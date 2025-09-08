# Hydro Valley Visualizer and Computer

This web application provides an interactive environment for defining, visualizing, and running computations on a hydro valley unit commitment problem.

## Features

*   **Interactive Editor:** Define your hydro valley's reservoirs and units using a JSON editor.
*   **Real-time Visualization:** The application features a side-by-side view with a network graph that updates in real-time as you edit the JSON, providing immediate visual feedback.
*   **Julia-powered Simulation:** Click the "Run Simulation" button to send your valley definition to a high-performance Julia backend. The server runs a dynamic simulation of the reservoir volumes over the specified time horizon using a random operation strategy.
*   **Responsive Design:** The UI is fully responsive and works great on desktop or mobile, powered by Pico.css.
*   **Theme Switching:** Toggle between light and dark modes. Your preference is saved for your next visit.

## How to Run the Application

### 1. Prerequisites

- Python 3.6+ and `pip`
- Julia 1.6+

### 2. Setup

**A. Setup the Python Backend**

Open a terminal and navigate to the project's root directory. Install the necessary Python packages:

```bash
pip install -r backend/requirements.txt
```

**B. Setup the Julia Backend**

The Julia server dependencies are managed by a `Project.toml` file. To install them, use the Julia package manager to instantiate the environment:

```bash
julia --project=julia_server -e 'using Pkg; Pkg.instantiate()'
```

This command will download and install the exact versions of the packages required for this project.

### 3. Running the Servers

Convenience scripts are provided to start and stop both servers at once.

*   **To start both servers:**
    ```bash
    ./start.sh
    ```
    This will launch the servers in the background. You can monitor their output in `julia_server.log` and `backend.log`.

*   **To stop both servers:**
    ```bash
    ./kill.sh
    ```

### 4. Using the Application

Once both servers are running, open your web browser and navigate to:

**http://127.0.0.1:5000**

You can edit the JSON on the left to see the graph on the right update. Click "Run Simulation" to send the data to the Julia server. The results of the simulation (the reservoir volumes over time) will be plotted in a new chart below the JSON editor.
