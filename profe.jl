using JuMP
using Gurobi
using Plots
using Random
using Distances
using Colors

# Semilla aleatoria para el paquete Random
Random.seed!()


V = 30 # número de clientes
K = 5  # número de vehículos
D = 3  # númeor de días

locations = 1:V
clients   = 2:V
vehicles  = 1:K
days      = 1:D

Q       = 8     # capacidad de los vehículos
Md      = 1000  # Valor grande para la restricción de cargas
Mt      = 1000  # Valor grande para la restricción de tiempos
P       = 50    # percentage of clients with zero demand on a day
R       = 20    # maxima longitud de cada distancia
L       = 50    # maxima consistencia temporal
epsilon = 0.1

coords    = [ (rand(1:R), rand(1:R)) for i in locations ]
distances = [ Euclidean()(coords[i], coords[j]) for i in locations for j in locations ]

demands   = [ ( rand(100) < P ? 0 : rand(1:Q) ) for i in clients for d in days ]

# Creación del modelo
model = Model(Gurobi.Optimizer)

@variable(model, x[locations, locations, days], Bin) # whether an arc is or not on a route
@variable(model, load[clients, days] >= 0)           # load of the vehicle when entering a location
@variable(model, time[clients, days] >= 0)           # time when entering a location

@objective(model, Min, sum( distances[i, j] * x[i, j, d] for i in locations, j in locations, d in days))

@constraint(model, [i in locations, d in days if demands[i,d]>0 || i==1 ], sum(x[i, j, d] for j in locations ) == 1 )
@constraint(model, [i in locations, d in days if demands[i,d]>0 || i==1 ], sum(x[j, i, d] for j in locations ) == 1 )
@constraint(model, [i in locations, d in days],   x[i, i, d]==0 )

@constraint(model, [i in clients, j in clients, d in days ],  load[j,d] >= load[i,d] +   demands[i,d] * x[i, j, d] - Md * (1 - x[i, j, d]))
@constraint(model, [i in clients, j in clients, d in days ],  time[j,d] >= time[i,d] + distances[i,j] * x[i, j, d] - Mt * (1 - x[i, j, d]))

@constraint(model, [i in clients, d in days if demands[i,d]>0 ],  load[i,d] <= Q )
# Esta restriccion
@constraint(model, [i in clients, d in days , e in days if demands[i,d]>0 and demands[i,e]>0 ],  time[i,d] - time[i,e] <= L )

optimize!(model)

# Obtener la solución de las variables de decisión
solution = value.(x)
arrival_times = value.(arrival_time)

# Imprimir la ruta de cada vehículo
print("\t")
for d in days
    printstyled("\tDía $d\t\t|"; color = :blue)
end
print("\n")
routes = Dict{Int, Vector{Int}}()
for k in V
    for d in days
        routes[d] = [i for i in C if any(solution[i, j, k, d] > 0.5 for j in C)]
    end
    printstyled("Vehículo $k:\t"; color = :green)
    for d in days
        route = routes[d]
        tabs="\t"

        if isempty(route)
            route = "No hay ruta"
        #Convertir la ruta en strings y unirlas para saber cuantos caracteres ocupa en la terminal
        elseif(length(join(string.(route), ", ")) < 6)         
            tabs="\t\t"
        end
        print("$route$tabs|\t")
    end
    print("\n")
end
println()

routes = Dict{Int, Dict{Int, Vector{Int}}}()

for d in days
    routes[d] = Dict{Int, Vector{Int}}()
    for k in V
        route = [i for i in C if any(solution[i, j, k, d] > 0.5 for j in C)]
        routes[d][k] = route
    end
end

# Mostrar el gráfico
for d in days
    local p = plot()
    title!("Capacitated Vehicle Routing Problem With Consistent Days. Day $d")
    # Nodos de clientes
    scatter!([coords[i][1] for i in C], [coords[i][2] for i in C], label = "Clients", color = :lightblue, markersize = 20, legend = :topleft)

    # define las coordenadas de las rutas
    local pointsArray = []
    # Etiquetas de los clientes
    for i in C
        annotate!(coords[i][1], coords[i][2], text("$i", :black))
    end
    #Añado el deposito visiblemente
    scatter!([10], [12], label = "Depot", color = :blue, markersize = 30, legend = :topleft)
    #Cambio el tamaño para que sea más visible
    plot!(size=(2040,1080))

    # Creo lineas para las rutas que sean visibles.
    for k in V
        route = routes[d][k]
        coordsRoute = [coords[i] for i in route]
        ## If coordsRoute is empty, continue
        if(isempty(coordsRoute)) 
            continue
        end
        pushfirst!(coordsRoute, (10,12))
        push!(coordsRoute, (10,12))

        plot!(coordsRoute, label =  "Vehicle $k", arrow=(:closed, 2.0),linewidth = 5, legend = :topleft, palette = palette(:Set2))
        
    end
    display(p)
    savefig("Solution_Figure_Day_$d.png")
end
