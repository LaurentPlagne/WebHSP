# Multi-Tier Data Plotting Web Application

This web application demonstrates a multi-tier architecture with a frontend, a Python backend, and a Julia backend for numerical processing.

- **Frontend:** A simple HTML/JavaScript interface using Plotly.js for charting.
- **Python Backend:** A Flask API that serves the frontend, manages datasets, and communicates with the Julia service.
- **Julia Backend:** A high-performance service for numerical computations.

## How to Run the Application

To run this application, you will need to start both the Julia and Python servers.

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

The Julia server dependencies are managed by a `Project.toml` file. To install them, navigate to the `julia_server` directory and use the Julia package manager to instantiate the environment.

```bash
cd julia_server
julia --project=. -e 'using Pkg; Pkg.instantiate()'
cd ..
```

This command will download and install the exact versions of the packages required for this project (`HTTP.jl` and `JSON.jl`).

### 3. Running the Servers

You need to run both servers simultaneously in separate terminal windows.

**A. Start the Julia Server**

In your first terminal, run the server from the root directory, activating its project environment:
```bash
julia --project=julia_server julia_server/server.jl
```
You should see the message: `Starting Julia server on http://127.0.0.1:8081`

**B. Start the Python Server**

In your second terminal, run:
```bash
python backend/app.py
```
This will start the Flask development server, typically on `http://127.0.0.1:5000`.

### 4. Using the Application

Once both servers are running, open your web browser and navigate to:

**http://127.0.0.1:5000**

You will see the main page with three options:

1.  **Select a Dataset:** Choose one of the pre-existing datasets from the dropdown and click "Process". The application will fetch the original data, send it for processing, and plot both the original and processed data.
2.  **Upload a Dataset:** Upload a `.json` or `.csv` file containing a single column of numbers. After uploading, the dataset will be available in the "Select a Dataset" dropdown.
3.  **Direct Input:** Paste a JSON array of numbers (e.g., `[10, 15, 8, 22]`) into the textarea and click "Process Direct Input". The application will process your input and plot the original and processed data.
