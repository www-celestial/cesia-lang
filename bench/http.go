// The Go reference of tools/http-bench.sh: the same two routes, on the cores GOMAXPROCS gives.
package main

import (
	"encoding/json"
	"net/http"
)

type product struct {
	Id    int
	Name  string
	Price float64
	Tags  []string
}

func main() {
	p := product{7, "bread", 1.25, []string{"fresh", "warm"}}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("Cesia")) })
	http.HandleFunc("/json", func(w http.ResponseWriter, r *http.Request) {
		body, _ := json.Marshal(p)
		w.Header().Set("Content-Type", "application/json")
		w.Write(body)
	})
	http.ListenAndServe("127.0.0.1:19102", nil)
}
