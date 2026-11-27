package main

// The migration mode: the client's address changes in the middle of a download of BASE/bytes/SIZE.
//
// After -at bytes, the old UDP socket (or TCP connection) dies at once: nothing it sends leaves, nothing that comes to
// it is read, as when a phone leaves a Wi-Fi network. Then:
//   - h3, -migrate migrate: the client moves the same QUIC connection to a new UDP socket (quic-go's AddPath, Probe,
//     Switch, RFC 9000 section 9), then sends a byte on a new stream so that the server sees the new address. If the
//     server refuses (disable_active_migration), if the probe has no answer in
//     -detect seconds, or if no byte comes in -detect seconds after the switch, the client gives the path up and does
//     what reconnect does.
//   - h3 or h1, -migrate reconnect: a new connection from a new socket asks for BASE/bytes/REMAINING, the bytes not yet
//     read.
//
// continue_ms is the time from the address change to the next byte of the download; total_ms the whole download.

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync/atomic"
	"time"

	"github.com/quic-go/quic-go"
	"github.com/quic-go/quic-go/http3"
)

// deadConn is a UDP socket that can die: once dead, what is sent is dropped and what comes is never read.
type deadConn struct {
	net.PacketConn
	dead atomic.Bool
}

func (d *deadConn) WriteTo(b []byte, a net.Addr) (int, error) {
	if d.dead.Load() {
		return len(b), nil
	}
	return d.PacketConn.WriteTo(b, a)
}

func (d *deadConn) ReadFrom(b []byte) (int, net.Addr, error) {
	for {
		n, a, err := d.PacketConn.ReadFrom(b)
		if err != nil || !d.dead.Load() {
			return n, a, err
		}
	}
}

type progress struct {
	n   int
	err error
	t   time.Time
}

// pump reads body until its end or an error, sending each read on ch, until done closes.
func pump(body io.Reader, ch chan<- progress, done <-chan struct{}) {
	buf := make([]byte, 64<<10)
	for {
		n, err := body.Read(buf)
		select {
		case ch <- progress{n, err, time.Now()}:
		case <-done:
			return
		}
		if err != nil {
			return
		}
	}
}

// readSome reads body synchronously until want bytes are read.
func readSome(body io.Reader, want int) (int, error) {
	buf := make([]byte, 64<<10)
	got := 0
	for got < want {
		n, err := body.Read(buf)
		got += n
		if err != nil {
			if err == io.EOF && got >= want {
				return got, nil
			}
			return got, fmt.Errorf("after %d bytes: %w", got, err)
		}
	}
	return got, nil
}

// drain reads ch until the end of the body; it gives the bytes and the time of the first read.
func drain(ch <-chan progress, timeout time.Duration) (int, time.Time, error) {
	got := 0
	var first time.Time
	for {
		select {
		case p := <-ch:
			if p.n > 0 && first.IsZero() {
				first = p.t
			}
			got += p.n
			if p.err == io.EOF {
				return got, first, nil
			}
			if p.err != nil {
				return got, first, p.err
			}
		case <-time.After(timeout):
			return got, first, errors.New("download stalled")
		}
	}
}

// nudge sends a non-probing packet on the new path, which is what moves the connection there for the server (RFC
// 9000 section 9.2; Switch itself sends nothing while the client has nothing to send): a unidirectional stream of a
// reserved type (0x21, RFC 9114 section 6.2.3), that the server must ignore.
func nudge(qc *quic.Conn) error {
	s, err := qc.OpenUniStream()
	if err != nil {
		return err
	}
	_, err = s.Write([]byte{0x21})
	return err
}

func h3Dial(ctx context.Context, raddr *net.UDPAddr, pc net.PacketConn) (*quic.Conn, *http3.ClientConn, error) {
	tr := &quic.Transport{Conn: pc, ConnectionIDLength: *cidLen}
	tc := tlsConfig()
	tc.NextProtos = []string{http3.NextProtoH3}
	qc, err := tr.Dial(ctx, raddr, tc, &quic.Config{MaxIdleTimeout: 30 * time.Second})
	if err != nil {
		return nil, nil, err
	}
	return qc, (&http3.Transport{DisableCompression: true}).NewClientConn(qc), nil
}

func h3Get(ctx context.Context, cc *http3.ClientConn, u string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return nil, err
	}
	resp, err := cc.RoundTrip(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != 200 {
		resp.Body.Close()
		return nil, fmt.Errorf("status %d", resp.StatusCode)
	}
	return resp, nil
}

func listenUDP() (*net.UDPConn, error) {
	return net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
}

