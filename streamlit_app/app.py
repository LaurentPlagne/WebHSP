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
EXAMPLES_DIR = os.path.join(os.path.dirname(__file__), '..', 'examples')
NETWORK_HTML_PATH = os.path.join(os.path.dirname(__file__), 'network_graph.html')

# --- Helper Functions ---
def get_example_files():
    """Returns a list of hd_xxx.json files from the examples directory."""
    if not os.path.exists(EXAMPLES_DIR):
        return []
    return [f for f in os.listdir(EXAMPLES_DIR) if f.startswith('hd_') and f.endswith('.json')]

def load_example_data(filename):
    """Loads a specific JSON file from the examples directory."""
    try:
        with open(os.path.join(EXAMPLES_DIR, filename), 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        st.error(f"Error loading example file {filename}: {e}")
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
        return response.text, None
    except json.JSONDecodeError:
        return None, None
    except requests.exceptions.RequestException as e:
        return None, f"Error connecting to Julia server: {e}"

def results_to_dataframe(results):
    return pd.DataFrame(results)

def convert_df_to_csv(df):
    return df.to_csv(index=True).encode('utf-8')

# --- Main Application UI ---
st.title("Hydro Valley Visualizer & Computer")
st.markdown("Load a valley description from the sidebar, or paste your own JSON into the editor. The network graph will update in real-time.")

# Initialize session state
if 'simulation_results' not in st.session_state:
    st.session_state.simulation_results = None
if 'dot_string' not in st.session_state:
    st.session_state.dot_string = ""
if 'json_text' not in st.session_state:
    example_data = load_example_data("hd_ROSELEND.json")
    st.session_state.json_text = json.dumps(example_data, indent=2) if example_data else "{}"

# --- UI for Loading Data ---
st.sidebar.title("Data Loader")
example_files = get_example_files()
options = [""] + example_files
try:
    default_index = options.index("hd_ROSELEND.json")
except ValueError:
    default_index = 0

selected_example = st.sidebar.selectbox(
    "Choose an example valley:",
    options,
    index=default_index,
    key='example_selector'
)

uploaded_file = st.sidebar.file_uploader(
    "Or upload your own JSON file:",
    type=['json'],
    key='file_uploader'
)

# --- Data Loading Logic ---
if uploaded_file is not None:
    try:
        json_data = json.load(uploaded_file)
        st.session_state.json_text = json.dumps(json_data, indent=2)
        st.sidebar.success("File uploaded successfully!")
    except json.JSONDecodeError:
        st.sidebar.error("Invalid JSON file.")
elif selected_example:
    example_data = load_example_data(selected_example)
    st.session_state.json_text = json.dumps(example_data, indent=2)

# --- Main App Layout ---
editor_tab, explorer_tab, results_tab = st.tabs(["Editor", "JSON Explorer", "Simulation Results"])

run_button = None

with editor_tab:
    col1, col2 = st.columns([1, 1.5])

    with col1:
        st.subheader("Valley Definition (JSON)")
        new_json_text = st.text_area(
            "Edit the JSON to see the graph update.",
            value=st.session_state.json_text,
            height=600,
        )
        if new_json_text != st.session_state.json_text:
            st.session_state.json_text = new_json_text
            st.experimental_rerun()

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
            network_html = network_html_template.replace("%%DOT_STRING%%", json.dumps(st.session_state.dot_string))
            components.html(network_html, height=625)
        else:
            st.warning("Invalid JSON. Please correct it to see the graph.")
            components.html("<div>Enter valid JSON to render the graph.</div>", height=625)

with explorer_tab:
    st.subheader("Explore the Valley Data")
    try:
        json_data = json.loads(st.session_state.json_text)
        st.json(json_data)
    except json.JSONDecodeError:
        st.warning("Invalid JSON format. Please fix it in the 'Editor' tab.")

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
