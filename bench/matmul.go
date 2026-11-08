package main

import "fmt"

func matmul(n int) float64 {
	a, b, c := make([]float64, n*n), make([]float64, n*n), make([]float64, n*n)
	for i := 0; i < n; i++ {
		for j := 0; j < n; j++ {
			a[i*n+j] = float64(i+j) * 0.5
			b[i*n+j] = float64(i-j) * 0.25
		}
	}
	for i := 0; i < n; i++ {
		for j := 0; j < n; j++ {
			s := 0.0
			for k := 0; k < n; k++ {
				s += a[i*n+k] * b[k*n+j]
			}
			c[i*n+j] = s
		}
	}
	return c[n+1]
}

func main() { fmt.Printf("%.6f\n", matmul(300)) }
