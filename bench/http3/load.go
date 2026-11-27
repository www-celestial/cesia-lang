// The client of bench/http3: a closed-loop load generator over HTTP/1.1, HTTP/2 or HTTP/3, and three other modes.
//
//	load -proto h1|h2|h3 -url URL -c 16 -d 5 -w 1 -insecure          requests/s, p50 and p99 latency of URL
//	load -proto P -url BASE -download BYTES -d 5 -insecure          sequential downloads of BASE/bytes/BYTES
//	load -proto P -url BASE -hold 200 -pid PID[,PID] -insecure      server memory per idle connection (hold.go)
//	load -proto P -url BASE -migrate migrate|reconnect -insecure    address change in the middle of a download (migrate.go)
//
// Each worker of the load mode has its own connection and one request in flight: it sends the next one when the
// previous answer is read whole. The connections are opened one after the other first (-ramp, each with one GET),
// then the clock starts: only the answers that end inside the measured window (after -w, for -d seconds) count. The output is one JSON line; -tag k=v (repeatable) adds string fields to it.
//
// With QLOGDIR set, each QUIC connection writes quic-go's qlog there: flights-svg.py draws what the client received.
package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/quic-go/quic-go"
	"github.com/quic-go/quic-go/http3"
	"github.com/quic-go/quic-go/qlog"
)

type tagList map[string]string

func (t tagList) String() string { return fmt.Sprint(map[string]string(t)) }
func (t tagList) Set(s string) error {
	k, v, ok := strings.Cut(s, "=")
	if !ok {
		return errors.New("tag wants k=v")
	}
	t[k] = v
	return nil
}

var (
	proto    = flag.String("proto", "h1", "h1, h2 or h3")
	target   = flag.String("url", "https://127.0.0.1:8443/", "URL (load mode) or base URL (other modes)")
	conns    = flag.Int("c", 16, "connections, each with one request in flight")
	dur      = flag.Float64("d", 5, "measured seconds")
	warm     = flag.Float64("w", 1, "warm-up seconds, not measured")
	insecure = flag.Bool("insecure", false, "accept any server certificate")
	sni      = flag.String("sni", "localhost", "TLS server name")
	download = flag.Int("download", 0, "download mode: size in bytes of each download of BASE/bytes/SIZE")
	maxN     = flag.Int("n", 1000, "download mode: at most this many downloads")
	reuse    = flag.Bool("reuse", false, "download mode: reuse one connection (default: a new connection per download)")
	hold     = flag.Int("hold", 0, "hold mode: number of idle connections to open")
	pids     = flag.String("pid", "", "hold mode: server PIDs whose VmRSS is summed")
	idle     = flag.Float64("idle", 3, "hold mode: seconds the connections stay idle before the second VmRSS")
	migrate  = flag.String("migrate", "", "migration mode: migrate (QUIC path switch, else a new connection) or reconnect")
	size     = flag.Int("size", 10000000, "migration mode: bytes of the download")
	at       = flag.Int("at", 2000000, "migration mode: bytes read before the address change")
	detect   = flag.Float64("detect", 1, "migration mode: seconds without a byte after which a path is given up")
	ramp     = flag.Bool("ramp", true, "load and hold modes: open the connections one after the other, before the clock starts")
	cidLen   = flag.Int("cidlen", 8, "migration mode: length of the client's QUIC connection IDs")
	expect   = flag.Int64("expect", 5, "load and hold modes: the body length an answer must have (-1: any)")
	tags     = tagList{}
)

func main() {
	flag.Var(tags, "tag", "k=v added to the JSON line (repeatable)")
	flag.Parse()
	var out map[string]any
	var err error
	switch {
	case *download > 0:
		out, err = runDownload()
	case *hold > 0:
		out, err = runHold()
	case *migrate != "":
		out, err = runMigrate()
	default:
		out, err = runLoad()
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "load:", err)
		if out != nil {
			// A run that failed half-way still says how far it went.
			out["error"] = err.Error()
			emit(out)
		}
		os.Exit(1)
	}
	emit(out)
}

func emit(out map[string]any) {
	out["proto"] = *proto
	for k, v := range tags {
		out[k] = v
	}
	if b, err := os.ReadFile("/proc/loadavg"); err == nil {
		out["loadavg"] = strings.Join(strings.Fields(string(b))[:3], " ")
	}
	b, _ := json.Marshal(out)
	fmt.Println(string(b))
}

