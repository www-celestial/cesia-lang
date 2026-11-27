package main

// The hold mode: the server's memory per idle connection. It reads the VmRSS of the server (the sum over -pid),
// opens -hold connections (one after the other, unless -ramp=false), each sends GET BASE/ once and then stays open
// and idle, waits -idle seconds, reads VmRSS
// again, and gives (after - before) / N.

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

func rssKB(list string) (int64, error) {
	var sum int64
	for _, p := range strings.Split(list, ",") {
		f, err := os.Open("/proc/" + strings.TrimSpace(p) + "/status")
		if err != nil {
			return 0, err
		}
		s := bufio.NewScanner(f)
		for s.Scan() {
			if v, ok := strings.CutPrefix(s.Text(), "VmRSS:"); ok {
				k, _ := strconv.ParseInt(strings.TrimSuffix(strings.TrimSpace(v), " kB"), 10, 64)
				sum += k
			}
		}
		f.Close()
	}
	return sum, nil
}

func runHold() (map[string]any, error) {
	if *pids == "" {
		return nil, fmt.Errorf("hold mode wants -pid")
	}
	before, err := rssKB(*pids)
	if err != nil {
		return nil, err
	}
	url := strings.TrimRight(*target, "/") + "/"
	t0 := time.Now()
	clients, failed, lastErr := openClients(*hold, url, *ramp)
	opened := time.Since(t0)
	time.Sleep(seconds(*idle))
	after, err := rssKB(*pids)
	if err != nil {
		return nil, err
	}
	for _, c := range clients {
		if c != nil {
			c.close()
		}
	}
	out := map[string]any{"mode": "hold", "url": url, "n": *hold, "open": *hold - failed, "open_ms": ms(opened), "ramp": *ramp,
		"idle_s": *idle, "before_kb": before, "after_kb": after,
		"per_conn_kb": float64(after-before) / float64(*hold)}
	if lastErr != nil {
		out["error"] = lastErr.Error()
	}
	return out, nil
}
