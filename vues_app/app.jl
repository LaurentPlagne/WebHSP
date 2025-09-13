using HTTP

const VUE_APP_DIR = @__DIR__
const PORT = 8080

# This function serves static files from the project directory.
# It's a simplified version for security and clarity.
function serve_static_file(req::HTTP.Request)
    # Sanitize the path to prevent directory traversal attacks
    # req.target is something like "/datasets/hydro_valley_instance.json"
    # We want to map it to vues_app/datasets/hydro_valley_instance.json,
    # but the Julia process is started from the root of the repo.
    # So we need to construct the path relative to the repo root.

    # The Vue app requests `/datasets/hydro_valley_instance.json`.
    # We need to map this to `vues_app/../streamlit_app/datasets/hydro_valley_instance.json`
    # because the data is not in the vues_app directory.
    # Let's copy the data file into the vues_app for simplicity.

    # Let's reconsider. The Vue app is in `vues_app`. The data is in `streamlit_app/datasets`.
    # For now, let's assume the data is also served from the root.
    # The `onMounted` hook in the Vue app requests `/datasets/hydro_valley_instance.json`.
    # This server needs to handle that.

    # The file path requested by the client
    requested_path = HTTP.URI(req.target).path

    # Let's be very specific about what we serve. We only need to serve one data file.
    if requested_path == "/datasets/hydro_valley_instance.json"
        # The data file is in the `streamlit_app` directory.
        # The server is run from the root of the repo.
        file_path = joinpath(@__DIR__, "..", "streamlit_app", "datasets", "hydro_valley_instance.json")
        if isfile(file_path)
            return HTTP.Response(200, read(file_path, String))
        end
    end

    return HTTP.Response(404, "Not Found")
end


function serve_vue_app(req::HTTP.Request)
    # Always serve the index.html for any non-static request.
    # This is the core of a Single Page Application (SPA).
    file_path = joinpath(VUE_APP_DIR, "index.html")
    if isfile(file_path)
        return HTTP.Response(200, ["Content-Type" => "text/html"], body=read(file_path, String))
    else
        return HTTP.Response(404, "index.html not found!")
    end
end

# Define the router
const ROUTER = HTTP.Router()

# Specific route for the dataset
HTTP.register!(ROUTER, "GET", "/datasets/hydro_valley_instance.json", serve_static_file)

# Catch-all route for the Vue app
HTTP.register!(ROUTER, "GET", "/*", serve_vue_app)

# Start the server
println("Starting Vue.js frontend server on http://127.0.0.1:$PORT")
HTTP.serve(ROUTER, "127.0.0.1", PORT)
