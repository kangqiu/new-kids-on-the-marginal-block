using JuMP
using HiGHS
using NamedArrays

GenCos = ["GenCo1", "GenCo2", "GenCo3"]
genco1_cap = [40 20 40; 0 0 0;]
genco2_cap = [50 50 50; 0 0 0;]
genco3_cap = [60 40 50; 0 0 0;]

gencos_capacities = zeros(Float64, 3, 2, 3)
gencos_capacities[1, :, :] = genco1_cap
gencos_capacities[2, :, :] = genco2_cap
gencos_capacities[3, :, :] = genco3_cap

genco1_cost = [1 4 6; 0 0 0;]
genco2_cost = [2 5 10; 0 0 0;]
genco3_cost = [3 7 9; 0 0 0;]
gencos_costs = zeros(Float64, 3, 2, 3)
gencos_costs[1, :, :] = genco1_cost
gencos_costs[2, :, :] = genco2_cost
gencos_costs[3, :, :] = genco3_cost

k = 2
D = 145
ngu = 1
ng = length(GenCos)
nb = fill(3, ngu)
α = 9
L = 1e3

G = Dict{Int, Vector{Int}}()
for j in 1:ng
    G[j] = collect(1:ngu)
end

# -----------------------------
# Solve market clearing under one-sided gaming
# -----------------------------
println("\n=======================================")
println(" Market clearing under one-sided gaming")
println(" Demand = $(D) MW")
println(" Gaming GenCo:  ", GenCos[k])
println("=======================================\n")

gaming_model = Model(HiGHS.Optimizer)
set_silent(gaming_model)

# -------------------------------------------------------------
# Variables needed
# -------------------------------------------------------------
a_star = gencos_costs
gmax = gencos_capacities
@variable(gaming_model, a[j in 1:ng, i in G[k], b in 1:nb[i]])
@variable(gaming_model, ν_max[j in 1:ng, i in G[j], b in 1:nb[i]], Bin)
@variable(gaming_model, ν_min[j in 1:ng, i in G[j], b in 1:nb[i]], Bin)
@variable(gaming_model, x[j in 1:ng, i in G[j], b in 1:nb[i]])
@variable(gaming_model, Δpr[j in 1:ng, i in G[j], b in 1:nb[i]])
@variable(gaming_model, g[j in 1:ng, i in G[j], b in 1:nb[i]])         
@variable(gaming_model, y[j in 1:ng, i in G[j], b in 1:nb[i]])         
@variable(gaming_model, μ_max[j in 1:ng, i in G[j], b in 1:nb[i]]) 
@variable(gaming_model, μ_min[j in 1:ng, i in G[j], b in 1:nb[i]]) 
@variable(gaming_model, λ)  
@variable(gaming_model, Δg)    



# -------------------------------------------------------------
# Linearization constraints
# -------------------------------------------------------------
@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    x[j,i,b] >= 0
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    x[j,i,b] <= ν_max[j,i,b] * α
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    λ - x[j,i,b] >= 0
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    λ - x[j,i,b] <= (1 - ν_max[j,i,b]) * α
)



# -------------------------------------------------------------
# Δpr constraints
# -------------------------------------------------------------
@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    0 <= Δpr[j,i,b]
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    Δpr[j,i,b] <= (1 - ν_max[j,i,b] - ν_min[j,i,b]) * L
)

@constraint(gaming_model,
    [l in 1:ng, i in G[l], b in 1:nb[i]],
    Δpr[l,i,b] <= (λ - a_star[l,i,b])*D-
                -(sum((x[l,j,s] - a_star[l,i,b] * ν_max[l,j,s]) * gmax[l,j,s] for j in G[l], s in 1:nb[j]))
                + (ν_max[l,i,b] + ν_min[l,i,b]) * L
)


# -------------------------------------------------------------
# Power Balance
# -------------------------------------------------------------
@constraint(gaming_model,
    sum(g[j,i,b] for j in 1:ng, i in G[j], b in 1:nb[i])  - D == 0
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    0 <= g[j,i,b]
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    g[j,i,b] <= gmax[j,i,b]
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    g[j,i,b] == ν_max[j,i,b] * gmax[j,i,b] + y[j,i,b]
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    0 <= y[j,i,b]
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    y[j,i,b] <= (1 - ν_max[j,i,b] - ν_min[j,i,b]) * D
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    Δg - y[j,i,b] <= (ν_max[j,i,b] + ν_min[j,i,b]) * D
)

