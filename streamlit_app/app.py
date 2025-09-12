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
JULIA_SIMULATION_URL = "http://127.0.0.1:8081/run_simulation"
JULIA_LAYOUT_URL = "http://127.0.0.1:8081/calculate_layout"
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

@st.cache_data
def get_dot_string(_json_text):
    """Sends JSON to the layout endpoint and returns the DOT string."""
    try:
        valley_data = json.loads(_json_text)
        response = requests.post(JULIA_LAYOUT_URL, json=valley_data, timeout=10)
        response.raise_for_status()
        # The response is now plain text (the DOT string)
        return response.text, None
    except json.JSONDecodeError:
        return None, None # Invalid JSON, don't update the graph
    except requests.exceptions.RequestException as e:
        return None, f"Error connecting to Julia server: {e}"

def results_to_dataframe(results):
    return pd.DataFrame(results)

def convert_df_to_csv(df):
    return df.to_csv(index=True).encode('utf-8')

# --- Main Application UI ---
st.title("Hydro Valley Visualizer & Computer")
st.markdown("Define your hydro valley using the JSON editor below. The network graph will update in real-time.")

# Initialize session state
if 'simulation_results' not in st.session_state:
    st.session_state.simulation_results = None
if 'dot_string' not in st.session_state:
    st.session_state.dot_string = ""
if 'json_text' not in st.session_state:
    default_data = load_default_data()
    st.session_state.json_text = json.dumps(default_data, indent=2) if default_data else "{}"

# Create tabs
editor_tab, results_tab = st.tabs(["Editor", "Simulation Results"])

run_button = None

with editor_tab:
    col1, col2 = st.columns([1, 1.5])

    with col1:
        st.subheader("Valley Definition (JSON)")
        st.text_area(
            "Edit the JSON to see the graph update.",
            value=st.session_state.json_text,
            height=600,
            key="json_editor_text_area"
        )
        st.session_state.json_text = st.session_state.json_editor_text_area
        run_button = st.button("Run Simulation")

    # --- Real-time Layout Update Logic ---
    dot_string, layout_error = get_dot_string(st.session_state.json_text)
    if layout_error:
        st.error(layout_error)
    if dot_string:
        st.session_state.dot_string = dot_string

    with col2:
        st.subheader("Valley Network Graph")
        if st.session_state.dot_string:
            network_html_template = load_network_html()
            # We must JSON-encode the DOT string to safely embed it in the JavaScript
            network_html = network_html_template.replace("%%DOT_STRING%%", json.dumps(st.session_state.dot_string))
            components.html(network_html, height=625)
        else:
            st.warning("Invalid JSON. Please correct it to see the graph.")
            components.html("<div>Enter valid JSON to render the graph.</div>", height=625)

# --- Simulation Logic ---
if run_button:
    try:
        valley_data = json.loads(st.session_state.json_text)
        with st.spinner('Running simulation...'):
            response = requests.post(JULIA_SIMULATION_URL, json=valley_data, timeout=30)
            response.raise_for_status()
            response_data = response.json()
            st.session_state.simulation_results = response_data.get("volume_history")
        st.success("Simulation completed successfully! Check the 'Simulation Results' tab.")
    except json.JSONDecodeError:
        st.error("Invalid JSON format. Cannot run simulation.")
    except requests.exceptions.RequestException as e:
        st.error(f"Error connecting to Julia server for simulation: {e}")

with results_tab:
    st.subheader("Simulation Results")
    if st.session_state.simulation_results:
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
    else:
        st.info("Click 'Run Simulation' in the 'Editor' tab to see results here.")
