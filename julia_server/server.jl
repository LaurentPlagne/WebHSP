using HTTP
using JSON
using Random

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
    for (i, r) in enumerate(reservoirs)
        node_levels[r["name"]] = (reservoir_ranks[i] - 1) * 2
    end
    for unit in units
        if haskey(node_levels, unit["upstream_reservoir"])
            node_levels[unit["name"]] = node_levels[unit["upstream_reservoir"]] + 1
        end
    end

    # --- Part 3: Ensure all nodes have a level to prevent rendering errors ---
    for r in reservoirs
        if !haskey(node_levels, r["name"])
            node_levels[r["name"]] = 0
        end
    end
    for u in units
        if !haskey(node_levels, u["name"])
            node_levels[u["name"]] = 0
        end
    end

    return node_levels
end

function topological_sort_units(reservoirs, units; upstream=false)
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

    ranks = zeros(Int, num_reservoirs)
    function calculate_rank(adj_matrix, r_idx)
        if ranks[r_idx] > 0
            return ranks[r_idx]
        end
        rk = 1
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

    adj_matrix_to_use = upstream ? transpose(adj) : adj
    for i in 1:num_reservoirs
        calculate_rank(adj_matrix_to_use, i)
    end

    sorted_units = sort(
        units,
        by = u -> get(ranks, get(reservoir_to_idx, u["upstream_reservoir"], 0), 0)
    )

    println("Topologically sorted units ($(upstream ? "upstream" : "downstream")): ")
    for u in sorted_units
        rank_val = get(ranks, get(reservoir_to_idx, u["upstream_reservoir"], 0), 0)
        println("- $(u["name"]) (Rank: $rank_val)")
    end
    flush(stdout)

    return sorted_units
end

function calculate_layout(req::HTTP.Request)
    try
        valley_data = JSON.parse(String(req.body))
        reservoirs = valley_data["reservoirs"]
        units = valley_data["units"]
        node_levels = calculate_topological_node_levels(reservoirs, units)
        println("Layout calculated via /calculate_layout endpoint.")
        flush(stdout)
        response_data = Dict("node_levels" => node_levels)
        return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(response_data))
    catch e
        println("Error during layout calculation: $e")
        error_response = Dict("error" => "Error during layout calculation: $(sprint(showerror, e))")
        return HTTP.Response(500, ["Content-Type" => "application/json"], body=JSON.json(error_response))
    end
end

function run_simulation(req::HTTP.Request)
    try
        valley_data = JSON.parse(String(req.body))
        num_timesteps = valley_data["time_horizon"]["num_timesteps"]
        timestep_hours = valley_data["time_horizon"]["timestep_hours"]
        units = valley_data["units"]
        reservoirs = valley_data["reservoirs"]
        m3s_to_Mm3_per_step = (3600 * timestep_hours) / 1_000_000

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

        reservoir_volumes = Dict{String, Float64}(r["name"] => r["initial_volume_M_m3"] for r in reservoirs)
        volume_history = Dict{String, Vector{Float64}}(r["name"] => [r["initial_volume_M_m3"]] for r in reservoirs)
        reservoir_map = Dict{String, Any}(r["name"] => r for r in reservoirs)
        node_levels = calculate_topological_node_levels(reservoirs, units)
        sorted_units = topological_sort_units(reservoirs, units)

        for t in 1:num_timesteps
            chosen_flows = Dict{String, Float64}()
            for unit in units
                power_levels = vcat(unit["power_levels"], [Dict("flow_rate_m3_s" => 0, "power_MW" => 0)])
                chosen_level = rand(power_levels)
                chosen_flows[unit["name"]] = chosen_level["flow_rate_m3_s"]
            end

            for (unit1_name, unit2_name) in conflicts
                if chosen_flows[unit1_name] > 0 && chosen_flows[unit2_name] > 0
                    if rand() < 0.5
                        chosen_flows[unit1_name] = 0.0
                    else
                        chosen_flows[unit2_name] = 0.0
                    end
                end
            end

            for unit in sorted_units
                flow_rate_m3_s = chosen_flows[unit["name"]]
                if flow_rate_m3_s > 0
                    up_res_name = unit["upstream_reservoir"]
                    down_res_name = unit["downstream_reservoir"]
                    if haskey(reservoir_map, up_res_name) && haskey(reservoir_map, down_res_name)
                        volume_change_Mm3 = flow_rate_m3_s * m3s_to_Mm3_per_step
                        current_up_vol = reservoir_volumes[up_res_name]
                        new_up_vol = current_up_vol - volume_change_Mm3
                        up_res_obj = reservoir_map[up_res_name]
                        min_up_vol = up_res_obj["min_volume_M_m3"][t]
                        max_up_vol = up_res_obj["max_volume_M_m3"][t]
                        reservoir_volumes[up_res_name] = clamp(new_up_vol, min_up_vol, max_up_vol)
                        current_down_vol = reservoir_volumes[down_res_name]
                        new_down_vol = current_down_vol + volume_change_Mm3
                        down_res_obj = reservoir_map[down_res_name]
                        min_down_vol = down_res_obj["min_volume_M_m3"][t]
                        max_down_vol = down_res_obj["max_volume_M_m3"][t]
                        reservoir_volumes[down_res_name] = clamp(new_down_vol, min_down_vol, max_down_vol)
                    end
                end
            end

            for r_name in keys(volume_history)
                push!(volume_history[r_name], reservoir_volumes[r_name])
            end
        end

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
HTTP.register!(router, "POST", "/calculate_layout", calculate_layout)

println("Starting Julia simulation server on http://127.0.0.1:8081")
HTTP.serve(router, "127.0.0.1", 8081)
