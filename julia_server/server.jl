using HTTP
using JSON
using Random

# Function to run the hydro valley simulation
function run_simulation(req::HTTP.Request)
    try
        # 1. Parse the JSON from the request body
        valley_data = JSON.parse(String(req.body))

        # Extract simulation parameters
        num_timesteps = valley_data["time_horizon"]["num_timesteps"]
        timestep_hours = valley_data["time_horizon"]["timestep_hours"]

        # Conversion factor from m^3/s for one hour to Million m^3
        m3s_to_Mm3_per_step = (3600 * timestep_hours) / 1_000_000

        # 2. Initialize reservoir volumes and history
        # Use a dictionary to map reservoir names to their current volume
        reservoir_volumes = Dict{String, Float64}(
            r["name"] => r["initial_volume_M_m3"] for r in valley_data["reservoirs"]
        )

        # Use a dictionary to store the time series for each reservoir
        volume_history = Dict{String, Vector{Float64}}(
            r["name"] => [r["initial_volume_M_m3"]] for r in valley_data["reservoirs"]
        )

        # 3. Main simulation loop
        for t in 1:num_timesteps
            # Calculate net flow for each reservoir for this time step
            net_flow_change = Dict{String, Float64}(r["name"] => 0.0 for r in valley_data["reservoirs"])

            # For each unit, randomly select a power level
            for unit in valley_data["units"]
                # Include an "off" state with 0 flow
                power_levels = vcat(unit["power_levels"], [Dict("flow_rate_m3_s" => 0, "power_MW" => 0)])

                # Randomly choose one operational level
                chosen_level = rand(power_levels)
                flow_rate = chosen_level["flow_rate_m3_s"]

                # Update the net flow for the connected reservoirs
                net_flow_change[unit["downstream_reservoir"]] += flow_rate
                net_flow_change[unit["upstream_reservoir"]] -= flow_rate
            end

            # Update reservoir volumes based on the net flow
            for (name, vol) in reservoir_volumes
                volume_change_Mm3 = net_flow_change[name] * m3s_to_Mm3_per_step
                new_volume = vol + volume_change_Mm3

                # Enforce min/max volume constraints (simple clipping)
                min_vol = valley_data["reservoirs"][findfirst(r -> r["name"] == name, valley_data["reservoirs"])]["min_volume_M_m3"][t]
                max_vol = valley_data["reservoirs"][findfirst(r -> r["name"] == name, valley_data["reservoirs"])]["max_volume_M_m3"][t]
                new_volume = clamp(new_volume, min_vol, max_vol)

                reservoir_volumes[name] = new_volume
                push!(volume_history[name], new_volume)
            end
        end

        # 4. Return the volume history
        return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(volume_history))

    catch e
        println("Error during simulation: $e")
        # Also print stacktrace for debugging
        for (exc, bt) in Base.catch_stack()
            println(sprint(showerror, exc, bt))
        end
        return HTTP.Response(500, "Error during simulation: $e")
    end
end

# Set up the router and register the endpoint
router = HTTP.Router()
# The endpoint is now `/run_simulation`
HTTP.register!(router, "POST", "/run_simulation", run_simulation)

# Start the server
println("Starting Julia simulation server on http://127.0.0.1:8081")
HTTP.serve(router, "127.0.0.1", 8081)
