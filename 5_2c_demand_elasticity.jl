using JuMP 
using HiGHS
using NamedArrays
using Ipopt


GenCos = ["GenCo1", "GenCo2", "GenCo3"]
blocks = [1, 2, 3]

marginal_cost = NamedArray(
    [1 4 6;
     2 5 10;
     3 7 9],
    (GenCos, blocks),
    ("GenCos", "blocks")
)

gen_capacity =  NamedArray(
    [40 20 40;
     50 50 50;
     60 40 50],
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
    cover demand q for GenCo g by summing up marginal costs of blocks used
    starting with cheaopest blocks first
    =#
    rem = q
    total = 0.0
    for b in blocks
        if rem <= 0
            break
        end
        use = min(gen_capacity[g,b], rem)
        total += use * marginal_cost[g,b]
        rem -= use
    end
    return total
end


# -----------------------------
# Solve LP market-clearing for each demand
# -----------------------------
println("\n=======================================")
println(" Market clearing under perfect competition")
println(" Demand = $(demand) MW")
println("=======================================\n")



# ----- elasticity parameters -----
ε  = -0.05
D0 = 145
λ0 = 3

max_iter = 50
tol = 1e-3

demand = D0    # initial guess

# Update the RHS of the demand constraint
mdl = Model(HiGHS.Optimizer)
set_silent(mdl)

# decision variable q_ib (with boundary constraint)
@variable(mdl, 0 <= x[g in GenCos, b in blocks] <= gen_capacity[g,b])

# demand balance
demand_constr = @constraint(mdl,sum(x[g,b] for g in GenCos, b in blocks) == demand)

# total cost
@objective(mdl, Min,sum(marginal_cost[g,b] * x[g,b] for g in GenCos, b in blocks))


for iter in 1:max_iter

    if iter == 1
        global λ_prev = λ0
    end
    

    optimize!(mdl)
    
    λ = dual(demand_constr)
    
    # Update demand from price elasticity
    #new_demand = D0 * (λ / λ0)^ε
    new_demand = normalized_rhs(demand_constr) * (1 - ε*(λ - λ_prev))
    

    println("Iter=$iter   λ=$(round(λ,digits=3))   Demand=$(round(normalized_rhs(demand_constr),digits=3))     New Demand=$(round(new_demand,digits=3))")
    
    
    if abs(new_demand - normalized_rhs(demand_constr)) < tol
        println("Converged.")
        break
    end

    if iter < max_iter
        set_normalized_rhs(demand_constr, new_demand)
        λ_prev = λ
    end

end

ts = termination_status(mdl)
ps = primal_status(mdl)
ds = dual_status(mdl)
if termination_status(mdl) == MOI.OPTIMAL
    println("Termination Status: $ts.")
    println("Primal status: $ps")
    println("Dual status: $ds")
elseif termination_status(mdl) == MOI.INFEASIBLE_OR_UNBOUNDED
    println("Problem infeasible or unbounded.")
end

total_cost = objective_value(mdl)
clearing_price = dual(demand_constr)

# Compute dispatch, revenues, costs, profits
dispatch_by_gen = Dict(g => sum(value(x[g,b]) for b in blocks) for g in GenCos)
revenues = Dict(g => clearing_price * dispatch_by_gen[g] for g in GenCos)
costs = Dict(g => true_cost_for_q(dispatch_by_gen[g], g) for g in GenCos)
profits = Dict(g => revenues[g] - costs[g] for g in GenCos)

# Print results
println("\nTotal procurement cost (objective): ", round(total_cost, digits=4), " €")
println("Market clearing price: ", round(clearing_price, digits=4), " €/MWh")
println("New Demand = ", round(normalized_rhs(demand_constr), digits=4), " MW\n")

println("Dispatch by GenCo:")
for g in GenCos
    println("  $(g): ", round(dispatch_by_gen[g], digits=4), " MW")
end

println("\nFinanicial results by GenCo:")
for g in GenCos
    println("  $(g): revenue=$(round(revenues[g],digits=2)) €  cost=$(round(costs[g],digits=2)) €  profit=$(round(profits[g],digits=2)) €")
end