// GPL-2.0-only. Process exit must close transports and preserve reload status
// even while another thread is using session state; no concurrent destructors.
#include "../src/DKWorkerExit.h"
#include <cassert>
#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <future>
#include <iostream>
#include <sys/socket.h>
#include <sys/wait.h>
#include <thread>

static int auditFD = -1;
static void unsafeDestructor() {
    const char marker = 'D';
    (void)write(auditFD, &marker, 1);
}
int main() {
    signal(SIGPIPE, SIG_IGN);
    for (int round = 0; round < 20; ++round) {
        int sockets[2], audit[2];
        assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
        assert(pipe(audit) == 0);
        pid_t child = fork();
        assert(child >= 0);
        if (child == 0) {
            close(sockets[0]); close(audit[0]); auditFD = audit[1];
            assert(atexit(unsafeDestructor) == 0);
            std::promise<void> wrote;
            std::thread writer([&] {
                const char data[] = "frame";
                // Parent continues reading; exit occurs with live I/O and heap.
                auto *buffer = new char[4096];
                assert(write(sockets[1], data, 5) == 5);
                wrote.set_value();
                for (;;) { buffer[0] = 'x'; if (write(sockets[1], data, 5) < 0) break; }
                delete[] buffer;
            });
            wrote.get_future().wait();
            usleep(10000);
            DKExitWorker(75);
        }
        close(sockets[1]); close(audit[1]);
        char buffer[4096]; size_t received = 0;
        ssize_t count;
        while ((count = read(sockets[0], buffer, sizeof(buffer))) > 0) received += count;
        assert(count == 0 && received > 0); // Peer gets EOF, not an orphan listener.
        assert(read(audit[0], buffer, 1) == 0); // No unsafe session destructors.
        int status = 0;
        assert(waitpid(child, &status, 0) == child);
        assert(WIFEXITED(status) && WEXITSTATUS(status) == 75);
        close(sockets[0]); close(audit[0]);
    }
    std::cout << "PASS: 20 live-writer process exits, EOF, reload status 75, no concurrent destructors\n";
}
