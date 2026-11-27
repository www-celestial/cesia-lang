/* bare-get: the OpenSSL QUIC client alone (guide quic-client-block), N downloads one after the other, each on a new
 * connection, of what bare-h3 sends; prints one JSON line per download: ms (dial to the last byte), bytes.
 *   bare-get HOST PORT N
 */
#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/quic.h>
#include <openssl/ssl.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static double now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: bare-get HOST PORT N\n");
        return 2;
    }
    static const unsigned char alpn[] = {2, 'h', '3'};
    static const unsigned char settings[] = {0x00, 0x04, 0x00};
    /* HEADERS: RIC 0, Base 0, :method GET (17), :scheme https (23), :path / (1). */
    static const unsigned char get[] = {0x01, 0x05, 0x00, 0x00, 0xd1, 0xd7, 0xc1};
    SSL_CTX *ctx = SSL_CTX_new(OSSL_QUIC_client_method());
    SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);
    int n = atoi(argv[3]);
    static unsigned char buf[65536];
    for (int i = 0; i < n; i++) {
        double t0 = now_ms();
        int fd = socket(AF_INET, SOCK_DGRAM, 0);
        struct sockaddr_in sa = {.sin_family = AF_INET, .sin_port = htons(atoi(argv[2]))};
        inet_pton(AF_INET, argv[1], &sa.sin_addr);
        connect(fd, (struct sockaddr *)&sa, sizeof sa);
        SSL *ssl = SSL_new(ctx);
        BIO_ADDR *peer = BIO_ADDR_new();
        BIO_ADDR_rawmake(peer, AF_INET, &sa.sin_addr, sizeof sa.sin_addr, sa.sin_port);
        SSL_set_fd(ssl, fd);
        SSL_set1_initial_peer_addr(ssl, peer);
        SSL_set_alpn_protos(ssl, alpn, sizeof alpn);
        SSL_set_tlsext_host_name(ssl, "localhost");
        SSL_set_default_stream_mode(ssl, SSL_DEFAULT_STREAM_MODE_NONE);
        size_t w, r, total = 0;
        SSL *ctl = NULL, *req = NULL;
        if (SSL_connect(ssl) != 1 || (ctl = SSL_new_stream(ssl, SSL_STREAM_FLAG_UNI)) == NULL ||
            !SSL_write_ex(ctl, settings, sizeof settings, &w) || (req = SSL_new_stream(ssl, 0)) == NULL ||
            !SSL_write_ex2(req, get, sizeof get, SSL_WRITE_FLAG_CONCLUDE, &w)) {
            ERR_print_errors_fp(stderr);
            return 1;
        }
        while (SSL_read_ex(req, buf, sizeof buf, &r) > 0)
            total += r;
        double took = now_ms() - t0;
        printf("{\"mode\":\"download\",\"client\":\"bare-get\",\"ms\":%.3f,\"bytes\":%zu}\n", took, total);
        fflush(stdout);
        SSL_free(req);
        SSL_free(ctl);
        SSL_shutdown(ssl);
        SSL_free(ssl);
        BIO_ADDR_free(peer);
        close(fd);
    }
    return 0;
}
