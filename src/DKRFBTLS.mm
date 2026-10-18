/*
 * Secure socket adapter for LibVNCServer 0.9.15.
 * Based on rfbssl_openssl.c, Copyright (C) 2011 Gernot Tenchio.
 * Copyright (C) 2026 DK ViewPhone contributors.
 * GPL-2.0-or-later; see COPYING.
 *
 * Preserve the six existing transport entry points. The archive implementation
 * is not linked when these symbols are supplied. RFB/authentication stays in
 * LibVNCServer. Each SSL object has serialized I/O and retained ownership during
 * close; the opaque cl->sslctx pointer is never dereferenced by these functions.
 */
#include <rfb/rfb.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <cerrno>
#include <chrono>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <poll.h>
#include <pthread.h>

namespace {
struct State {
    std::mutex io;
    SSL_CTX *context = nullptr;
    SSL *ssl = nullptr;
    bool closed = false;
    ~State() { if (ssl) SSL_free(ssl); if (context) SSL_CTX_free(context); }
};
struct Registry {
    std::mutex mutex;
    std::unordered_map<rfbClientPtr, std::shared_ptr<State>> states;
};
Registry &registry() {
    // One process-lifetime registry. Avoid static-destruction races with library
    // threads at process exit; every per-session entry is erased on destroy.
    static auto *value = new Registry;
    return *value;
}
std::shared_ptr<State> find(rfbClientPtr cl) {
    auto &r = registry(); std::lock_guard<std::mutex> lock(r.mutex);
    auto it = r.states.find(cl);
    return it == r.states.end() ? nullptr : it->second;
}
struct CancellationMask {
    int previous = PTHREAD_CANCEL_ENABLE;
    CancellationMask() { pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous); }
    ~CancellationMask() { pthread_setcancelstate(previous, nullptr); }
};
enum class Operation { read, peek, write };
int transfer(rfbClientPtr cl, char *buffer, int size, Operation op) {
    auto state = find(cl);
    if (!state) { errno = ENOTCONN; return -1; }
    if (!buffer || size <= 0) { errno = EINVAL; return -1; }
    CancellationMask cancellation;
    std::lock_guard<std::mutex> lock(state->io);
    if (state->closed || !state->ssl) { errno = ENOTCONN; return -1; }
    ERR_clear_error();
    int result = op == Operation::write ? SSL_write(state->ssl, buffer, size) :
                 op == Operation::peek ? SSL_peek(state->ssl, buffer, size) : SSL_read(state->ssl, buffer, size);
    if (result > 0) return result;
    int error = SSL_get_error(state->ssl, result);
    // The engine polls the socket with its existing bounded read/write waits.
    // Never spin on WANT_READ/WANT_WRITE while holding an SSL object's lock.
    if (error == SSL_ERROR_WANT_READ || error == SSL_ERROR_WANT_WRITE) errno = EAGAIN;
    else if (error == SSL_ERROR_ZERO_RETURN || (error == SSL_ERROR_SYSCALL && result == 0)) return 0;
    else if (error != SSL_ERROR_SYSCALL || errno == 0) errno = EPROTO;
    return -1;
}
}

extern "C" int rfbssl_init(rfbClientPtr cl) {
    if (!cl || !cl->screen || !cl->screen->sslcertfile || !*cl->screen->sslcertfile) { errno = EINVAL; return -1; }
    if (find(cl)) return 0;
    std::shared_ptr<State> state;
    try { state = std::make_shared<State>(); } catch (const std::bad_alloc &) { errno = ENOMEM; return -1; }
    state->context = SSL_CTX_new(TLS_server_method());
    const char *key = cl->screen->sslkeyfile && *cl->screen->sslkeyfile ? cl->screen->sslkeyfile : cl->screen->sslcertfile;
    if (!state->context || SSL_CTX_set_min_proto_version(state->context, TLS1_2_VERSION) != 1 ||
        SSL_CTX_use_certificate_chain_file(state->context, cl->screen->sslcertfile) != 1 ||
        SSL_CTX_use_PrivateKey_file(state->context, key, SSL_FILETYPE_PEM) != 1 ||
        SSL_CTX_check_private_key(state->context) != 1) { errno = EPROTO; return -1; }
    SSL_CTX_set_mode(state->context, SSL_MODE_ENABLE_PARTIAL_WRITE | SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);
    state->ssl = SSL_new(state->context);
    if (!state->ssl || SSL_set_fd(state->ssl, cl->sock) != 1) { errno = EPROTO; return -1; }
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    bool accepted = false;
    while (std::chrono::steady_clock::now() < deadline) {
        int error;
        {
            CancellationMask cancellation;
            ERR_clear_error(); int result = SSL_accept(state->ssl);
            if (result == 1) { accepted = true; break; }
            error = SSL_get_error(state->ssl, result);
        }
        if (error != SSL_ERROR_WANT_READ && error != SSL_ERROR_WANT_WRITE) { errno = EPROTO; return -1; }
        pollfd wait = {cl->sock, static_cast<short>(error == SSL_ERROR_WANT_READ ? POLLIN : POLLOUT), 0};
        int result = poll(&wait, 1, 100);
        if (result < 0 && errno != EINTR) return -1;
        if (wait.revents & (POLLERR | POLLHUP | POLLNVAL)) { errno = ECONNRESET; return -1; }
    }
    if (!accepted) { errno = ETIMEDOUT; return -1; }
    auto &r = registry(); std::lock_guard<std::mutex> lock(r.mutex);
    try { r.states[cl] = state; } catch (const std::bad_alloc &) { errno = ENOMEM; return -1; }
    cl->sslctx = reinterpret_cast<rfbSslCtx *>(state.get());
    return 0;
}
extern "C" int rfbssl_write(rfbClientPtr cl, const char *buffer, int size) {
    return transfer(cl, const_cast<char *>(buffer), size, Operation::write);
}
extern "C" int rfbssl_read(rfbClientPtr cl, char *buffer, int size) { return transfer(cl, buffer, size, Operation::read); }
extern "C" int rfbssl_peek(rfbClientPtr cl, char *buffer, int size) { return transfer(cl, buffer, size, Operation::peek); }
extern "C" int rfbssl_pending(rfbClientPtr cl) {
    auto state = find(cl); if (!state) return 0;
    CancellationMask cancellation; std::lock_guard<std::mutex> lock(state->io);
    return !state->closed && state->ssl ? SSL_pending(state->ssl) : 0;
}
extern "C" void rfbssl_destroy(rfbClientPtr cl) {
    if (!cl) return;
    std::shared_ptr<State> state;
    {
        auto &r = registry(); std::lock_guard<std::mutex> lock(r.mutex);
        auto it = r.states.find(cl);
        if (it != r.states.end()) {
            state = it->second; r.states.erase(it);
            // The engine chooses raw write/read when sslctx is NULL. Shut down
            // the transport first so a concurrent closing thread cannot fall
            // back to plaintext. Socket ownership/close remains in the engine.
            shutdown(cl->sock, SHUT_RDWR);
        }
        cl->sslctx = nullptr;
    }
    if (!state) return;
    CancellationMask cancellation; std::lock_guard<std::mutex> lock(state->io);
    state->closed = true;
    if (state->ssl) { SSL_free(state->ssl); state->ssl = nullptr; }
    if (state->context) { SSL_CTX_free(state->context); state->context = nullptr; }
}
#ifdef DK_TLS_TESTING
extern "C" size_t DKTestTLSSessions() {
    auto &r = registry(); std::lock_guard<std::mutex> lock(r.mutex); return r.states.size();
}
#endif
