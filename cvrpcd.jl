using JuMP, Gurobi, Plots, Random, Distances, Colors

# Set random seed for the Random package
Random.seed!()

# Define the data variables
U = 8                # number of coordinates
client_demand = 5   # Maximum demand per client
vehicle_capacity = 15  # Maximum vehicle capacity
D = 3                 # number of days
K = 5                 # number of vehicles

locations = 1:U       # Set of destinations
clients   = 2:U       # Set of clients (excluding the depot)
days      = 1:D       # Set of days

Md        = vehicle_capacity # Large value for the load constraint
Mt        = 5000             # Large value for the time constraint
Pd        = 0.75              # Probability that a client has a demand on a given day
R         = 30               # Maximum length of each distance
L         = 10               # Maximum time a client can wait

# Generate input data
coords = [(rand(1:R), rand(1:R)) for i in clients] # Client coordinates
pushfirst!(coords, (R/2,R/2))                      # Depot coordinates

distances = [Euclidean()(coords[i], coords[j]) for i in locations, j in locations] # Distances between clients

# Client demands making sure that the depot has no demand having in mind that Pd
demands = [rand(0:client_demand) * (rand() < Pd) for i in locations, d in days]


# Model
model = Model(Gurobi.Optimizer)

# Decision variables
@variable(model, x[locations, locations, days], Bin) # 1 if vehicle k goes from client i to client j on day d
@variable(model, time[locations, days] >= 0)         # Arrival time at client i on day d
@variable(model, load[clients, days] >= 0)           # Load of vehicle k upon arrival at client i on day d
@variable(model, y[days], Bin)                       # 1 if a new route starts on day d


# Objective function
@objective(model, Min, sum(distances[i, j] * x[i, j, d] for i in locations, j in locations, d in days)) 
# Minimize the total distance traveled

# Constraints

## Clients must be visited only once per day
for i in clients, d in days
    if demands[i, d] > 0  # Considerar solo los clientes con demanda mayor a cero
        @constraint(model, sum(x[i, j, d] for j in locations) == 1)
        @constraint(model, sum(x[j, i, d] for j in locations) == 1)
    else
        @constraint(model, sum(x[i, j, d] for j in locations) == 0)  # Restricción para evitar la visita a clientes sin demanda
        @constraint(model, sum(x[j, i, d] for j in locations) == 0)
    end
end
## Load constraint
@constraint(model, [i in clients, j in clients, d in days],  load[j, d] >= load[i, d] + demands[i, d] * x[i, j, d] - Md * (1 - x[i, j, d]))

## Arrival time constraint
@constraint(model, [i in locations, j in clients, d in days],  time[j, d] >= time[i, d] + distances[i,j] * x[i, j, d] - Mt * (1 - x[i, j, d]))

## Time constraint
for i in clients, d in days, e in days
    if d != e && demands[i, d] > 0
        @constraint(model, time[i, d] - time[i, e] <= L) # The difference in waiting time for client i between day d and the previous day must be less than L
    end
end

# Constraints to ensure each vehicle starts and ends at the depot
@constraint(model, [d in days], sum(x[1, j, d] for j in clients) == 1) # Each vehicle must start at the depot on day d
@constraint(model, [d in days], sum(x[i, 1, d] for i in clients) == 1) # Each vehicle must end at the depot on day d

# Additional constraint to separate routes
@constraint(model, [d in days], sum(x[1, j, d] for j in clients) <= y[d] * K) 

optimize!(model)


solution = value.(x)
times = value.(time)
new_routes = value.(y)

routes = Dict{Int, Vector{Int}}()
global subroutes= Dict{Int,Vector{Vector{Int}}}()
global current_subroute = Dict{Int,Vector{Int}}()
# Get the routes
for d in days
    routes[d] = []
    for i in locations
        for j in locations
            if solution[i, j, d] >= 0.9
                push!(routes[d], j)
            end
        end
    end
    pushfirst!(routes[d], 1)  # Add the depot as the starting point of each route
    push!(routes[d], 1)  # Add the depot as the ending point of each route
end

for d in days
    subroutes[d] = []
    current_subroute[d] = []
        for r in routes[d]
            if r == 1
                if !isempty(current_subroute[d])
                    push!(subroutes[d], copy(current_subroute[d]))
                    empty!(current_subroute[d])
                end
            else
                push!(current_subroute[d], r)
            end
        end
        if !isempty(current_subroute[d])
            push!(subroutes[d], copy(current_subroute[d]))
        end
    for s in subroutes[d]
        sort!(s, by = i -> times[i, d])
        pushfirst!(s, 1)
        push!(s, 1)
    end
end

# Print the routes separately for each day
for d in days
    printstyled("Day $d -> Routes: $(subroutes[d])\n", color = :red, bold = true)
    # take each client in the subroutes and print them
    if haskey(subroutes, d) 
        for s in subroutes[d]
            printstyled("Route: $(s)\n", color = :blue, bold = true)
            for i in s
                if i != 1
                    println("Client $i - Demand: $(demands[i, d]) - Arrival Time: $(times[i, d])")
                end
            end
        end
    else
        println("No route for this day")
    end
end

for d in days
    local p = plot()
    title!("Capacitated Vehicle Routing Problem With Consistent Days. Day $d")

    scatter!([coords[i][1] for i in clients], [coords[i][2] for i in clients], label = "Clients", color = :lightpink, markersize = 20, legend = :outertopright)

    local pointsArray = []

    for i in clients
        annotate!(coords[i][1], coords[i][2], text("$(i)", :black))
    end

    scatter!(coords[1], label = "Depot", color = :blue, markersize = 30, legend = :outertopright)
    annotate!(coords[1][1], coords[1][2] + 0.75, text("DEPOT", :black), offset = :left)

    plot!(size=(1000, 1000))

    for s in subroutes[d]
        coordsSubroute = [coords[i] for i in s]
        plot!(coordsSubroute, label = "route", arrow=(:closed, 2.0), linewidth = 5, legend = :outertopright, palette = palette(:Set3))
    end
        
    display(p)
    savefig("Solution_Figure_$(d).png")
end