func runMigrate() (map[string]any, error) {
	u, err := url.Parse(*target)
	if err != nil {
		return nil, err
	}
	base := strings.TrimRight(*target, "/")
	if *proto == "h1" {
		if *migrate != "reconnect" {
			return nil, errors.New("TCP has no migration: h1 takes -migrate reconnect")
		}
		return reconnectH1(base)
	}
	if *proto != "h3" {
		return nil, errors.New("migration mode wants h3 or h1")
	}
	raddr, err := net.ResolveUDPAddr("udp", u.Host)
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	out := map[string]any{"mode": "migrate", "how": *migrate, "url": bytesURL(base, *size), "size": *size, "at": *at}
	u1, err := listenUDP()
	if err != nil {
		return out, err
	}
	old := &deadConn{PacketConn: u1}
	t0 := time.Now()
	qc, cc, err := h3Dial(ctx, raddr, old)
	if err != nil {
		return out, err
	}
	resp, err := h3Get(ctx, cc, bytesURL(base, *size))
	if err != nil {
		return out, err
	}
	got, err := readSome(resp.Body, *at)
	if err != nil {
		return out, err
	}
	// The address changes now.
	tChange := time.Now()
	old.dead.Store(true)
	out["before_ms"] = ms(tChange.Sub(t0))
	done := make(chan struct{})
	defer close(done)
	outcome := "reconnect"
	var tNext time.Time
	if *migrate == "migrate" {
		outcome = ""
		ch := make(chan progress, 64)
		go pump(resp.Body, ch, done)
		u2, err := listenUDP()
		if err != nil {
			return out, err
		}
		path, err := qc.AddPath(&quic.Transport{Conn: u2, ConnectionIDLength: *cidLen})
		if err != nil {
			outcome = "no path (" + err.Error() + ")"
		} else {
			pctx, pcancel := context.WithTimeout(ctx, seconds(*detect))
			err = path.Probe(pctx)
			pcancel()
			out["probe_ms"] = ms(time.Since(tChange))
			if err != nil {
				outcome = "probe unanswered (" + err.Error() + ")"
			} else if err = path.Switch(); err != nil {
				outcome = "switch refused (" + err.Error() + ")"
			} else if err = nudge(qc); err != nil {
				outcome = "no stream after switch (" + err.Error() + ")"
			}
		}
		if outcome == "" {
			// The bytes read while probing were in the buffers before the change; the next byte is the first read
			// after the switch.
			tSwitched := time.Now()
			wait := time.After(seconds(*detect))
		next:
			for {
				select {
				case p := <-ch:
					got += p.n
					if p.err != nil && p.err != io.EOF {
						outcome = "error after switch (" + p.err.Error() + ")"
						break next
					}
					if p.t.After(tSwitched) && p.n > 0 {
						tNext = p.t
						outcome = "migrated"
						break next
					}
					if p.err == io.EOF {
						outcome = "migrated"
						tNext = p.t
						break next
					}
				case <-wait:
					outcome = "stalled after switch"
					break next
				}
			}
		}
		if outcome == "migrated" {
			n, _, err := drain(ch, 30*time.Second)
			got += n
			if err != nil {
				return out, fmt.Errorf("after migration: %w", err)
			}
		} else {
			// Drain what the old connection had already buffered: those bytes count, as a client would keep them.
			for {
				select {
				case p := <-ch:
					got += p.n
					continue
				default:
				}
				break
			}
		}
	}
	if outcome != "migrated" {
		qc.CloseWithError(0, "address changed")
		if outcome != "reconnect" {
			outcome += ", then a new connection"
		}
		if got > *size {
			got = *size
		}
		rest := *size - got
		u3, err := listenUDP()
		if err != nil {
			return out, err
		}
		_, cc3, err := h3Dial(ctx, raddr, u3)
		if err != nil {
			return out, err
		}
		resp3, err := h3Get(ctx, cc3, bytesURL(base, rest))
		if err != nil {
			return out, err
		}
		ch3 := make(chan progress, 64)
		go pump(resp3.Body, ch3, done)
		n, first, err := drain(ch3, 30*time.Second)
		if err != nil {
			return out, err
		}
		got += n
		tNext = first
	}
	tEnd := time.Now()
	out["outcome"] = outcome
	out["got"] = got
	out["continue_ms"] = ms(tNext.Sub(tChange))
	out["total_ms"] = ms(tEnd.Sub(t0))
	if got != *size {
		out["error"] = fmt.Sprintf("got %d of %d bytes", got, *size)
	}
	return out, nil
}

// reconnectH1 is the TCP case: the connection is closed after -at bytes, and a new one asks for the rest.
func reconnectH1(base string) (map[string]any, error) {
	out := map[string]any{"mode": "migrate", "how": "reconnect", "url": bytesURL(base, *size), "size": *size, "at": *at}
	var conn atomic.Value
	newH1 := func() *http.Client {
		d := &net.Dialer{}
		tr := &http.Transport{
			TLSClientConfig:    tlsConfig(),
			DisableCompression: true,
			TLSNextProto:       map[string]func(string, *tls.Conn) http.RoundTripper{},
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				c, err := d.DialContext(ctx, network, addr)
				if err == nil {
					conn.Store(c)
				}
				return c, err
			},
		}
		return &http.Client{Transport: tr}
	}
	t0 := time.Now()
	resp, err := newH1().Get(bytesURL(base, *size))
	if err != nil {
		return out, err
	}
	got, err := readSome(resp.Body, *at)
	if err != nil {
		return out, err
	}
	tChange := time.Now()
	conn.Load().(net.Conn).Close()
	// What the TLS layer had already decrypted and buffered still counts.
	buf := make([]byte, 64<<10)
	for {
		n, err := resp.Body.Read(buf)
		got += n
		if err != nil {
			break
		}
	}
	resp.Body.Close()
	if got > *size {
		got = *size
	}
	resp2, err := newH1().Get(bytesURL(base, *size-got))
	if err != nil {
		return out, err
	}
	done := make(chan struct{})
	defer close(done)
	ch := make(chan progress, 64)
	go pump(resp2.Body, ch, done)
	n, first, err := drain(ch, 30*time.Second)
	if err != nil {
		return out, err
	}
	got += n
	out["outcome"] = "reconnect"
	out["got"] = got
	out["continue_ms"] = ms(first.Sub(tChange))
	out["total_ms"] = ms(time.Since(t0))
	if got != *size {
		out["error"] = fmt.Sprintf("got %d of %d bytes", got, *size)
	}
	return out, nil
}