@constraint(gaming_model,
    Δg == D -  sum(ν_max[j,i,b] * gmax[j,i,b] for j in 1:ng, i in G[j], b in 1:nb[i])
)

@constraint(gaming_model,
    Δg <= sum((1 - ν_max[j,i,b] - ν_min[j,i,b])*gmax[j,i,b] for j in 1:ng, i in G[j], b in 1:nb[i])
)



#-------------------------------
# KKT Stationarity
# ---------------------------------------
@constraint(gaming_model,
   [j in 1:ng, i in G[j], b in 1:nb[i]],
    a[j,i,b] - λ - μ_max[j,i,b] + μ_min[j,i,b] == 0
)

@constraint(gaming_model,
   [j in 1:ng, i in G[j], b in 1:nb[i]],
    μ_max[j,i,b] <= 0
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    μ_min[j,i,b] <= 0
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    -μ_max[j,i,b]/L <= ν_max[j,i,b]
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    -μ_min[j,i,b]/L <= ν_min[j,i,b]
)


# ---------------------------------------
# Complementary Slackness Constraints
# ---------------------------------------
@constraint(gaming_model,
   [j in 1:ng, i in G[j], b in 1:nb[i]],
    ν_max[j,i,b] + ν_min[j,i,b] <= 1
)

@constraint(gaming_model,
    sum(1 - ν_max[j,i,b] - ν_min[j,i,b] for j in 1:ng, i in G[j], b in 1:nb[i]) == 1
)


# ---------------------------------------
# Monotonic Offers Constraints
# ---------------------------------------

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 2:nb[i]],
    a[j,i,b] >= a[j,i,b-1]
)

@constraint(gaming_model,
   [j in 1:ng, i in G[j], b in 1:nb[i]],
    λ <= α
)

# ---------------------------------------
# NE Offers Constraints for gaming and non-gaming GenCos
# ---------------------------------------
@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    a_star[j,i,b] * ν_max[j,i,b] + λ - x[j,i,b]  <= a[j,i,b]
)

@constraint(gaming_model,
    [j in 1:ng, i in G[j], b in 1:nb[i]],
    a[j,i,b] <= a_star[j,i,b]*ν_max[j,i,b] + α*(1 - ν_max[j,i,b])
)

non_gaming = setdiff(1:ng, [k])
@constraint(gaming_model,
    [j in non_gaming, i in G[j], b in 1:nb[i]],
    a[j,i,b] == a_star[j,i,b]
)


# -------------------------------------------------------------
# Profit expression: pr_k
# -------------------------------------------------------------
@expression(gaming_model,
    pr_k,
    sum((x[k,i,b] - a_star[k,i,b] * ν_max[k,i,b]) * gmax[k,i,b] + Δpr[k,i,b]
         for i in G[k], b in 1:nb[i])
)

@objective(gaming_model, Max, pr_k)

unset_silent(gaming_model)
optimize!(gaming_model)

ts = termination_status(gaming_model)
ps = primal_status(gaming_model)
ds = dual_status(gaming_model)
if termination_status(gaming_model) == MOI.OPTIMAL
    println("Termination Status: $ts.")
    println("Primal status: $ps")
    println("Dual status: $ds")
elseif ts == INFEASIBLE
    println("Problem infeasible or unbounded.")
end


#println("pr_k = ", value(pr_k))
#println("Blocks = ", value(g))
#println("Prices = ", value(a))

println("\nResults:")
println("Clearing Price λ = ", value(λ))

cost = zeros(ng)
revenue = zeros(ng)
profit = zeros(ng)
dispatch = zeros(ng)
for j in 1:ng
    # Sum over all blocks for each GenCo
    for i in G[j]
        for b in 1:nb[i]   # assuming nb is same for all units
            c = value(g[j,i,b]) * value(a_star[j,i,b])
            r = value(g[j,i,b]) * value(λ)
            p = r - c
            d = value(g[j,i,b])
            cost[j] += c
            revenue[j] += r
            profit[j] += p
            dispatch[j] += d
        end
    end
    println("Dispatch GenCo $j = ", dispatch[j], " | Profit GenCo $j = ", profit[j])
end


"""
Varying the price cap α

- For each gaming GenCo, the price cap needs to be set higher than the most expensive true ic of the other GenCos
- If the α is lower, this leads to infeasibilities
- Specifically because of constraint (40)

"""
