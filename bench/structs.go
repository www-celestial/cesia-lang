package main

import "fmt"

// A particle is a value: each step makes a new one, as the other versions do.
type particle struct{ x, y, vx, vy float64 }

func simulate(n, steps int) float64 {
	ps := make([]particle, n)
	for i := 1; i <= n; i++ {
		ps[i-1] = particle{float64(i), 0.0, 1.0, float64(i) * 0.5}
	}
	dt := 0.001
	for s := 1; s <= steps; s++ {
		for i := 0; i < n; i++ {
			p := ps[i]
			vy := p.vy - 9.81*dt
			ps[i] = particle{p.x + p.vx*dt, p.y + vy*dt, p.vx, vy}
		}
	}
	e := 0.0
	for _, p := range ps {
		e = e + p.x + p.y
	}
	return e
}

func main() { fmt.Printf("%.6f\n", simulate(1000, 5000)) }
