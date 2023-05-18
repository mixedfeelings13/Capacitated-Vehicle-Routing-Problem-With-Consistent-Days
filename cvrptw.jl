using JuMP
using Gurobi
using Plots
using Random
using Distances
using Colors

# Semilla aleatoria para el paquete Random
Random.seed!()


n = 15 # número de clientes
Q = 8 # capacidad de los vehículos
K = 5 # número de vehículos
M = 1000 # Valor grande para la restricción
# Variables para limpiar
C = 1:n # 1 a n = clientes
V = 1:K # 1 a K = vehículos
days = 1:3

# Número de demanda aleatoria
demands = [[rand(0:8) for i in C] for d in days]
# println(d)
# println(demands)
# si imprime 3 demandas para 3 dias de 15 clientes

# Ventanas de tiempo aleatorias consistentes
earliest_start = [[rand(0:10) for i in C] for d in days]
latest_end = [[earliest_start[d][i] + rand(10:30) for i in C] for d in days]

# Generar coordenadas aleatorias para los clientes
coords = [(rand(1:20), rand(1:20)) for i in C]

# Generar matriz de distancias aleatorias
c = zeros(n, n)  # Inicializar la matriz de distancias

for i in 1:n
    for j in 1:n
        if i != j
            # Generar distancia aleatoria en el rango de 1 a 6
            d = Euclidean()(coords[i], coords[j])
            # Asignar la distancia a la matriz de distancias
            c[i, j] = d
        end
    end
end

# Creación del modelo
model = Model(Gurobi.Optimizer)

# Variable de decisión
@variable(model, x[C, C, V, days], Bin) # Decisión 0 o 1 para x, vehículo va o no va a un cliente
@variable(model, arrival_time[C, days] >= 0)
@variable(model, load[C, days])


# Función objetivo
@objective(model, Min, sum(c[i, j] * x[i, j, k, d] for i in C, j in C, k in V, d in days))

# Restricción de visita única para cada cliente
@constraint(model, visit_once[i in C], sum(x[i, j, k, d] for j in C, d in days, k in V) == 1)
@constraint(model, exit_once[i in C], sum(x[j, i, k, d] for j in C, d in days, k in V) == 1)
# Restricción de capacidad para cada vehículo
@constraint(model, capacity[k in V, d in days], sum(demands[d][i] * x[i, j, k, d] for i in C, j in C) <= Q) 
# Restricción de ventana de tiempo consistente
for d in days
    for i in C
        @constraint(model, sum(x[i, j, k, d] for j in C, k in V) + arrival_time[i,d] <= latest_end[d][i])
        @constraint(model, sum(x[i, j, k, d] for j in C, k in V) + arrival_time[i,d] >= earliest_start[d][i])
    end
end
# Restricción de los días
for d in days
    for i in C
        for j in C
            for k in V 
                @constraint(model, load[j, d] >= load[i, d] + demands[d][i] * x[i, j, k, d] - M * (1 - x[i, j, k, d]))
            end
        end
    end
end


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
    # Nodos de clientes en color rosa
    scatter!([coords[i][1] for i in C], [coords[i][2] for i in C], label = "Clients", color = :hotpink, markersize = 15, legend = :topleft)

    # define las coordenadas de las rutas
    local pointsArray = []
    #Añado el deposito visiblemente
    scatter!([10], [12], label = "Depot", color = :red, markersize = 20, legend = :topleft)
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

        plot!(coordsRoute, label =  "Route $d, Vehicle $k", arrow=(:closed, 2.0),linewidth = 5, legend = :topleft, palette = :rainbow)
    end
    display(p)
    savefig("Solution_Figure_Day_$d.png")
end
