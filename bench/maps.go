package main

import (
	"fmt"
	"strconv"
)

func maps(n int) int {
	m := map[string]int{}
	for k := 1; k <= n; k++ {
		m["key"+strconv.Itoa(k)] = k
	}
	total := 0
	for k := 1; k <= n; k++ {
		total += m["key"+strconv.Itoa(k)]
	}
	return total
}

func main() { fmt.Println(maps(500000)) }
