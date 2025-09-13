import streamlit as st
import requests
import json
import pandas as pd
import os
from streamlit_agraph import agraph, Node, Edge, Config
import pydot

# --- App Configuration ---
st.set_page_config(
    page_title="Hydro Valley Visualizer & Computer",
    layout="wide"
)

# --- Constants ---
JULIA_SIMULATION_URL = "http://127.0.0.1:8081/run_simulation"
JULIA_LAYOUT_URL = "http://127.0.0.1:8081/calculate_layout"
DATA_FILE_PATH = os.path.join(os.path.dirname(__file__), 'datasets', 'hydro_valley_instance.json')

# --- Helper Functions ---
def load_default_data():
    try:
        with open(DATA_FILE_PATH, 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        st.error(f"Error loading default data: {e}")
        return {}

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
if 'selected_node' not in st.session_state:
    st.session_state.selected_node = None

# --- UI Tabs ---
editor_tab, simulation_tab = st.tabs(["Editor", "Simulation"])

with editor_tab:
    col1, col2, col3 = st.columns([1, 1.5, 1])

    with col1:
        st.subheader("Valley Definition (JSON)")
        st.text_area(
            "Edit the JSON to see the graph update.",
            value=st.session_state.json_text,
            height=600,
            key="json_editor_text_area"
        )
        st.session_state.json_text = st.session_state.json_editor_text_area

    # --- Graph and Details Logic ---
    valley_data = json.loads(st.session_state.json_text)
    entity_info = {}
    nodes = []
    edges = []

    # Process reservoirs
    for r in valley_data.get("reservoirs", []):
        entity_info[r["name"]] = {"kind": "Reservoir", "data": r}
        nodes.append(Node(id=r["name"], label=r["name"], shape='box', color='#ADD8E6'))

    # Process units (turbines and pumps)
    for unit in valley_data.get("units", []):
        unit_type = unit.get("type", "N/A").capitalize()
        entity_info[unit["name"]] = {"kind": unit_type, "data": unit}
        color = "#90EE90" if unit_type == "Turbine" else "#FFB6C1"
        nodes.append(Node(id=unit["name"], label=unit["name"], shape='dot', color=color))
        # Add edges
        if unit.get("upstream_reservoir"):
            edges.append(Edge(source=unit["upstream_reservoir"], target=unit["name"]))
        if unit.get("downstream_reservoir"):
            edges.append(Edge(source=unit["name"], target=unit["downstream_reservoir"]))

    # Process junctions
    for j in valley_data.get("junctions", []):
        entity_info[j["name"]] = {"kind": "Junction", "data": j}
        nodes.append(Node(id=j["name"], label=j["name"], shape='diamond', color='#D3D3D3'))
        # Add edges for junctions if connection info is available
        # This part is left as a potential extension as connection info for junctions is not in the sample JSON.

    # Update tooltips
    for node in nodes:
        info = entity_info.get(node.id, {"kind": "N/A", "data": {}})
        connections = "N/A"
        if info["kind"] == "Reservoir":
            connections_list = [u["name"] for u in valley_data.get("units", []) if u.get("upstream_reservoir") == node.id or u.get("downstream_reservoir") == node.id]
            connections = ", ".join(connections_list)
        elif info["kind"] in ["Turbine", "Pump"]:
            connections = f"Upstream: {info['data'].get('upstream_reservoir', 'N/A')}, Downstream: {info['data'].get('downstream_reservoir', 'N/A')}"
        node.title = f"Name: {node.id}\nKind: {info['kind']}\nConnections: {connections}"


    with col2:
        st.subheader("Valley Network Graph")
        config = Config(width=600,
                        height=625,
                        directed=True,
                        physics=False,
                        hierarchical=True)
        node_id = agraph(nodes=nodes, edges=edges, config=config)
        if node_id:
            st.session_state.selected_node = node_id

    with col3:
        st.subheader("Details")
        selected_node_id = st.session_state.get("selected_node")
        if selected_node_id and selected_node_id in entity_info:
            st.write(f"**Selected:** {selected_node_id}")
            info = entity_info[selected_node_id]
            data = info["data"]

            if info["kind"] == "Reservoir":
                df = pd.DataFrame({
                    'Min Volume': data.get('min_volume_M_m3', []),
                    'Max Volume': data.get('max_volume_M_m3', [])
                })
                st.write("Volume Time Series (M_m3):")
                st.table(df)
            elif info["kind"] in ["Turbine", "Pump"]:
                st.write("Power Levels:")
                st.table(pd.DataFrame(data.get("power_levels", [])))
            else:
                st.info("No details available for this entity.")
        else:
            st.info("Hover over a node in the graph to see details.")

with simulation_tab:
    st.subheader("Simulation")
    if st.button("Launch simulation"):
        try:
            valley_data_sim = json.loads(st.session_state.json_text)
            with st.spinner('Running simulation...'):
                response = requests.post(JULIA_SIMULATION_URL, json=valley_data_sim, timeout=30)
                response.raise_for_status()
                response_data = response.json()
                st.session_state.simulation_results = response_data.get("volume_history")
            st.success("Simulation completed successfully!")
        except json.JSONDecodeError:
            st.error("Invalid JSON format. Cannot run simulation.")
        except requests.exceptions.RequestException as e:
            st.error(f"Error connecting to Julia server for simulation: {e}")

    if st.session_state.get("simulation_results"):
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
        st.info("Click 'Launch simulation' to see results here.")