func tlsConfig() *tls.Config {
	return &tls.Config{InsecureSkipVerify: *insecure, ServerName: *sni}
}

// client is one connection's worth of HTTP: its own transport, so that its requests never share a connection with
// another client's.
type client struct {
	http  *http.Client
	close func()
}

func newClient(p string) (*client, error) {
	switch p {
	case "h1", "h2":
		tr := &http.Transport{
			TLSClientConfig:     tlsConfig(),
			MaxConnsPerHost:     1,
			MaxIdleConnsPerHost: 1,
			MaxIdleConns:        1,
			DisableCompression:  true,
			ForceAttemptHTTP2:   p == "h2",
		}
		ps := new(http.Protocols)
		if p == "h1" {
			ps.SetHTTP1(true)
			tr.TLSNextProto = map[string]func(string, *tls.Conn) http.RoundTripper{}
		} else {
			ps.SetHTTP2(true)
		}
		tr.Protocols = ps
		return &client{&http.Client{Transport: tr}, tr.CloseIdleConnections}, nil
	case "h3":
		tr := &http3.Transport{TLSClientConfig: tlsConfig(), DisableCompression: true,
			QUICConfig: &quic.Config{MaxIdleTimeout: 60 * time.Second, KeepAlivePeriod: 0,
				Tracer: qlog.DefaultConnectionTracer}}
		return &client{&http.Client{Transport: tr}, func() { tr.Close() }}, nil
	}
	return nil, fmt.Errorf("unknown proto %q", p)
}

var wantMajor = map[string]int{"h1": 1, "h2": 2, "h3": 3}

// get sends one GET and reads its body whole; it gives the body's length and the time to its first byte.
func get(ctx context.Context, c *client, url string) (int64, time.Duration, error) {
	t0 := time.Now()
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return 0, 0, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return 0, 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		io.Copy(io.Discard, resp.Body)
		return 0, 0, fmt.Errorf("status %d", resp.StatusCode)
	}
	if resp.ProtoMajor != wantMajor[*proto] {
		return 0, 0, fmt.Errorf("answered in %s", resp.Proto)
	}
	var first time.Duration
	buf := make([]byte, 64<<10)
	var n int64
	for {
		k, err := resp.Body.Read(buf)
		if k > 0 && n == 0 {
			first = time.Since(t0)
		}
		n += int64(k)
		if err == io.EOF {
			return n, first, nil
		}
		if err != nil {
			return n, first, err
		}
	}
}

func seconds(f float64) time.Duration { return time.Duration(f * float64(time.Second)) }

func ms(d time.Duration) float64 { return float64(d.Microseconds()) / 1000 }

// quantile gives the nearest-rank q-quantile of sorted values.
func quantile(sorted []time.Duration, q float64) time.Duration {
	if len(sorted) == 0 {
		return 0
	}
	i := int(q*float64(len(sorted))+0.999999) - 1
	if i < 0 {
		i = 0
	}
	if i >= len(sorted) {
		i = len(sorted) - 1
	}
	return sorted[i]
}

// openClients opens n connections one after the other (each sends GET url once), or all at once when !ramp.
func openClients(n int, url string, ramp bool) ([]*client, int, error) {
	clients := make([]*client, n)
	failed := 0
	var mu sync.Mutex
	var lastErr error
	var wg sync.WaitGroup
	open := func(i int) {
		defer wg.Done()
		c, err := newClient(*proto)
		if err != nil {
			mu.Lock()
			lastErr = err
			mu.Unlock()
			return
		}
		for try := 0; try < 3; try++ {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			var k int64
			k, _, err = get(ctx, c, url)
			cancel()
			if err == nil && *expect >= 0 && k != *expect {
				err = fmt.Errorf("body of %d bytes, not %d", k, *expect)
			}
			if err == nil {
				break
			}
		}
		mu.Lock()
		if err != nil {
			failed++
			lastErr = err
		}
		mu.Unlock()
		clients[i] = c
	}
	for i := range clients {
		wg.Add(1)
		if ramp {
			open(i)
		} else {
			go open(i)
		}
	}
	wg.Wait()
	return clients, failed, lastErr
}

