using JuMP 
using HiGHS
using NamedArrays


GenCos = ["GenCo1", "GenCo2", "GenCo3"]
blocks = [1, 2, 3]

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

model = Model(HiGHS.Optimizer)

