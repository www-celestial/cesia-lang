// The quic-go giant of bench/http3: the routes of serve.ce, over HTTPS (HTTP/1.1 and HTTP/2 by ALPN, net/http) on
// TCP PORT and HTTP/3 (quic-go/http3) on UDP PORT.
//
//	quicgo -cert CERT -key KEY -port PORT [-h3=false]
package main

import (
	"bytes"
	"crypto/tls"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"

	"github.com/quic-go/quic-go"
	"github.com/quic-go/quic-go/http3"
)

var block = bytes.Repeat([]byte("x"), 65536)

func sendBytes(w http.ResponseWriter, r *http.Request) {
	n, err := strconv.Atoi(r.PathValue("n"))
	if err != nil || n < 0 {
		http.Error(w, "bad size", http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "text/plain")
	w.Header().Set("Content-Length", strconv.Itoa(n))
	for n > 0 {
		k := min(n, len(block))
		if _, err := w.Write(block[:k]); err != nil {
			return
		}
		n -= k
	}
}

func main() {
	cert := flag.String("cert", "", "certificate (PEM)")
	key := flag.String("key", "", "private key (PEM)")
	port := flag.Int("port", 8444, "TCP and UDP port")
	h3 := flag.Bool("h3", true, "serve HTTP/3 on UDP too")
	flag.Parse()
	pair, err := tls.LoadX509KeyPair(*cert, *key)
	if err != nil {
		log.Fatal(err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		w.Header().Set("Content-Length", "5")
		w.Write([]byte("Cesia"))
	})
	mux.HandleFunc("GET /bytes/{n}", sendBytes)
	addr := fmt.Sprintf("0.0.0.0:%d", *port)
	tcp := &http.Server{Addr: addr, Handler: mux,
		TLSConfig: &tls.Config{Certificates: []tls.Certificate{pair}, NextProtos: []string{"h2", "http/1.1"}}}
	go func() { log.Fatal(tcp.ListenAndServeTLS("", "")) }()
	if *h3 {
		udp := &http3.Server{Addr: addr, Handler: mux,
			TLSConfig:  http3.ConfigureTLSConfig(&tls.Config{Certificates: []tls.Certificate{pair}}),
			QUICConfig: &quic.Config{}}
		go func() { log.Fatal(udp.ListenAndServe()) }()
	}
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	<-stop
}
