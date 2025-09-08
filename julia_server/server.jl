using HTTP
using JSON

function process_data(req::HTTP.Request)
    try
        body = String(req.body)
        data = JSON.parse(body)

        if !(data isa AbstractArray)
            return HTTP.Response(400, "Invalid input: expected an array of numbers.")
        end

        processed_data = [x + (rand() * 0.2 - 0.1) for x in data]

        return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(processed_data))
    catch e
        return HTTP.Response(500, "Error processing data: $e")
    end
end

router = HTTP.Router()
HTTP.register!(router, "POST", "/process", process_data)

println("Starting Julia server on http://127.0.0.1:8081")
HTTP.serve(router, "127.0.0.1", 8081)
