-- Sales by city, from a CSV text, with the table module: kepler run examples/stats.k
use frame
use num

sales = frame.FromCsv("city,item,amount
Paris,tea,12.5
Lyon,tea,7
Paris,coffee,30
Nice,coffee,4.5
Lyon,coffee,21
")

totals = frame.GroupBy(["city"], [frame.Agg("total", "amount", Sum), frame.Agg("orders", "amount", Len)], sales)
Print(frame.Show(frame.SortBy("total", totals, descending = true)))
Print("")
amounts = frame.Column("amount", sales)
Print("median", num.Median(amounts), "std", Round(num.Std(1.0 * amounts)))
