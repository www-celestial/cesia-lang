/* bare-h3: the OpenSSL QUIC stack alone, no Cesia: OpenSSL's own blocking server model (guide quic-server-block),
 * one thread per connection (OpenSSL's contentive concurrency model), with the least HTTP/3 a quic-go client accepts:
 * a control stream with an empty SETTINGS, and on each request stream a HEADERS frame (:status 200, QPACK static
 * index 25) and one DATA frame of SIZE bytes, then FIN.
 *   bare-h3 CERT KEY PORT SIZE
 */
#include <openssl/err.h>
#include <openssl/quic.h>
#include <openssl/ssl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static unsigned char *body;
static size_t body_len;

static int select_alpn(SSL *ssl, const unsigned char **out, unsigned char *out_len, const unsigned char *in,
                       unsigned int in_len, void *arg) {
    static const unsigned char h3[] = {2, 'h', '3'};
    if (SSL_select_next_proto((unsigned char **)out, out_len, h3, sizeof h3, in, in_len) == OPENSSL_NPN_NEGOTIATED)
        return SSL_TLSEXT_ERR_OK;
    return SSL_TLSEXT_ERR_ALERT_FATAL;
}

static void *serve(void *arg) {
    SSL *conn = arg, *ctl = NULL, *uni[8] = {0}, *req = NULL;
    int nuni = 0;
    unsigned char buf[4096];
    size_t n, w;
    static const unsigned char settings[] = {0x00, 0x04, 0x00};

    SSL_set_default_stream_mode(conn, SSL_DEFAULT_STREAM_MODE_NONE);
    if ((ctl = SSL_new_stream(conn, SSL_STREAM_FLAG_UNI)) == NULL || !SSL_write_ex(ctl, settings, sizeof settings, &w))
        goto end;
    while (req == NULL) {
        SSL *s = SSL_accept_stream(conn, 0);
        if (s == NULL)
            goto end;
        if (SSL_get_stream_type(s) == SSL_STREAM_TYPE_BIDI)
            req = s;
        else if (nuni < 8)
            uni[nuni++] = s; /* the client's control stream: kept open, never read */
        else
            SSL_free(s);
    }
    /* The request: read until its FIN (a GET sends its HEADERS and ends its side). */
    while (SSL_read_ex(req, buf, sizeof buf, &n) > 0)
        ;
    if (!SSL_write_ex(req, body, body_len, &w) || w != body_len || !SSL_stream_conclude(req, 0))
        goto end;
    while (SSL_shutdown(conn) == 0)
        ;
end:
    SSL_free(req);
    for (int i = 0; i < nuni; i++)
        SSL_free(uni[i]);
    SSL_free(ctl);
    SSL_free(conn);
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 5) {
        fprintf(stderr, "usage: bare-h3 CERT KEY PORT SIZE\n");
        return 2;
    }
    size_t size = strtoul(argv[4], NULL, 10);
    /* HEADERS (type 1, length 3: Required Insert Count 0, Base 0, indexed static 25 = :status 200), then DATA. */
    unsigned char head[] = {0x01, 0x03, 0x00, 0x00, 0xd9, 0x00, 0x80 | (size >> 24), size >> 16, size >> 8, size};
    body_len = sizeof head + size;
    body = malloc(body_len);
    memcpy(body, head, sizeof head);
    memset(body + sizeof head, 'x', size);

    SSL_CTX *ctx = SSL_CTX_new(OSSL_QUIC_server_method());
    if (ctx == NULL || SSL_CTX_use_certificate_chain_file(ctx, argv[1]) <= 0 ||
        SSL_CTX_use_PrivateKey_file(ctx, argv[2], SSL_FILETYPE_PEM) <= 0) {
        ERR_print_errors_fp(stderr);
        return 1;
    }
    SSL_CTX_set_alpn_select_cb(ctx, select_alpn, NULL);

    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in sa = {.sin_family = AF_INET, .sin_port = htons(atoi(argv[3]))};
    if (fd < 0 || bind(fd, (struct sockaddr *)&sa, sizeof sa) < 0) {
        perror("bind");
        return 1;
    }
    SSL *listener = SSL_new_listener(ctx, 0);
    if (listener == NULL || !SSL_set_fd(listener, fd) || !SSL_listen(listener)) {
        ERR_print_errors_fp(stderr);
        return 1;
    }
    fprintf(stderr, "bare-h3 on %s with %s\n", argv[3], OpenSSL_version(OPENSSL_VERSION));
    for (;;) {
        SSL *conn = SSL_accept_connection(listener, 0);
        if (conn == NULL) {
            ERR_print_errors_fp(stderr);
            continue;
        }
        pthread_t t;
        if (pthread_create(&t, NULL, serve, conn) != 0)
            SSL_free(conn);
        else
            pthread_detach(t);
    }
}
