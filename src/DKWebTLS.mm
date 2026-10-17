// GPL-2.0-only. Optional bounded HTTPS static-file adapter in the engine process.
// LibVNCServer's built-in HTTP listener has no TLS support. No RFB/input code here.
#import "DKWebTLS.h"
#import <Foundation/Foundation.h>
#include <openssl/ssl.h>
#include <arpa/inet.h>
#include <atomic>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#include <thread>
#include <vector>
#include <string>
#include <algorithm>
#include <cstring>
#include <time.h>
#include <mutex>
#include <set>

static SSL_CTX *context;
static int listener = -1;
static std::atomic<bool> running(false);
static std::vector<std::thread> threads;
static std::mutex clientsMutex;
static std::set<int> clients;
static std::string documentRoot;
static int rfbPort;
static double now() { return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e9; }

static bool writeTLS(SSL *ssl, const char *data, size_t length) {
    // Absolute per-response budget, including clients that trickle reads.
    const double deadline = now() + 5;
    while (length && running && now() < deadline) {
        int n = SSL_write(ssl, data, (int)std::min(length, size_t(16384)));
        if (n <= 0) return false;
        data += n; length -= n;
    }
    return length == 0;
}

static void serve(int fd) {
    SSL *ssl = SSL_new(context);
    if (!ssl) return;
    SSL_set_fd(ssl, fd);
    if (SSL_accept(ssl) != 1) { SSL_free(ssl); return; }
    std::string request; char buffer[2048];
    const double deadline = now() + 5;
    while (request.find("\r\n\r\n") == std::string::npos && request.size() < 8192 && running &&
           now() < deadline) {
        int n = SSL_read(ssl, buffer, sizeof(buffer));
        if (n <= 0) break;
        request.append(buffer, n);
    }
    @autoreleasepool {
        NSString *target = nil;
        auto end = request.find(" HTTP/1.");
        if (request.rfind("GET /", 0) == 0 && end != std::string::npos &&
            request.find("\r\n\r\n") != std::string::npos) {
            target = [[NSString alloc] initWithBytes:request.data()+4 length:end-4 encoding:NSUTF8StringEncoding];
            target = [[target componentsSeparatedByString:@"?"] firstObject].stringByRemovingPercentEncoding;
        }
        if ([target isEqualToString:@"/"]) target = @"/index.vnc";
        NSString *root = @(documentRoot.c_str());
        NSString *resolved = target ? [[root stringByAppendingString:target] stringByResolvingSymlinksInPath] : nil;
        NSDictionary *types = @{@"vnc":@"text/html; charset=utf-8", @"html":@"text/html; charset=utf-8",
            @"css":@"text/css; charset=utf-8", @"js":@"application/javascript; charset=utf-8",
            @"svg":@"image/svg+xml", @"png":@"image/png", @"ico":@"image/x-icon", @"woff":@"font/woff"};
        NSString *mime = resolved ? types[resolved.pathExtension.lowercaseString] : nil;
        NSData *data = nil; struct stat st = {};
        if (mime && [resolved hasPrefix:[root stringByAppendingString:@"/"]] &&
            stat(resolved.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode) && st.st_size <= 8*1024*1024) {
            data = [NSData dataWithContentsOfFile:resolved];
            if ([resolved.pathExtension isEqualToString:@"vnc"] && data) {
                NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                html = [html stringByReplacingOccurrencesOfString:@"$PORT" withString:[NSString stringWithFormat:@"%d", rfbPort]];
                data = [html dataUsingEncoding:NSUTF8StringEncoding];
            }
        }
        NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %@\r\nConnection: close\r\nContent-Type: %@\r\nContent-Length: %lu\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n\r\n",
            data ? @"200 OK" : @"404 Not Found", data ? mime : @"text/plain", (unsigned long)data.length];
        if (writeTLS(ssl, header.UTF8String, strlen(header.UTF8String)) && data)
            writeTLS(ssl, (const char *)data.bytes, data.length);
    }
    // Do not wait for a peer close_notify; the connection is deliberately one-shot.
    SSL_free(ssl);
}

void DKWebTLSStop(void) {
    running = false;
    { std::lock_guard<std::mutex> guard(clientsMutex); for (int fd : clients) shutdown(fd, SHUT_RDWR); }
    for (auto &t : threads) if (t.joinable()) t.join();
    threads.clear();
    if (listener >= 0) close(listener);
    listener = -1;
    if (context) SSL_CTX_free(context);
    context = nullptr;
}

bool DKWebTLSStart(const char *bind, int port, const char *root, const char *cert, const char *key, int vncPort) {
    DKWebTLSStop();
    if (!root || !cert || !key) return false;
    context = SSL_CTX_new(TLS_server_method());
    if (!context) return false;
    SSL_CTX_set_min_proto_version(context, TLS1_2_VERSION);
    if (SSL_CTX_use_certificate_chain_file(context, cert) != 1 ||
        SSL_CTX_use_PrivateKey_file(context, key, SSL_FILETYPE_PEM) != 1 || SSL_CTX_check_private_key(context) != 1) {
        DKWebTLSStop(); return false;
    }
    listener = socket(AF_INET, SOCK_STREAM, 0);
    int yes = 1; setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    sockaddr_in address = {}; address.sin_len = sizeof(address); address.sin_family = AF_INET;
    address.sin_port = htons(port);
    if (listener < 0 || inet_pton(AF_INET, bind, &address.sin_addr) != 1 ||
        ::bind(listener, (sockaddr *)&address, sizeof(address)) || listen(listener, 8)) {
        DKWebTLSStop(); return false;
    }
    fcntl(listener, F_SETFL, O_NONBLOCK); fcntl(listener, F_SETFD, FD_CLOEXEC);
    documentRoot = [[@(root) stringByResolvingSymlinksInPath] UTF8String]; rfbPort = vncPort; running = true;
    for (int i = 0; i < 4; ++i) threads.emplace_back([] {
        while (running) @autoreleasepool {
            pollfd p = {listener, POLLIN, 0};
            if (poll(&p, 1, 100) <= 0) continue;
            int fd = accept(listener, nullptr, nullptr);
            if (fd < 0) continue;
            fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK);
            fcntl(fd, F_SETFD, FD_CLOEXEC);
            timeval timeout = {1, 0};
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
            int noSigPipe = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
            { std::lock_guard<std::mutex> guard(clientsMutex); clients.insert(fd); }
            if (running) serve(fd);
            { std::lock_guard<std::mutex> guard(clientsMutex); clients.erase(fd); close(fd); }
        }
    });
    return true;
}
