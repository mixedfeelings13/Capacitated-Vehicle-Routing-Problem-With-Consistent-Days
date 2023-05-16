using JuMP
using Gurobi
using Plots
using Random
using Distances
using Colors

# Semilla aleatoria para el paquete Random
Random.seed!()

# @constraint(model, time_window[i in C, j in C, k in V], earliest_start[i] <= sum(x[i, j, k]) <= latest_end[i])

n = 15 # número de clientes
Q = 10 # capacidad de los vehículos
K = 10 # número de vehículos
# Variables para limpiar
C = 1:n # 1 a n = clientes
V = 1:K # 1 a K = vehículos

# Número de demanda aleatoria
demands = [rand(1:10) for i in C]

# Tiempo para realizar el servicio aleatorio
service_times = [rand(1:5) for i in C]

# Ventanas de tiempo aleatorias consistentes
earliest_start = [rand(0:10) for i in C]
latest_end = [earliest_start[i] + rand(10:30) for i in C]



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
@variable(model, x[C, C, V], Bin) # Decisión 0 o 1 para x, vehículo va o no va a un cliente
@variable(model, tiempo_llegada[C,V] >= 0)

# Función objetivo
@objective(model, Min, sum(c[i, j] * x[i, j, k] for i in C, j in C, k in V))

# Restricción de visita única para cada cliente
@constraint(model, visit_once[i in C], sum(x[i, j, k] for j in C, k in V) == 1)
# Restricción de capacidad para cada vehículo
@constraint(model, capacity[k in V], sum(demands[i] * x[i, j, k] for i in C, j in C) <= Q)
# Restricción de ventana de tiempo consistente
for k in V
    for i in C
        @constraint(model, sum(service_times[i]*x[i,j,k] for j in C) + tiempo_llegada[i,k] <= latest_end[i])
        @constraint(model, sum(service_times[i]*x[i,j,k] for j in C) + tiempo_llegada[i,k] >= earliest_start[i])
    end
end
# Restricción de fin en el depósito para cada vehículo
@constraint(model, depot_end[k in V], sum(x[j, 1, k] for j in C) == 1)
println(depot_end)
# Ventanas de tiempo prohibidas
for k in V
    for i in C
        # Generar una probabilidad aleatoria para determinar si se prohíbe la visita en este cliente
        prob_prohibir = rand()
        if prob_prohibir < 0.3
            # Definir una ventana de tiempo prohibida para el cliente i en el vehículo k
            @constraint(model, sum(service_times[i]*x[i,j,k] for j in C) + tiempo_llegada[i, k] <= latest_end[i] - 5)
            @constraint(model, sum(service_times[i]*x[i,j,k] for j in C) + tiempo_llegada[i, k] >= earliest_start[i] + 5)
        end
    end
end


optimize!(model)

# Obtener la solución de las variables de decisión
solution = value.(x)
tiempos_llegada = value.(tiempo_llegada)

# Imprimir la ruta de cada vehículo
for k in V
    println("Ruta del vehículo $k:")
    route = [i for i in C if any(solution[i, j, k] > 0.5 for j in C)]
    println(route)
    println()
end
# Definir la información en plots
routes =  Dict{Int, Vector{Int}}()

for k in V
    route = [i for i in C if any(solution[i, j, k] > 0.5 for j in C)]
    routes[k] = route
end

# Mostrar el gráfico
p = plot()

title!("Capacitated Vehicle Routing Problem With Consistent Time Windows")
# Nodos de clientes en color rosa
scatter!([coords[i][1] for i in C], [coords[i][2] for i in C], label = "Clients", color = :hotpink, markersize = 15, legend = :topleft)

# define las coordenadas de las rutas
pointsArray = []
#Añado el deposito visiblemente
scatter!([10], [12], label = "Depot", color = :red, markersize = 20, legend = :topleft)
#Cambio el tamaño para que sea más visible
plot!(size=(2040,1080))
# Creo lineas para las rutas que sean visibles.
for k in V
    route = routes[k]
    coordsRoute = [coords[i] for i in route]
    pushfirst!(coordsRoute, (10,12))
    push!(coordsRoute, (10,12))
    plot!(coordsRoute, label = "Route $k", linewidth = 5, legend = :topleft, palette = :rainbow)
end
display(p)
savefig("Solution_Figure.pdf")