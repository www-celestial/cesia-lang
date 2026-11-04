orders = [{Status: "paid", Region: "EMEA", Amount: 100},
          {Status: "paid", Region: "APAC", Amount: 300},
          {Status: "refunded", Region: "EMEA", Amount: 999},
          {Status: "paid", Region: "EMEA", Amount: 250},
          {Status: "paid", Region: "AMER", Amount: 50},
          {Status: "paid", Region: "LATAM", Amount: 20}]

defn isTopThree()
  top3 = orders
    then Filter(it.Status == "paid")
    then Group(it.Region, summary = g -> {Total: Sum(g.Amount)})
    then Top(3, by = it.Total)
  Equal(top3, [{Key: "EMEA", Total: 350}, {Key: "APAC", Total: 300}, {Key: "AMER", Total: 50}])
end
