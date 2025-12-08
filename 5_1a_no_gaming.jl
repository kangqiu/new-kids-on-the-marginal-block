using JuMP 
using HiGHS
using NamedArrays


GenCos = ["GenCo1", "GenCo2", "GenCo3", "GenCo4"]
blocks = [1, 2]

marginal_cost = NamedArray(
    [10 40;
     20 50;
     30 70;
     60 80],
    (GenCos, blocks),
    ("GenCos", "blocks")
)

gen_capacity =  NamedArray(
    [10 10;
     10 10;
     20 10;
     10 10],
    (GenCos, blocks),
    ("GenCos", "blocks")
)

struct Block
    genco::String
    block::Int
    cost::Float64
    capacity::Float64
end

demand = [35, 55]



function supply_stack()
    #=
    sort GenCo blocks in ascending order of cost
    =#
    bl = Block[]
    for g in GenCos, b in blocks
        push!(bl, Block(g, b, marginal_cost[g,b], gen_capacity[g,b]))
    end
    sort(bl, by = x -> x.cost)
end


function compute_cost(g, q)
    #=
    compute cost for GenCo g to produce quantity q
    =#
    total = 0.0
    rem = q

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


function clear_market(D)
    #=
    clear market for demand D
    =#
    
    remaining = D
    dispatch = Dict(g => 0.0 for g in GenCos)
    price = 0.0

    for blk in stack
        if remaining <= 0
            break
        end

        alloc = min(blk.capacity, remaining)
        dispatch[blk.genco] += alloc
        remaining -= alloc
        price = blk.cost
    end

    revenue = Dict(g => dispatch[g] * price for g in GenCos)
    cost = Dict(g => compute_cost(g, dispatch[g]) for g in GenCos)
    profit = Dict(g => revenue[g] - cost[g] for g in GenCos)

    return price, dispatch, revenue, cost, profit
end

# -----------------------------
# Run
# -----------------------------
stack = supply_stack()
for D in (35, 55)
    println("\n===============================")
    println(" Demand = $D")
    println("===============================")

    price, dispatch, revenue, cost, profit = clear_market(D)

    println("Market price: $price\n")

    println("Dispatch:")
    for g in GenCos
        println("  $g : $(dispatch[g])")
    end

    println("\nProfits:")
    for g in GenCos
        println("  $g : revenue=$(revenue[g]), cost=$(cost[g]), profit=$(profit[g])")
    end
end
