#!/usr/bin/env bash
# setup.sh: builds or fetches what the measures of bench/http3 need, all of it under $BENCH ($HOME/.cache/quic/bench):
# the load generator and the quic-go server (Go, this folder's module), Caddy 2 (go install), nginx 1.27 with HTTP/3
# (the files of the docker image nginx:1.27-alpine, run through its musl loader), OpenSSL's QUIC alone (openssl/, with
# the system's OpenSSL 3.6 or later), ngtcp2's example server (NGTCP2 and its libev, built over the system's OpenSSL
# and nghttp3), the files of /bytes/N, serve-tcp.ce (serve.ce without HTTP/3, for the A/B with main), Cesia of main
# (MAIN_COMMIT), the two configs.
set -euo pipefail
. "$(dirname "$0")/env.sh"
MAIN_COMMIT=${MAIN_COMMIT:-dcc524e4}
export GOPATH=$BENCH/go GOCACHE=$BENCH/gocache GOFLAGS=-modcacherw PATH=$(dirname "$GO"):$PATH
mkdir -p "$BENCH/bin" "$BENCH/www/bytes" "$RUN/nginx/logs" "$RUN/nginx/tmp" "$RUN/caddy"

(cd "$HERE" && go build -o "$BENCH/bin/load" . && go build -o "$BENCH/bin/quicgo" ./quicgo)

[ -x "$BENCH/bin/caddy" ] || GOBIN=$BENCH/bin go install github.com/caddyserver/caddy/v2/cmd/caddy@latest

cc -O2 -o "$BENCH/bin/bare-h3" "$HERE/openssl/bare-h3.c" -lssl -lcrypto -lpthread
cc -O2 -o "$BENCH/bin/bare-get" "$HERE/openssl/bare-get.c" -lssl -lcrypto

NGTCP2=${NGTCP2:-1.26.0} LIBEV=${LIBEV:-4.33}
if [ ! -x "$BENCH/bin/ngtcp2-server" ]; then
  src=$BENCH/ngtcp2
  mkdir -p "$src"
  curl -sSfL "https://github.com/ngtcp2/ngtcp2/releases/download/v$NGTCP2/ngtcp2-$NGTCP2.tar.xz" | tar -xJ -C "$src"
  curl -sSfL "http://dist.schmorp.de/libev/libev-$LIBEV.tar.gz" | tar -xz -C "$src"
  (cd "$src/libev-$LIBEV" && ./configure -q --prefix="$src/prefix" --disable-shared && make -s && make -s install)
  (cd "$src/ngtcp2-$NGTCP2" && ./configure -q --with-openssl --with-libev --with-libnghttp3 --disable-shared \
    LIBEV_CFLAGS="-I$src/prefix/include" LIBEV_LIBS="-L$src/prefix/lib -lev -lm" && make -s)
  cp "$src/ngtcp2-$NGTCP2/examples/osslserver" "$BENCH/bin/ngtcp2-server"
fi

if [ ! -x "$NGX/usr/sbin/nginx" ]; then
  mkdir -p "$NGX"
  cid=$(docker create nginx:1.27-alpine)
  docker export "$cid" | tar -x -C "$NGX"
  docker rm "$cid" >/dev/null
fi

for n in 1000000 10000000; do
  [ -f "$BENCH/www/bytes/$n" ] || head -c "$n" /dev/zero | tr '\0' x >"$BENCH/www/bytes/$n"
done

# serve.ce without std/http3 and std/quic, that main can run too.
grep -v -e '^use std/http3' -e '^use std/quic' -e '^  h3 = ' "$HERE/serve.ce" |
  sed -e 's/, http3 = h3//' >"$BENCH/serve-tcp.ce"

if [ ! -x "$CESIA_MAIN" ]; then
  src=$(dirname "$(dirname "$(dirname "$(dirname "$(dirname "$CESIA_MAIN")")")")")/main-src
  mkdir -p "$src"
  git -C "$HERE" archive "$MAIN_COMMIT" | tar -x -C "$src"
  (cd "$src" && dune build --build-dir "$(dirname "$(dirname "$(dirname "$(dirname "$CESIA_MAIN")")")")" ./src/bin/main.exe)
fi

cat >"$RUN/Caddyfile" <<EOF
{
	admin off
	persist_config off
	auto_https disable_redirects
	skip_install_trust
	storage file_system $RUN/caddy/data
	log default {
		output discard
	}
	servers {
		protocols h1 h2 h3
	}
}
https://:${PORT[caddy]} {
	tls $CERTS/cert.pem $CERTS/key.pem
	handle / {
		respond "Cesia" 200
	}
	handle /bytes/* {
		root * $BENCH/www
		file_server
	}
}
EOF

cat >"$RUN/nginx.conf" <<EOF
daemon off;
master_process on;
worker_processes 4;
pid $RUN/nginx/nginx.pid;
error_log $LOGS/nginx-error.log warn;
events {
    worker_connections 4096;
}
http {
    access_log off;
    default_type text/plain;
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 300s;
    keepalive_requests 100000000;
    client_body_temp_path $RUN/nginx/tmp/body;
    proxy_temp_path $RUN/nginx/tmp/proxy;
    fastcgi_temp_path $RUN/nginx/tmp/fastcgi;
    uwsgi_temp_path $RUN/nginx/tmp/uwsgi;
    scgi_temp_path $RUN/nginx/tmp/scgi;
    ssl_protocols TLSv1.3;
    ssl_certificate $CERTS/cert.pem;
    ssl_certificate_key $CERTS/key.pem;
    server {
        listen ${PORT[nginx]} ssl;
        listen ${PORT[nginx]} quic reuseport;
        http2 on;
        http3 on;
        location = / {
            return 200 "Cesia";
        }
        location /bytes/ {
            root $BENCH/www;
        }
    }
}
EOF
echo "setup done in $BENCH"
