using NamedArrays

GenCos = ["GenCo1", "GenCo2", "GenCo3", "GenCo4"]
blocks = [1, 2]

true_cost = NamedArray(
    [10 40;
     20 50;
     30 70;
     60 80],
    (GenCos, blocks),
    ("GenCo", "Block")
)

gen_capacity = NamedArray(
    [10 10;
     10 10;
     20 10;
     10 10],
    (GenCos, blocks),
    ("GenCo", "Block")
)

demands = [35.0, 55.0]

struct Block
    genco::String
    block::Int
    price::Float64
    capacity::Float64
end

function supply_stack(price,genco)
    #=
    creates sorted list of blocks with true marginal costs for non-gaming GenCos
    and bid price for gaming GenCo
    =#
    blocks_list = Block[]
    for g in GenCos, b in blocks
        p = g == genco ? price : true_cost[g,b]
        push!(blocks_list, Block(g, b, p, gen_capacity[g,b]))
    end
    sort(blocks_list, by = x -> x.price)
end


function compute_cost(q,genco)
    #=
    computes true cost for gaming GenCo to produce quantity q
    uses cheap blocks first
    =#
    rem = q
    total = 0.0
    for b in blocks
        if rem <= 0
            break
        end
        use = min(gen_capacity[genco,b], rem)
        total += use * true_cost[genco,b]
        rem -= use
    end
    total
end


function clear_market(D, price,genco)
    #=
    clear market for demand D given gaming GenCo's bid price
    returns profit, market clearing price, quantity allocated to all GenCos
    =#
    gen = genco
    stack = supply_stack(price,gen)
    remaining = D
    dispatch = Dict(g => 0.0 for g in GenCos)
    price = 0.0

    for blk in stack
        if remaining <= 0; break; end
        alloc = min(blk.capacity, remaining)
        dispatch[blk.genco] += alloc
        remaining -= alloc
        price = blk.price
    end

    quantity = dispatch[genco]
    revenue = quantity * price
    cost = compute_cost(quantity,gen)
    profit = revenue - cost

    return profit, price, quantity
end


function search_NE_bid(D,genco)
    #=
    iterate over possible bid prices (1 to 100 €/MWh) and return the one
    that yields the highest profit for the gaming GenCo and is a NE
    =#
    best_profit = -Inf
    best_bid_price = -1
    best_clearing_price = 0.0
    best_quantity = 0.0

    for p in 1:100
        profit, λ, quantity = clear_market(D, p,genco)
        if profit > best_profit
            best_profit = profit
            best_bid_price = p
            best_clearing_price = λ
            best_quantity = quantity
        end
    end

    return best_bid_price, best_profit, best_clearing_price, best_quantity
end



# ---------------------------------------
# Run
# ---------------------------------------
gamer = "GenCo2"
for D in demands
    println("\n=========================")
    println(" Gaming GenCo: $gamer")
    println(" Demand = $D")
    println("=========================")

    best_bid, best_profit, λ, quantity = search_NE_bid(D,gamer)

    println("$gamer NE-bid: $best_bid €/MWh")
    println("Resulting market price: $λ €/MWh")
    println("$gamer dispatch: $quantity MW")
    println("$gamer profit: $best_profit")
end
