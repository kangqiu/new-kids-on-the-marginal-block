using JuMP 
using HiGHS
using NamedArrays


GenCos = ["GenCo1", "GenCo2", "GenCo3"]
blocks = [1, 2, 3]
d = 145 #demand in MW

gen_capacity = NamedArray(
    [40 20 40;
     50 50 50;
     60 40 50],
    (GenCos, blocks),
    ("GenCos", "blocks")
)

true_ic =  NamedArray(
    [1 4 6;
     2 5 10;
     3 7 9],
    (GenCos, blocks),
    ("GenCos", "blocks")
)


L = 1000 #large constant, such as price cap
α = maximum(true_ic) + 20 #price cap?
gaming_GenCo = "GenCo1"
non_gaming_GenCos = filter(!=(gaming_GenCo), GenCos)
model = Model(HiGHS.Optimizer)

##################
## Variables
#################
@variable(model, prₖ ) #profit of current gaming GenCo
@variable(model, x[GenCos, blocks] ≥ 0) #revenue of each block
@variable(model, Δpr[GenCos, blocks] ≥ 0) #additional profit from marginal block

@variable(model, vᵐᵃˣ[GenCos, blocks], Bin) #vᵐᵃˣ is 1 if generator block is at max capacity
@variable(model, vᵐᶦⁿ[GenCos, blocks], Bin) #vᵐᶦⁿ is 1 if generator block is at min capacity
@variable(model, g[GenCos, blocks] ≥ 0) #generation of each block
@variable(model, y[GenCos, blocks] ≥ 0) #arbitrary block generation
@variable(model, Δg ≥ 0 ) # Amount of generation in the marginal block

#explicit dual variables
@variable(model, μᵐᵃˣ[GenCos, blocks] ≤ 0) #dual for max capacity constraint
@variable(model, μᵐᶦⁿ[GenCos, blocks] ≤ 0) #dual for min capacity constraint
@variable(model, λ) #market clearing price

@variable(model, a[GenCos, blocks] ≥ 0) #price offers

@objective(model, Max, prₖ)
################## 
## 1) GenCo Profit 
#################

# GenCo k (gaming GenCo) profit
profit_k = 0.0
for b in blocks
    profit_k += (x[gaming_GenCo, b] - true_ic[gaming_GenCo, b]) * gen_capacity[gaming_GenCo, b] 
    profit_k += Δpr[gaming_GenCo, b]
end
 
@constraint(model, prₖ == profit_k)

# Marginal block profit
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    Δpr[gen, b] ≤ L *(1- vᵐᵃˣ[gen, b] - vᵐᶦⁿ[gen, b]) #this ensures that Δpr is associated with only the marginal block, otherwise it is 0
)

upper_bound_profit = 0.0
for gen in GenCos
    for b in blocks
        upper_bound_profit += (x[gen, b] - true_ic[gen, b]*vᵐᵃˣ[gen, b]) * gen_capacity[gen, b] 
    end
end
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    Δpr[gen, b] ≤ ((λ - true_ic[gen, b]) * d) - upper_bound_profit + (vᵐᵃˣ[gen, b] + vᵐᶦⁿ[gen, b]) * L)

# linear equivalent (linear equivalent x_ib = λ*vᵐᵃˣ_ib)
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    x[gen, b] ≤ vᵐᵃˣ[gen, b] * α)
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    λ - x[gen, b] ≥ 0)
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    λ - x[gen, b] ≤ (1 - vᵐᵃˣ[gen, b]) * α)

###################
## 2) Power Balance
###################
total_generation = 0.0
for gen in GenCos
    for b in blocks
        total_generation += g[gen, b]
    end
end
@constraint(model, total_generation - d == 0)
@constraint(model, [gen ∈ GenCos, b ∈ blocks], 
        g[gen, b] ≤ gen_capacity[gen, b]) # Generation cannot exceed max capacity if at max

@constraint(model, [gen ∈ GenCos, b ∈ blocks], 
        g[gen, b] == vᵐᵃˣ[gen, b]* gen_capacity[gen, b] + y[gen, b]) #set y to be arbitrary generation when not at max

#linear equivalent y_ib = (1-v_min - v_max) Δg
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    y[gen, b] ≤ (1 - vᵐᵃˣ[gen, b] - vᵐᶦⁿ[gen, b]) * d
)
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    Δg - y[gen, b] ≥ 0)
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    Δg - y[gen, b] ≤ (vᵐᵃˣ[gen, b] + vᵐᶦⁿ[gen, b]) * d
)


###################
## 3) KKT
##################
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    a[gen, b] - λ - μᵐᵃˣ[gen, b] + μᵐᶦⁿ[gen, b] == 0
)

####################
## 4) Binary variables definition
###################
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    -μᵐᵃˣ[gen, b]/L ≤ vᵐᵃˣ[gen, b]
)
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    -μᵐᶦⁿ[gen, b]/L ≤ vᵐᶦⁿ[gen, b]
)

####################
## 5) Complementarity conditions
###################
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    vᵐᵃˣ[gen, b] + vᵐᶦⁿ[gen, b] ≤ 1
)
#only one block marginal
v_marginal = 0
for gen in GenCos
    for b in blocks
        v_marginal += (1 - vᵐᵃˣ[gen, b] - vᵐᶦⁿ[gen, b])
    end
end
@constraint(model, [gen ∈ GenCos, b ∈ blocks],
    v_marginal == 1
)

###################
## 6) Monotonic offers
###################
for gen in GenCos  
    for b in blocks[2:end]
        @constraint(model, a[gen, b] ≥ a[gen, b-1])
    end
end

@constraint(model, λ ≤ α)


####################
## 7) Necessary NE conditions for gaming and non gaming GenCos
####################
@constraint(model, [gen ∈ GenCos, b ∈ blocks], 
    true_ic[gen, b]*vᵐᵃˣ[gen, b] + λ - x[gen, b] ≤ a[gen, b])
@constraint(model, [gen ∈ GenCos, b ∈ blocks], 
    a[gen, b] ≤  true_ic[gen, b]*vᵐᵃˣ[gen, b] + α*(1-vᵐᵃˣ[gen, b]))

@constraint(model, [gen ∈ non_gaming_GenCos, b ∈ blocks], 
    a[gen, b] == true_ic[gen, b])

optimize!(model)


######################
## Results and plotting
######################

# get all bids 
a = value.(model[:a])
# get volume for bids 
g = value.(model[:g])

#check which blocks are dispatched
v_min = value.(model[:vᵐᶦⁿ])
v_max = value.(model[:vᵐᵃˣ])


value.(model[:g]) 
value.(model[:Δg])
