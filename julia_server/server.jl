using HTTP
using JSON

# Function to calculate total maximum power capacity from hydro valley data
function compute_capacity(req::HTTP.Request)
    try
        # Parse the JSON from the request body
        valley_data = JSON.parse(String(req.body))

        total_capacity = 0.0

        # Iterate through the units
        for unit in valley_data["units"]
            # Check if the unit is a turbine
            if unit["type"] == "turbine"
                # Find the maximum power level for this turbine
                if !isempty(unit["power_levels"])
                    max_power = maximum(level["power_MW"] for level in unit["power_levels"])
                    total_capacity += max_power
                end
            end
        end

        # Create the response object
        result = Dict("total_max_power_MW" => total_capacity)

        # Return the result as a JSON response
        return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(result))
    catch e
        println("Error processing data: $e")
        return HTTP.Response(500, "Error processing data: $e")
    end
end

# Set up the router and register the new endpoint
router = HTTP.Router()
HTTP.register!(router, "POST", "/compute_capacity", compute_capacity)

# Start the server
println("Starting Julia server on http://127.0.0.1:8081")
HTTP.serve(router, "127.0.0.1", 8081)
