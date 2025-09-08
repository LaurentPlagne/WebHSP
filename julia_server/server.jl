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
        units = valley_data["units"]
        reservoirs = valley_data["reservoirs"]

        m3s_to_Mm3_per_step = (3600 * timestep_hours) / 1_000_000

        # 2. Identify conflicting unit pairs (turbine/pump between same two reservoirs)
        conflicts = Dict()
        for (i, unit1) in enumerate(units)
            for j in (i+1):length(units)
                unit2 = units[j]
                # Check if they connect the same reservoirs but in opposite directions
                if unit1["upstream_reservoir"] == unit2["downstream_reservoir"] &&
                   unit1["downstream_reservoir"] == unit2["upstream_reservoir"]
                   # Ensure one is a turbine and the other is a pump
                   if unit1["type"] != unit2["type"]
                       conflicts[unit1["name"]] = unit2["name"]
                   end
                end
            end
        end

        # 3. Initialize reservoir volumes and history
        reservoir_volumes = Dict{String, Float64}(r["name"] => r["initial_volume_M_m3"] for r in reservoirs)
        volume_history = Dict{String, Vector{Float64}}(r["name"] => [r["initial_volume_M_m3"]] for r in reservoirs)

        # 4. Main simulation loop
        for t in 1:num_timesteps

            # Step A: Randomly select an operational level for each unit
            chosen_flows = Dict{String, Float64}()
            for unit in units
                power_levels = vcat(unit["power_levels"], [Dict("flow_rate_m3_s" => 0, "power_MW" => 0)])
                chosen_level = rand(power_levels)
                chosen_flows[unit["name"]] = chosen_level["flow_rate_m3_s"]
            end

            # Step B: Correct for any conflicts
            for (unit1_name, unit2_name) in conflicts
                if chosen_flows[unit1_name] > 0 && chosen_flows[unit2_name] > 0
                    # Conflict found! Randomly turn one off.
                    if rand() < 0.5
                        chosen_flows[unit1_name] = 0.0
                    else
                        chosen_flows[unit2_name] = 0.0
                    end
                end
            end

            # Step C: Calculate net flow for each reservoir
            net_flow_change = Dict{String, Float64}(r["name"] => 0.0 for r in reservoirs)
            for unit in units
                flow_rate = chosen_flows[unit["name"]]
                if flow_rate > 0
                    net_flow_change[unit["downstream_reservoir"]] += flow_rate
                    net_flow_change[unit["upstream_reservoir"]] -= flow_rate
                end
            end

            # Step D: Update reservoir volumes
            for (name, vol) in reservoir_volumes
                volume_change_Mm3 = net_flow_change[name] * m3s_to_Mm3_per_step
                new_volume = vol + volume_change_Mm3

                min_vol = reservoirs[findfirst(r -> r["name"] == name, reservoirs)]["min_volume_M_m3"][t]
                max_vol = reservoirs[findfirst(r -> r["name"] == name, reservoirs)]["max_volume_M_m3"][t]
                clamped_volume = clamp(new_volume, min_vol, max_vol)

                reservoir_volumes[name] = clamped_volume
                push!(volume_history[name], clamped_volume)
            end
        end

        return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(volume_history))

    catch e
        println("Error during simulation: $e")
        for (exc, bt) in Base.catch_stack()
            println(sprint(showerror, exc, bt))
        end
        return HTTP.Response(500, "Error during simulation: $e")
    end
end

router = HTTP.Router()
HTTP.register!(router, "POST", "/run_simulation", run_simulation)

println("Starting Julia simulation server on http://127.0.0.1:8081")
HTTP.serve(router, "127.0.0.1", 8081)
