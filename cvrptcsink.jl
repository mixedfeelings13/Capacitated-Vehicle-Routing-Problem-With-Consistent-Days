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
vehicles  = 1:K
days      = 1:D # Conjunto de dias

Md        = 5000 # Valor grande para la restricción de cargas
Mt        = 5000 # Valor grande para la restricción de tiempos
Pd        = 50  # Probabilidad de que el cliente tenga una demanda en un dia determinado
R         = 20  # longitud máxima de cada distancia
L         = 5  # Tiempo maximo que puede esperar un cliente

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
@variable(model, x[locations, locations, days], Bin) # 1 si el vehiculo k va del cliente i al cliente j en el dia d

@variable(model, time[locations, days] >= 0) # Tiempo de llegada al cliente i en el dia d

@variable(model, load[clients, days] >= 0) # Carga del vehiculo k al llegar al cliente i en el dia d


# Función objetivo
@objective(model, Min, sum(distances[i,j]*x[i,j,d] for i in locations, j in locations, d in days)) # Minimizar la distancia total recorrida

# Restricciones

# Para cada cliente y dia la suma de los vehiculos que llegan al cliente debe ser igual a 1
for i in clients
    for d in days
        if (demands[i-1,d] >= 1)
            @constraint(model, sum(x[i, j, d] for j in locations) == 1)
            @constraint(model, sum(x[j, i, d] for j in locations) == 1)
        else 
        end
    end
end

# Restriccion de carga
@constraint(model, [i in clients, j in clients, d in days],  load[j,d] >= load[i,d] + demands[i-1,d] * x[i, j, d] - Md * (1 - x[i, j, d]))
# Restricción de tiempo de llegada
@constraint(model, [i in locations, j in clients, d in days],  time[j,d] >= time[i,d] + distances[i,j] * x[i, j, d] - Mt * (1 - x[i, j, d]))

# Restricción de tiempo
for i in clients,  d in days, e in days
    if (d == e) continue end
    if (demands[i-1,d] >= 1 && demands[i-1,e] >= 1)
        @constraint(model, time[i,d] - time[i,e] <= L) # La diferencia de tiempo de espera del cliente i en el dia d y el dia anterior debe ser menor que L
    end
end

# Cada vehiculo debe empezar y terminar en el deposito
@constraint(model, [d in days], sum(x[1,j,d] for j in clients) == 1) # Cada vehiculo k debe empezar en el deposito en el dia d

optimize!(model)

# Obtener la solución de las variables de decisión
solution = value.(x)
times = value.(time)



routes = Dict{Int,Vector{Int}}()

for d in days
    #routes[d] = Dict{Int, Vector{Int}}()
    route = [i for i in locations if any(solution[i, j, d] == 1 for j in locations)]

    # order the route using times
    route = sort(route, by = i -> times[i,d])

    push!(route, 1)
    if isempty(route)
        routes[d] = []
        continue
    end

    routes[d] = route

    println("Day $d: $(route)")
    for i in route
        if i == 1
            continue
        end
        println("Cliente $i: $(times[i,d])")
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

        route = routes[d]
        coordsRoute = [coords[i] for i in route]
        if(isempty(coordsRoute)) 
            continue
        end
        plot!(coordsRoute, label =  "Route", arrow=(:closed, 2.0), linewidth = 5, legend = :outertopright, palette = palette(:Set2))

    



    # Creo lineas para las rutas que sean visibles.
    # for k in vehicles
    #     route = routes[d][k]
    #     coordsRoute = [coords[i] for i in route]
    #     if(isempty(coordsRoute)) 
    #         continue
    #     end
    #     plot!(coordsRoute, label =  "Vehicle $k", arrow=(:closed, 2.0), linewidth = 5, legend = :outertopright, palette = palette(:Set2))
        
    # end
    display(p)
    savefig("Solution_Figure_Day_$d.png")
end