func runLoad() (map[string]any, error) {
	t0 := time.Now()
	clients, failed, err := openClients(*conns, *target, *ramp)
	out := map[string]any{"mode": "load", "url": *target, "c": *conns, "d": *dur, "ramp": *ramp,
		"setup_ms": ms(time.Since(t0)), "setup_failed": failed}
	if err != nil && failed == *conns {
		return out, err
	}
	start := time.Now()
	warmEnd := start.Add(seconds(*warm))
	end := warmEnd.Add(seconds(*dur))
	var mu sync.Mutex
	var all []time.Duration
	var errs int
	var firstErr error
	var wg sync.WaitGroup
	for _, c := range clients {
		if c == nil {
			continue
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			defer c.close()
			ctx, cancel := context.WithDeadline(context.Background(), end.Add(10*time.Second))
			defer cancel()
			var lat []time.Duration
			bad := 0
			var badErr error
			for {
				t0 := time.Now()
				if !t0.Before(end) {
					break
				}
				n, _, err := get(ctx, c, *target)
				if err == nil && *expect >= 0 && n != *expect {
					err = fmt.Errorf("body of %d bytes, not %d", n, *expect)
				}
				t1 := time.Now()
				counted := t1.After(warmEnd) && !t1.After(end)
				if err != nil {
					if t1.After(warmEnd) {
						bad++
						badErr = err
					}
					time.Sleep(10 * time.Millisecond)
					continue
				}
				if counted {
					lat = append(lat, t1.Sub(t0))
				}
			}
			mu.Lock()
			all = append(all, lat...)
			errs += bad
			if badErr != nil && firstErr == nil {
				firstErr = badErr
			}
			mu.Unlock()
		}()
	}
	wg.Wait()
	sort.Slice(all, func(i, j int) bool { return all[i] < all[j] })
	out["requests"] = len(all)
	out["rps"] = float64(len(all)) / *dur
	out["p50_ms"] = ms(quantile(all, 0.50))
	out["p99_ms"] = ms(quantile(all, 0.99))
	out["errors"] = errs
	if firstErr == nil {
		firstErr = err
	}
	if firstErr != nil {
		out["error"] = firstErr.Error()
	}
	return out, nil
}

func bytesURL(base string, n int) string {
	return strings.TrimRight(base, "/") + "/bytes/" + strconv.Itoa(n)
}

// runDownload downloads BASE/bytes/SIZE again and again, one at a time, for -d seconds (at least once, at most -n
// times); each on a new connection unless -reuse, so that its time holds the handshake and the slow start.
func runDownload() (map[string]any, error) {
	url := bytesURL(*target, *download)
	end := time.Now().Add(seconds(*dur))
	var times, firsts []time.Duration
	errs := 0
	var lastErr error
	var shared *client
	for len(times) < *maxN && (len(times) == 0 || time.Now().Before(end)) {
		c := shared
		if c == nil {
			var err error
			if c, err = newClient(*proto); err != nil {
				return nil, err
			}
			if *reuse {
				shared = c
				if _, _, err := get(context.Background(), c, strings.TrimRight(*target, "/")+"/"); err != nil {
					return nil, err
				}
			}
		}
		ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
		t0 := time.Now()
		n, first, err := get(ctx, c, url)
		took := time.Since(t0)
		cancel()
		if !*reuse {
			c.close()
		}
		if err == nil && n != int64(*download) {
			err = fmt.Errorf("got %d bytes", n)
		}
		if err != nil {
			errs++
			lastErr = err
			if errs >= 5 {
				break
			}
			continue
		}
		times = append(times, took)
		firsts = append(firsts, first)
	}
	if shared != nil {
		shared.close()
	}
	out := map[string]any{"mode": "download", "url": url, "bytes": *download, "fresh": !*reuse,
		"downloads": len(times), "errors": errs}
	if lastErr != nil {
		out["error"] = lastErr.Error()
	}
	if len(times) == 0 {
		return out, nil
	}
	sort.Slice(times, func(i, j int) bool { return times[i] < times[j] })
	sort.Slice(firsts, func(i, j int) bool { return firsts[i] < firsts[j] })
	med := quantile(times, 0.5)
	out["ms"] = ms(med)
	out["min_ms"] = ms(times[0])
	out["max_ms"] = ms(times[len(times)-1])
	out["ttfb_ms"] = ms(quantile(firsts, 0.5))
	out["mb_s"] = float64(*download) / med.Seconds() / 1e6
	return out, nil
}
