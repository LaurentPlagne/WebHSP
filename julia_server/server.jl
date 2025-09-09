using HTTP
using JSON
using Random

# Function to calculate node levels for hierarchical layout
function calculate_node_levels(reservoirs, units)
    node_levels = Dict{String, Int}()

    # Identify all reservoirs that are downstream of a turbine
    turbine_downstream = Set{String}()
    for unit in units
        if unit["type"] == "turbine"
            push!(turbine_downstream, unit["downstream_reservoir"])
        end
    end

    # Initialize levels for top-level reservoirs (not downstream of any turbine)
    for reservoir in reservoirs
        if !(reservoir["name"] in turbine_downstream)
            node_levels[reservoir["name"]] = 0
        end
    end

    # Iteratively determine levels for all other nodes
    max_iterations = length(reservoirs) + length(units)
    for _ in 1:max_iterations
        for unit in units
            upstream_reservoir = unit["upstream_reservoir"]
            if haskey(node_levels, upstream_reservoir)
                unit_level = node_levels[upstream_reservoir] + 1
                if !haskey(node_levels, unit["name"]) || unit_level > node_levels[unit["name"]]
                    node_levels[unit["name"]] = unit_level
                end

                downstream_reservoir = unit["downstream_reservoir"]
                downstream_level = unit_level + 1
                if !haskey(node_levels, downstream_reservoir) || downstream_level > node_levels[downstream_reservoir]
                    node_levels[downstream_reservoir] = downstream_level
                end
            end
        end
    end

    return node_levels
end

function calculate_topological_node_levels(reservoirs, units)
    # --- Part 1: Calculate base ranks of reservoirs from turbine-based graph ---
    reservoir_to_idx = Dict{String, Int}(r["name"] => i for (i, r) in enumerate(reservoirs))
    num_reservoirs = length(reservoirs)
    adj = zeros(Int, num_reservoirs, num_reservoirs)
    for unit in filter(u -> u["type"] == "turbine", units)
        if haskey(reservoir_to_idx, unit["downstream_reservoir"]) && haskey(reservoir_to_idx, unit["upstream_reservoir"])
            downstream_idx = reservoir_to_idx[unit["downstream_reservoir"]]
            upstream_idx = reservoir_to_idx[unit["upstream_reservoir"]]
            adj[downstream_idx, upstream_idx] = 1
        end
    end
    reservoir_ranks = zeros(Int, num_reservoirs)
    function calculate_rank(adj_matrix, r_idx)
        if reservoir_ranks[r_idx] > 0; return reservoir_ranks[r_idx]; end
        rk = 1
        dependencies = findall(x -> x == 1, adj_matrix[r_idx, :])
        if !isempty(dependencies)
            max_rank_dep = 0
            for r_prime_idx in dependencies
                max_rank_dep = max(max_rank_dep, calculate_rank(adj_matrix, r_prime_idx))
            end
            rk = 1 + max_rank_dep
        end
        reservoir_ranks[r_idx] = rk
        return rk
    end
    for i in 1:num_reservoirs; calculate_rank(adj, i); end

    # --- Part 2: Assign levels directly based on ranks ---
    node_levels = Dict{String, Int}()
    # Assign reservoir levels, scaled by 2 to make space for units
    for (i, r) in enumerate(reservoirs)
        node_levels[r["name"]] = (reservoir_ranks[i] - 1) * 2
    end
    # Assign unit levels to be 1 level below their upstream reservoir
    for unit in units
        if haskey(node_levels, unit["upstream_reservoir"])
            node_levels[unit["name"]] = node_levels[unit["upstream_reservoir"]] + 1
        end
    end

    return node_levels
end

