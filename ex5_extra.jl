using JuMP
using HiGHS
using NamedArrays

GenCos = ["GenCo1", "GenCo2", "GenCo3"]
blocks = [1, 2, 3]

marginal_cost = NamedArray(
    [1 4 6;
     2 5 10;
     3 7 9;],
    (GenCos, blocks),
    ("GenCos", "blocks")
)

gen_capacity = NamedArray(
    [40 20 40;
     50 50 50;
     60 40 50;],
    (GenCos, blocks),
    ("GenCos", "blocks")
)

struct Block
    genco::String
    block::Int
    cost::Float64
    capacity::Float64
end

function true_cost_for_q(q, g)
    #=
    demand q for GenCo g by summing marginal costs
    =#
    rem = q
    total = 0.0
    for b in blocks
        if rem <= 0
            break
        end
        use = min(gen_capacity[g, b], rem)
        total += use * marginal_cost[g, b]
        rem -= use
    end
    total
end

# -----------------------------
# Solve LP market-clearing for each demand
# -----------------------------
println("\n=======================================")
println(" Market clearing under perfect competition")
println(" Flexible Demand MW")
println("=======================================\n")

# set up model
# tentative price 
λ0 = 2.
# tentative starting demand
D0 = 145.0
# elasticity 
ϵ = 0.05

# Initialize variables that will be used after the loop
d = D0
model = nothing
x = nothing
balance = nothing

for iter in 1:50
    global model, x, balance, d, λ0, λ
    
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    
    x = @variable(model, 0 <= x[g in GenCos, b in blocks] <= gen_capacity[g, b])
    balance = @constraint(model, sum(x[g, b] for g in GenCos, b in blocks) == d)
    @objective(model, Min, sum(marginal_cost[g, b] * x[g, b] for g in GenCos, b in blocks))
    
    optimize!(model)
    
    λ = dual(balance)
    d_new = d*(1 - ϵ * (λ-λ0) /λ0)
    
    λ0 = λ
    d = d_new
    println("Iter $iter: λ = $(round(λ, digits=4)), Demand = $(round(d, digits=4))")
end

# check results
ts = termination_status(model)
ps = primal_status(model)
ds = dual_status(model)

if termination_status(model) == MOI.OPTIMAL
    println("\nTermination Status: $ts")
    println("Primal status: $ps")
    println("Dual status: $ds")
elseif termination_status(model) == MOI.INFEASIBLE_OR_UNBOUNDED
    println("Problem infeasible or unbounded.")
end

total_cost = objective_value(model)
clearing_price = dual(balance)  # Fixed: was "demand_const" which didn't exist

# Compute dispatch, revenues, costs, profits
dispatch_by_gen = Dict(g => sum(value(x[g, b]) for b in blocks) for g in GenCos)
revenues = Dict(g => clearing_price * dispatch_by_gen[g] for g in GenCos)
costs = Dict(g => true_cost_for_q(dispatch_by_gen[g], g) for g in GenCos)
profits = Dict(g => revenues[g] - costs[g] for g in GenCos)

# Print results
println("\nTotal procurement cost (objective): ", round(total_cost, digits=4), " €")
println("Market clearing price: ", round(clearing_price, digits=4), " €/MWh\n")

println("Dispatch by GenCo:")
for g in GenCos
    println("  $(g): ", round(dispatch_by_gen[g], digits=4), " MW")
end

println("\nFinancial results by GenCo:")
for g in GenCos
    println("  $(g): revenue=$(round(revenues[g], digits=2)) €  cost=$(round(costs[g], digits=2)) €  profit=$(round(profits[g], digits=2)) €")
end
