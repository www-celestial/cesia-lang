package main

import "fmt"

func mandel(w, h, maxit int) int {
	total := 0
	for py := 0; py <= h-1; py++ {
		y0 := 2.0*float64(py)/float64(h) - 1.0
		for px := 0; px <= w-1; px++ {
			x0 := 3.0*float64(px)/float64(w) - 2.0
			x, y, x2, y2, it := 0.0, 0.0, 0.0, 0.0, 0
			for x2+y2 < 4.0 && it < maxit {
				y = 2.0*x*y + y0
				x = x2 - y2 + x0
				x2 = x * x
				y2 = y * y
				it++
			}
			total += it
		}
	}
	return total
}

func main() { fmt.Println(mandel(600, 400, 200)) }
