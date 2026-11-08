package main

import (
	"fmt"
	"os"
	"strconv"
	"sync"
)

// COUNT goroutines park on one gate, then all end once it opens: what tools/fiber-size.sh measures for Cesia.
func main() {
	count, _ := strconv.Atoi(os.Args[1])
	gate := make(chan struct{})
	var done sync.WaitGroup
	for i := 0; i < count; i++ {
		done.Add(1)
		go func() {
			<-gate
			done.Done()
		}()
	}
	close(gate)
	done.Wait()
	fmt.Println(count)
}
