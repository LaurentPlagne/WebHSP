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

# Create tabs
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

    # --- Real-time Layout Update Logic ---
    dot_string, layout_error = get_dot_string(st.session_state.json_text)
    if layout_error:
        st.error(layout_error)
    if dot_string:
        st.session_state.dot_string = dot_string

    with col2:
        st.subheader("Valley Network Graph")
        if st.session_state.dot_string:
            try:
                # Get data from JSON
                valley_data = json.loads(st.session_state.json_text)
                entity_info = {}

                for r in valley_data.get("reservoirs", []):
                    connections = [t["name"] for t in valley_data.get("turbines", []) if t.get("reservoir") == r["name"]]
                    entity_info[r["name"]] = {"kind": "Reservoir", "connections": ", ".join(connections)}

                for t in valley_data.get("turbines", []):
                    entity_info[t["name"]] = {"kind": "Turbine", "connections": t.get("reservoir", "N/A")}

                for j in valley_data.get("junctions", []):
                    # Connections for junctions are not straightforward from the provided data structure.
                    # This part may need to be revisited if more detailed connection info is required.
                    entity_info[j["name"]] = {"kind": "Junction", "connections": "N/A"}

                graphs = pydot.graph_from_dot_data(st.session_state.dot_string)
                graph = graphs[0]
                nodes = []
                edges = []
                for pydot_node in graph.get_nodes():
                    node_id = pydot_node.get_name().strip('"')
                    node_label = pydot_node.get_label().strip('"') if pydot_node.get_label() else node_id
                    info = entity_info.get(node_id, {"kind": "N/A", "connections": "N/A"})
                    title = f"Name: {node_id}\nKind: {info['kind']}\nConnections: {info['connections']}"
                    nodes.append(Node(id=node_id,
                                      label=node_label,
                                      title=title))
                for pydot_edge in graph.get_edges():
                    edges.append(Edge(source=pydot_edge.get_source().strip('"'),
                                      target=pydot_edge.get_destination().strip('"')))

                config = Config(width=600,
                                height=625,
                                directed=True,
                                physics=False,
                                hierarchical=True,
                                )

                node_id = agraph(nodes=nodes, edges=edges, config=config)
                if node_id:
                    st.session_state.selected_node = node_id
            except Exception as e:
                st.error(f"Error rendering graph: {e}")
        else:
            st.warning("Invalid JSON. Please correct it to see the graph.")

    with col3:
        st.subheader("Details")
        selected_node = st.session_state.get("selected_node")
        if selected_node:
            st.write(f"**Selected:** {selected_node}")

            # Display simulation data if available
            if st.session_state.get("simulation_results"):
                if selected_node in st.session_state.simulation_results:
                    volume_data = st.session_state.simulation_results[selected_node]
                    df = pd.DataFrame({
                        "Metric": ["Min Volume", "Max Volume"],
                        "Value": [min(volume_data), max(volume_data)]
                    })
                    st.table(df)
                else:
                    st.info("No simulation data available for this entity.")
            else:
                st.info("Run a simulation to see detailed data.")
        else:
            st.info("Hover over a node in the graph to see details.")

with simulation_tab:
    st.subheader("Simulation")
    if st.button("Launch simulation"):
        try:
            valley_data = json.loads(st.session_state.json_text)
            with st.spinner('Running simulation...'):
                response = requests.post(JULIA_SIMULATION_URL, json=valley_data, timeout=30)
                response.raise_for_status()
                response_data = response.json()
                st.session_state.simulation_results = response_data.get("volume_history")
            st.success("Simulation completed successfully!")
        except json.JSONDecodeError:
            st.error("Invalid JSON format. Cannot run simulation.")
        except requests.exceptions.RequestException as e:
            st.error(f"Error connecting to Julia server for simulation: {e}")

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
        st.info("Click 'Launch simulation' to see results here.")
