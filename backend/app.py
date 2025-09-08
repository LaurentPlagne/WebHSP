from flask import Flask, jsonify, send_from_directory, request, abort
import requests
import os

app = Flask(__name__, static_folder='../frontend')

JULIA_SERVER_URL = "http://127.0.0.1:8081/compute_capacity"

@app.route('/')
def index():
    return send_from_directory(app.static_folder, 'index.html')

@app.route('/<path:path>')
def static_proxy(path):
    # This is for serving any other static files like CSS, JS, etc.
    return send_from_directory(app.static_folder, path)

@app.route('/datasets/<path:path>')
def send_dataset(path):
    return send_from_directory(os.path.join(os.path.dirname(__file__), 'datasets'), path)

@app.route('/api/compute_valley', methods=['POST'])
def compute_valley():
    valley_data = request.get_json()
    if not valley_data:
        abort(400, 'Missing JSON data in request')

    # Forward the request to the Julia service
    try:
        julia_response = requests.post(JULIA_SERVER_URL, json=valley_data)
        julia_response.raise_for_status()  # Raise an exception for bad status codes
        return jsonify(julia_response.json())
    except requests.exceptions.RequestException as e:
        abort(500, f"Error contacting Julia server: {e}")

if __name__ == '__main__':
    app.run(port=5000, debug=True)
