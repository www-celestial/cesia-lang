package main

import "fmt"

// Calls through a list of functions. Go has no value of changing kind: the numbers are all floats here.
func dyn(n int) float64 {
	ops := []func(a, b float64) float64{
		func(a, b float64) float64 { return a + b },
		func(a, b float64) float64 { return a*0.5 + b },
	}
	xs := []float64{1, 2.5, 3, 4.5}
	total := 0.0
	for i := 1; i <= n; i++ {
		f := ops[i%2]
		x := xs[i%4]
		total = f(total, x)
		if total > 1000000.0 {
			total = total / 2
		}
	}
	return total
}

func main() { fmt.Printf("%.6f\n", dyn(10000000)) }
