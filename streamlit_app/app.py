import streamlit as st
import requests
import json
import pandas as pd
import os
import streamlit.components.v1 as components

# --- App Configuration ---
st.set_page_config(
    page_title="Hydro Valley Visualizer & Computer",
    layout="wide"
)

# --- Constants ---
JULIA_SERVER_URL = "http://127.0.0.1:8081/run_simulation"
DATA_FILE_PATH = os.path.join(os.path.dirname(__file__), 'datasets', 'hydro_valley_instance.json')
NETWORK_HTML_PATH = os.path.join(os.path.dirname(__file__), 'network_graph.html')

# --- Helper Functions ---
def load_default_data():
    try:
        with open(DATA_FILE_PATH, 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        st.error(f"Error loading default data: {e}")
        return {}

def load_network_html():
    try:
        with open(NETWORK_HTML_PATH, 'r') as f:
            return f.read()
    except FileNotFoundError:
        st.error("Network graph HTML file not found.")
        return ""

def results_to_dataframe(results):
    return pd.DataFrame(results)

def convert_df_to_csv(df):
    return df.to_csv(index=True).encode('utf-8')

# --- Main Application UI ---
st.title("Hydro Valley Visualizer & Computer")
st.markdown("Define your hydro valley using the JSON editor below, view the network graph, and run a simulation.")

# Initialize session state
if 'simulation_results' not in st.session_state:
    st.session_state.simulation_results = None
if 'node_levels' not in st.session_state:
    st.session_state.node_levels = None

default_data = load_default_data()
initial_json_text = json.dumps(default_data, indent=2) if default_data else "{}"
network_html_template = load_network_html()

col1, col2 = st.columns([1, 1.5])

with col1:
    st.subheader("Valley Definition (JSON)")
    json_input = st.text_area("Edit the JSON to see the graph update.", initial_json_text, height=600)
    run_button = st.button("Run Simulation")

with col2:
    st.subheader("Valley Network Graph")
    try:
        valley_data = json.loads(json_input)
        # Prepare data for the HTML component
        graph_data = {
            "valleyData": valley_data,
            "nodeLevels": st.session_state.get('node_levels') # Pass levels if available
        }
        network_html = network_html_template.replace("%%GRAPH_DATA%%", json.dumps(graph_data))
        components.html(network_html, height=625)
    except json.JSONDecodeError:
        st.warning("Invalid JSON. Please correct it to see the graph.")
        components.html("<div>Enter valid JSON to render the graph.</div>", height=625)

# --- Simulation Logic ---
if run_button:
    try:
        valley_data = json.loads(json_input)
        with st.spinner('Running simulation...'):
            response = requests.post(JULIA_SERVER_URL, json=valley_data, timeout=30)
            response.raise_for_status()
            response_data = response.json()
            # Store both results and levels in session state
            st.session_state.simulation_results = response_data.get("volume_history")
            st.session_state.node_levels = response_data.get("node_levels")
        st.success("Simulation completed successfully!")
        st.experimental_rerun() # Rerun to update the graph with new levels
    except json.JSONDecodeError:
        st.error("Invalid JSON format. Cannot run simulation.")
    except requests.exceptions.RequestException as e:
        st.error(f"Error connecting to Julia server: {e}")

# --- Display Results ---
if st.session_state.simulation_results:
    st.subheader("Simulation Results")

    results_df = results_to_dataframe(st.session_state.simulation_results)
    results_df.index.name = "Time Step"

    st.line_chart(results_df)

    st.download_button(
        label="Download Results (CSV)",
        data=convert_df_to_csv(results_df),
        file_name="simulation_results.csv",
        mime="text/csv",
    )

    with st.expander("View Raw Result Data"):
        st.json(st.session_state.simulation_results)
