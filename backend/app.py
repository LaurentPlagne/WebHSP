from flask import Flask, jsonify, send_from_directory, request, abort
import os
import json
import requests

app = Flask(__name__, static_folder='../frontend')

DATASETS_DIR = os.path.join(os.path.dirname(__file__), 'datasets')
JULIA_SERVER_URL = "http://127.0.0.1:8081/process"

@app.route('/')
def index():
    return send_from_directory(app.static_folder, 'index.html')

@app.route('/<path:path>')
def static_proxy(path):
    return send_from_directory(app.static_folder, path)

@app.route('/datasets/<path:path>')
def send_dataset(path):
    return send_from_directory(DATASETS_DIR, path)

@app.route('/api/datasets', methods=['GET'])
def get_datasets():
    try:
        datasets = [f for f in os.listdir(DATASETS_DIR) if f.endswith('.json') or f.endswith('.csv')]
        return jsonify(datasets)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/process', methods=['POST'])
def process_dataset():
    data = request.get_json()
    if not data or 'dataset' not in data:
        abort(400, 'Missing dataset name in request')

    dataset_name = data['dataset']
    dataset_path = os.path.join(DATASETS_DIR, dataset_name)

    if not os.path.exists(dataset_path):
        abort(404, 'Dataset not found')

    with open(dataset_path, 'r') as f:
        if dataset_name.endswith('.json'):
            dataset_data = json.load(f)
        elif dataset_name.endswith('.csv'):
            # Basic CSV parsing, assuming one column of numbers
            dataset_data = [float(line.strip()) for line in f]
        else:
            abort(400, 'Unsupported file type')

    try:
        julia_response = requests.post(JULIA_SERVER_URL, json=dataset_data)
        julia_response.raise_for_status()
        return jsonify(julia_response.json())
    except requests.exceptions.RequestException as e:
        abort(500, f"Error contacting Julia server: {e}")

@app.route('/api/process_direct', methods=['POST'])
def process_direct():
    json_data = request.get_json()
    if not json_data or 'data' not in json_data:
        abort(400, 'Missing data in request')

    # Basic validation
    if not isinstance(json_data['data'], list):
        abort(400, 'Data must be an array')

    # Save the new dataset to a file
    import time
    dataset_name = f"direct_input_{int(time.time())}.json"
    dataset_path = os.path.join(DATASETS_DIR, dataset_name)
    with open(dataset_path, 'w') as f:
        json.dump(json_data['data'], f)

    # Call Julia service
    try:
        julia_response = requests.post(JULIA_SERVER_URL, json=json_data['data'])
        julia_response.raise_for_status()
        return jsonify(julia_response.json())
    except requests.exceptions.RequestException as e:
        abort(500, f"Error contacting Julia server: {e}")

@app.route('/api/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return 'No file part', 400
    file = request.files['file']
    if file.filename == '':
        return 'No selected file', 400
    if file:
        filename = file.filename
        if not (filename.endswith('.json') or filename.endswith('.csv')):
            return 'Invalid file type', 400

        file.save(os.path.join(DATASETS_DIR, filename))
        return 'File uploaded successfully', 200

if __name__ == '__main__':
    app.run(port=5000, debug=True)
