// Real OpenSSL I/O with concurrent server read/write/pending/teardown.
#include <rfb/rfb.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cerrno>
#include <csignal>
#include <fcntl.h>
#include <poll.h>
#include <thread>
#include <unistd.h>
#include <iostream>
extern "C" {
int rfbssl_init(rfbClientPtr);
int rfbssl_read(rfbClientPtr, char *, int);
int rfbssl_write(rfbClientPtr, const char *, int);
int rfbssl_peek(rfbClientPtr, char *, int);
int rfbssl_pending(rfbClientPtr);
void rfbssl_destroy(rfbClientPtr);
size_t DKTestTLSSessions();
}
int main(int argc, char **argv) {
    assert(argc == 3); signal(SIGPIPE, SIG_IGN);
    for (int cycle = 0; cycle < 12; ++cycle) {
        int sockets[2]; assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
        for (int fd : sockets) assert(fcntl(fd, F_SETFL, O_NONBLOCK) == 0);
        rfbScreenInfo screen = {}; screen.sslcertfile = argv[1]; screen.sslkeyfile = argv[2];
        rfbClientRec client = {}; client.screen = &screen; client.sock = sockets[0];
        int accepted = -1;
        std::thread handshake([&] { accepted = rfbssl_init(&client); });
        SSL_CTX *ctx = SSL_CTX_new(TLS_client_method()); assert(ctx);
        SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, nullptr); // generated fixture, never deployment configuration
        SSL *peer = SSL_new(ctx); assert(peer); SSL_set_fd(peer, sockets[1]);
        bool connected = false;
        auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(6);
        while (std::chrono::steady_clock::now() < deadline) {
            ERR_clear_error(); int result = SSL_connect(peer);
            if (result == 1) { connected = true; break; }
            int error = SSL_get_error(peer, result);
            assert(error == SSL_ERROR_WANT_READ || error == SSL_ERROR_WANT_WRITE);
            pollfd p = {sockets[1], static_cast<short>(error == SSL_ERROR_WANT_READ ? POLLIN : POLLOUT), 0};
            poll(&p, 1, 10);
        }
        handshake.join(); assert(connected && accepted == 0); assert(DKTestTLSSessions() == 1);
        std::atomic<bool> active(true);
        std::atomic<unsigned> reads(0), writes(0), pending(0);
        std::thread reader([&] { char b[2048]; while (active) { if (rfbssl_read(&client, b, sizeof(b)) > 0) ++reads; std::this_thread::yield(); } });
        std::thread writer([&] { const char b[128] = "fixture"; while (active) { if (rfbssl_write(&client, b, sizeof(b)) > 0) ++writes; std::this_thread::yield(); } });
        std::thread peeker([&] { char b[8]; while (active) { rfbssl_pending(&client); rfbssl_peek(&client, b, sizeof(b)); ++pending; std::this_thread::yield(); } });
        deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(250);
        const char send[128] = "fixture"; char receive[16384];
        // The peer SSL belongs to this thread only. Server SSL entry points are
        // deliberately called from three different threads.
        while (std::chrono::steady_clock::now() < deadline) {
            SSL_write(peer, send, sizeof(send)); SSL_read(peer, receive, sizeof(receive));
            std::this_thread::yield();
        }
        std::thread closeA([&] { for (int i = 0; i < 16; ++i) rfbssl_destroy(&client); });
        std::thread closeB([&] { for (int i = 0; i < 16; ++i) rfbssl_destroy(&client); });
        closeA.join(); closeB.join();
        active = false; reader.join(); writer.join(); peeker.join();
        assert(reads && writes && pending); assert(client.sslctx == nullptr); assert(DKTestTLSSessions() == 0);
        assert(rfbssl_pending(&client) == 0); assert(rfbssl_write(&client, send, sizeof(send)) == -1);
        SSL_free(peer); SSL_CTX_free(ctx); close(sockets[0]); close(sockets[1]);
    }
    rfbScreenInfo screen = {}; screen.sslcertfile = (char *)"/nonexistent-dk-test-certificate";
    rfbClientRec invalid = {}; invalid.screen = &screen; invalid.sock = -1;
    assert(rfbssl_init(&invalid) == -1); assert(DKTestTLSSessions() == 0);
    rfbssl_destroy(&invalid); rfbssl_destroy(nullptr);
    std::cout << "12 concurrent TLS read/write/pending/close rounds passed; no retained sessions\n";
}
