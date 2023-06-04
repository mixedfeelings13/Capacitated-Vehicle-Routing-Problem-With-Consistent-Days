using JuMP
using Gurobi
using Plots
using Random
using Distances
using Colors


# Semilla aleatoria para el paquete Random
Random.seed!()

# Definimos las variables de los datos
V = 10 # número de coordenadas
client_demand = 1 # Demanda maxima por cliente

K = 5  #  número de vehiculos
vehicle_capacity = 10 # Capacidad maxima del vehiculo


D = 3  # número de días

locations = 1:V # Conjunto de destinos
clients   = 2:V # Conjunto de clientes
vehicles  = 1:K # Conjunto de vehiculos
days      = 1:D # Conjunto de dias

Md        = 5000 # Valor grande para la restricción de cargas
Mt        = 5000 # Valor grande para la restricción de tiempos
Pd        = 50  # Probabilidad de que el cliente tenga una demanda en un dia determinado
R         = 20  # longitud máxima de cada distancia
L         = 10  # Tiempo maximo que puede esperar un cliente

## Generamos datos de entrada
coords = [(rand(1:R), rand(1:R)) for i in clients] # Coordenadas de los clientes
pushfirst!(coords, (11,13)) # Coordenadas del deposito
# println(coords)
distances = [Euclidean()(coords[i], coords[j]) for i in locations, j in locations] # Distancias entre clientes

demands = [rand(1:100) < Pd ? rand(1:client_demand) : 0 for i in clients, d in days] # Demanda de cada cliente en cada dia<
# println(demands)
# Creamos el modelo
model = Model(Gurobi.Optimizer)

# Variables de decisión
@variable(model, x[locations, locations, vehicles, days], Bin) # 1 si el vehiculo k va del cliente i al cliente j en el dia d

@variable(model, time[locations, days] >= 0) # Tiempo de llegada al cliente i en el dia d

@variable(model, load[clients, vehicles, days] >= 0) # Carga del vehiculo k al llegar al cliente i en el dia d


# Función objetivo
@objective(model, Min, sum(distances[i,j]*x[i,j,k,d] for i in locations, j in locations, k in vehicles, d in days)) # Minimizar la distancia total recorrida


# Restricciones

# Para cada cliente y dia la suma de los vehiculos que llegan al cliente debe ser igual a 1
for i in clients
    for d in days
        if (demands[i-1,d] >= 1)
            @constraint(model, sum(x[i, j, k, d] for j in locations, k in vehicles) == 1)
            @constraint(model, sum(x[j, i, k, d] for j in locations, k in vehicles) == 1)
        else 
        end
    end
end

# Restriccion de carga
@constraint(model, [i in clients, j in clients, k in vehicles, d in days],  load[j,k,d] >= load[i,k,d] + demands[i-1,d] * x[i, j, k, d] - Md * (1 - x[i, j, k, d]))
# Restricción de tiempo de llegada
@constraint(model, [i in locations, j in locations, k in vehicles, d in days],  time[j,d] >= time[i,d] + distances[i,j] * x[i, j, k, d] - Mt * (1 - x[i, j, k, d]))

# Restricción de tiempo
for i in clients,  d in days, e in days    
    if (demands[i-1,d] >= 1 && demands[i-1,e] >= 1)
        @constraint(model, time[i,d] - time[i,d] <= L ) # El tiempo de espera del cliente i en el dia d no puede superar el tiempo maximo de espera
    end
end

# Cada vehiculo debe empezar y terminar en el deposito
@constraint(model, [k in vehicles, d in days], sum(x[1,j,k,d] for j in clients) == 1) # Cada vehiculo k debe empezar en el deposito en el dia d

optimize!(model)

# Obtener la solución de las variables de decisión
solution = value.(x)
times = value.(time)



routes = Dict{Int, Dict{Int, Vector{Int}}}()

for d in days
    routes[d] = Dict{Int, Vector{Int}}()
    println("Day $d:")
    for k in vehicles
        route = [i for i in locations if any(solution[i, j, k, d] > 0.5 for j in locations)]
        push!(route, 1)
        if length(route) == 2
            routes[d][k] = []
            continue
        end
        routes[d][k] = route

        println("Vehicle $k: ", route)
        for i in route
            println("Cliente $i: $(times[i,d])")
        end
    end
end




# Mostrar el gráfico
for d in days
    local p = plot()
    title!("Capacitated Vehicle Routing Problem With Consistent Days. Day $d")
    # Nodos de clientes
    scatter!([coords[i][1] for i in clients], [coords[i][2] for i in clients], label = "Clients", color = :lightblue, markersize = 20, legend = :outertopright)

    # define las coordenadas de las rutas
    local pointsArray = []
    # Etiquetas de los clientes
    for i in clients
        annotate!(coords[i][1], coords[i][2], text("$(i)", :black))
    end
    #Añado el deposito visiblemente
    scatter!(coords[1], label = "Depot", color = :blue, markersize = 30, legend = :outertopright)
    annotate!(coords[1][1], coords[1][2] + 0.75, text("DEPÓSITO", :black), offset = :left)
    #Cambio el tamaño para que sea más visible
    plot!(size=(2040,1080))

    # Creo lineas para las rutas que sean visibles.
    for k in vehicles
        route = routes[d][k]
        coordsRoute = [coords[i] for i in route]
        if(isempty(coordsRoute)) 
            continue
        end
        plot!(coordsRoute, label =  "Vehicle $k", arrow=(:closed, 2.0), linewidth = 5, legend = :outertopright, palette = palette(:Set2))
        
    end
    display(p)
    savefig("Solution_Figure_Day_$d.png")
end
