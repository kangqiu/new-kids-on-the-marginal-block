using JuMP
using HiGHS
using NamedArrays

GenCos = [
	"GenCo1",
	"GenCo2",
	"GenCo3",
	"GenCo4",
]

blocks = [1,2]

ic = NamedArray(
	[10 40;
	 20 50;
	 30 70;
	 60 80;],
	(GenCos, blocks),
	("GenCos", "Blocks")
)

gen_capacity = NamedArray(
	[10 10;
	 10 10;
	 20 10;
	 10 10;],
	(GenCos, blocks),
	("GenCos", "Blocks")
)

demand = [35,55]

struct Block
	genco::String
	block::Int
	cost::Float64
	capacity::Float64
end

function supply_stack(price, genco)
	#=
	Compute profit of a GenCo
        =#
	bl = Block[]
	for g in GenCos, b in blocks
		p = g == genco ? price : ic[g,b]
		push!(bl, Block(g,b,p,gen_capacity[g,b]))
	end
	sort(bl, by = x -> x.cost)
end

function compute_cost(g, q)
	#=
	compute cost for GenCo g to produce quantity q
	=#
	total = 0.
	rem = q
	
	for b in blocks
		if rem <= 0
			break
		end
		use = min(gen_capacity[g,b], rem)
		total += use*ic[g,b]
		rem -= use
	end
	return total
end

function clear_market(d, price, genco)
	#=
	clear market demand with the gaming price.
	=#

	remaining = d
	stack = supply_stack(price, genco)
	dispatch = Dict(g => 0. for g in GenCos)
	price = 0.

	for blk in stack
		if remaining <= 0
			break
		end
		alloc = min(blk.capacity, remaining)
		dispatch[blk.genco] += alloc
		remaining -= alloc
		price = blk.cost
	end

	quantity = dispatch[genco]
	revenue = quantity*price
	cost = compute_cost(genco, quantity)
	profit = revenue - cost
	return quantity, price, profit
end

function search_NE_bid(d, genco)
	#=
	grid search for the gaming GENCO to find optimum profit
	=#
	best_profit = -Inf
	best_bid_price = -1.
	best_clearing_price = 0.
	best_quantity = 0.

	for p in 1:100
            quantity, λ , profit = clear_market(d, p, genco)
            if profit > best_profit
                best_profit = profit
                best_bid_price = p
                best_clearing_price = λ
                best_quantity = quantity
            end
	end
    return best_bid_price, best_profit, best_clearing_price, best_quantity
end

gamer = "GenCo2"
for d in demand
    println("\n=========================")
    println(" Gaming GenCo: $gamer")
    println(" Demand = $d")
    println("=========================")

    best_bid, best_profit, λ, quantity = search_NE_bid(d,gamer)

    println("$gamer NE-bid: $best_bid €/MWh")
    println("Resulting market price: $λ €/MWh")
    println("$gamer dispatch: $quantity MW")
    println("$gamer profit: $best_profit")
end
