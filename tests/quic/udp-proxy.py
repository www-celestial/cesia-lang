# A UDP relay between one QUIC client and a server, for tests/quic/threats.ce: it counts and inspects what passes, and
# plays the attacker. python3 -I udp-proxy.py LISTEN SERVER, then lines on its standard input, one answer line each:
#   (its first line: the port it listens on)
#   drop          the server's datagrams are counted but no longer given to the client (an address that can't answer)
#   pass          they are given again
#   stats         {"client": bytes from the client, "server": bytes from the server, "types": first bytes of the
#                 server's long headers seen, "scids": the source connection ids of those headers, in hex}
#   flood N       the client's first datagram (its Initial) sent again from N new sockets, as from N addresses
#   spoof         the client's last short-header datagram sent again from a new socket, and the bytes the server sent
#                 to that socket within a second
#   rebind        the relay goes on from a new port, as a NAT that gives the client another address: {"port": the new
#                 one}
#   dcids         the destination connection ids of the server's short headers, in the order first seen, in hex
#   mark          the client's datagrams are recorded from now on (a flight to replay)
#   replay        those datagrams sent again from a new socket, as an attacker who saw them would, and the bytes the
#                 server answered within a second
#   delay MS      the server's datagrams reach the client MS milliseconds later: a path with a round trip
import json, select, socket, sys, time

listen, server = int(sys.argv[1]), ("127.0.0.1", int(sys.argv[2]))
front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
front.bind(("127.0.0.1", listen))
listen = front.getsockname()[1]
back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
back.connect(server)
client = None
dropping = False
stats = {"client": 0, "server": 0, "types": [], "scids": []}
first = None
last_short = None
recording = None
dcids = []
cid_len = None
delay = 0.0
held = []   # (time due, datagram) of the server, in order

def server_packet(d):
    stats["server"] += len(d)
    if d and not d[0] & 0x80 and cid_len and len(d) > 1 + cid_len:
        dcid = d[1:1 + cid_len].hex()
        if dcid not in dcids:
            dcids.append(dcid)
    if d and d[0] & 0x80 and len(d) > 6:
        stats["types"].append(d[0])
        dcid_len = d[5]
        at = 6 + dcid_len
        if at < len(d):
            scid_len = d[at]
            scid = d[at + 1:at + 1 + scid_len].hex()
            if scid and scid not in stats["scids"]:
                stats["scids"].append(scid)

def answer(x):
    sys.stdout.write(json.dumps(x) + "\n")
    sys.stdout.flush()

print(listen, flush=True)
while True:
    now = time.time()
    while held and held[0][0] <= now:
        if client is not None and not dropping:
            front.sendto(held[0][1], client)
        held.pop(0)
    wait = 1.0 if not held else max(0.0, min(1.0, held[0][0] - now))
    ready, _, _ = select.select([front, back, sys.stdin], [], [], wait)
    for r in ready:
        if r is front:
            d, a = front.recvfrom(65536)
            client = a
            stats["client"] += len(d)
            if first is None:
                first = d
                if d and d[0] & 0x80 and len(d) > 6:
                    # The client's own connection id: the source id of its first long header, which the server's short
                    # headers carry as their destination.
                    at = 6 + d[5]
                    cid_len = d[at]
            if recording is not None:
                recording.append(d)
            if d and not d[0] & 0x80:
                last_short = d
            back.send(d)
        elif r is back:
            d = back.recv(65536)
            server_packet(d)
            if delay > 0:
                held.append((time.time() + delay, d))
            elif client is not None and not dropping:
                front.sendto(d, client)
        else:
            line = sys.stdin.readline().split()
            if not line or line[0] == "quit":
                sys.exit(0)
            if line[0] == "drop":
                dropping = True
                answer("ok")
            elif line[0] == "pass":
                dropping = False
                answer("ok")
            elif line[0] == "stats":
                answer(stats)
            elif line[0] == "flood":
                # By batches of 200 sockets: a process may hold 1,024 descriptors.
                got = sent = 0
                for batch in range(0, int(line[1]), 200):
                    socks = []
                    for k in range(200):
                        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                        s.setblocking(False)
                        s.sendto(first, server)
                        sent += len(first)
                        socks.append(s)
                    until = time.time() + 0.2
                    while time.time() < until:
                        rs, _, _ = select.select(socks, [], [], 0.02)
                        for s in rs:
                            try:
                                got += len(s.recv(65536))
                            except OSError:
                                pass
                    for s in socks:
                        s.close()
                answer({"sent": sent, "answered": got})
            elif line[0] == "rebind":
                back.close()
                back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                back.connect(server)
                answer({"port": back.getsockname()[1]})
            elif line[0] == "delay":
                delay = int(line[1]) / 1000.0
                answer("ok")
            elif line[0] == "dcids":
                answer(dcids)
            elif line[0] == "mark":
                recording = []
                answer("ok")
            elif line[0] == "replay":
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                sent = 0
                for d in recording or []:
                    s.sendto(d, server)
                    sent += len(d)
                got = 0
                until = time.time() + 1.0
                while time.time() < until:
                    rs, _, _ = select.select([s], [], [], 0.05)
                    if rs:
                        got += len(s.recv(65536))
                s.close()
                answer({"datagrams": len(recording or []), "sent": sent, "answered": got})
            elif line[0] == "spoof":
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                s.sendto(last_short, server)
                got = 0
                until = time.time() + 1.0
                while time.time() < until:
                    rs, _, _ = select.select([s], [], [], 0.05)
                    if rs:
                        got += len(s.recv(65536))
                s.close()
                answer({"sent": len(last_short), "answered": got})