function topological_sort_units(reservoirs, units; upstream=false)
    # Create a mapping from reservoir name to index
    reservoir_to_idx = Dict{String, Int}(r["name"] => i for (i, r) in enumerate(reservoirs))
    num_reservoirs = length(reservoirs)

    # Build adjacency matrix using only turbines to define the graph's topology
    # This avoids cycles caused by pumps.
    adj = zeros(Int, num_reservoirs, num_reservoirs)
    for unit in filter(u -> u["type"] == "turbine", units)
        # Skip units if reservoirs are not in the map (e.g. external)
        if haskey(reservoir_to_idx, unit["downstream_reservoir"]) && haskey(reservoir_to_idx, unit["upstream_reservoir"])
            downstream_idx = reservoir_to_idx[unit["downstream_reservoir"]]
            upstream_idx = reservoir_to_idx[unit["upstream_reservoir"]]
            adj[downstream_idx, upstream_idx] = 1
        end
    end

    # Memoization cache for ranks
    ranks = zeros(Int, num_reservoirs)

    # Recursive rank calculation function
    function calculate_rank(adj_matrix, r_idx)
        if ranks[r_idx] > 0
            return ranks[r_idx]
        end

        rk = 1
        # Find dependencies
        dependencies = findall(x -> x == 1, adj_matrix[r_idx, :])
        if !isempty(dependencies)
            max_rank_dep = 0
            for r_prime_idx in dependencies
                max_rank_dep = max(max_rank_dep, calculate_rank(adj_matrix, r_prime_idx))
            end
            rk = 1 + max_rank_dep
        end

        ranks[r_idx] = rk
        return rk
    end

    # Determine which adjacency matrix to use and calculate ranks for all reservoirs
    adj_matrix_to_use = upstream ? transpose(adj) : adj
    for i in 1:num_reservoirs
        calculate_rank(adj_matrix_to_use, i)
    end

    # Sort units based on the rank of their upstream reservoir
    sorted_units = sort(
        units,
        by = u -> ranks[reservoir_to_idx[u["upstream_reservoir"]]]
    )

    # Add a print statement for verification
    println("Topologically sorted units ($(upstream ? "upstream" : "downstream")): ")
    for u in sorted_units
        println("- $(u["name"]) (Rank: $(ranks[reservoir_to_idx[u["upstream_reservoir"]]]))")
    end
    flush(stdout)

    return sorted_units
end


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

        # 2. Identify conflicting unit pairs
        conflicts = Dict()
        for (i, unit1) in enumerate(units)
            for j in (i+1):length(units)
                unit2 = units[j]
                if unit1["upstream_reservoir"] == unit2["downstream_reservoir"] &&
                   unit1["downstream_reservoir"] == unit2["upstream_reservoir"] &&
                   unit1["type"] != unit2["type"]
                    conflicts[unit1["name"]] = unit2["name"]
                end
            end
        end

        # 3. Initialize reservoir volumes and history
        reservoir_volumes = Dict{String, Float64}(r["name"] => r["initial_volume_M_m3"] for r in reservoirs)
        volume_history = Dict{String, Vector{Float64}}(r["name"] => [r["initial_volume_M_m3"]] for r in reservoirs)

        # New: Get a map of reservoir names to the full reservoir object for quick access
        reservoir_map = Dict{String, Any}(r["name"] => r for r in reservoirs)

        # 4. Calculate node levels for graph visualization using the new topological method
        node_levels = calculate_topological_node_levels(reservoirs, units)

        # 5. Get topologically sorted units (New!)
        # We use the default downstream sort (upstream=false)
        sorted_units = topological_sort_units(reservoirs, units)

        # 6. Main simulation loop
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
                    if rand() < 0.5
                        chosen_flows[unit1_name] = 0.0
                    else
                        chosen_flows[unit2_name] = 0.0
                    end
                end
            end

            # Step C (New): Process units in topological order
            for unit in sorted_units
                flow_rate_m3_s = chosen_flows[unit["name"]]
                if flow_rate_m3_s > 0
                    up_res_name = unit["upstream_reservoir"]
                    down_res_name = unit["downstream_reservoir"]

                    # Ensure reservoirs exist before processing
                    if haskey(reservoir_map, up_res_name) && haskey(reservoir_map, down_res_name)
                        volume_change_Mm3 = flow_rate_m3_s * m3s_to_Mm3_per_step

                        # Update upstream reservoir
                        current_up_vol = reservoir_volumes[up_res_name]
                        new_up_vol = current_up_vol - volume_change_Mm3
                        up_res_obj = reservoir_map[up_res_name]
                        min_up_vol = up_res_obj["min_volume_M_m3"][t]
                        max_up_vol = up_res_obj["max_volume_M_m3"][t]
                        reservoir_volumes[up_res_name] = clamp(new_up_vol, min_up_vol, max_up_vol)

                        # Update downstream reservoir
                        current_down_vol = reservoir_volumes[down_res_name]
                        new_down_vol = current_down_vol + volume_change_Mm3
                        down_res_obj = reservoir_map[down_res_name]
                        min_down_vol = down_res_obj["min_volume_M_m3"][t]
                        max_down_vol = down_res_obj["max_volume_M_m3"][t]
                        reservoir_volumes[down_res_name] = clamp(new_down_vol, min_down_vol, max_down_vol)
                    end
                end
            end

            # Step D (New): Record volumes for this timestep
            for r_name in keys(volume_history)
                push!(volume_history[r_name], reservoir_volumes[r_name])
            end
        end

        # 7. Combine results and return
        response_data = Dict(
            "volume_history" => volume_history,
            "node_levels" => node_levels
        )

        return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(response_data))

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
