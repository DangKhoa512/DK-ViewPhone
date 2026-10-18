// GPL-2.0-only. Real pthread contention: rollback and final static frame delivery.
#include "../src/DKFramePublication.h"
#include <cassert>
#include <future>
#include <iostream>
#include <thread>
#include <utility>
#include <vector>

int main() {
    pthread_mutex_t first = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_t second = PTHREAD_MUTEX_INITIALIZER;
    std::vector<pthread_mutex_t *> clients{&first, &second};
    auto mutex = [](pthread_mutex_t *value) { return value; };
    auto lock = [&] { return dkviewphone::tryLockAll(clients, mutex); };
    auto unlock = [&] { for (auto value : clients) assert(pthread_mutex_unlock(value) == 0); };
    int front = 1, back = 2, publications = 0, scheduled = 0;
    dkviewphone::LatestFramePublication pending;
    auto publish = [&] { std::swap(front, back); ++publications; };
    auto schedule = [&] { ++scheduled; };
    auto attempt = [&] { return pending.attempt(lock, publish, unlock, schedule); };
    std::promise<void> acquired, release;
    auto released = release.get_future();
    std::thread writer([&] {
        assert(pthread_mutex_lock(&second) == 0);
        acquired.set_value();
        released.wait();
        // The producer must never overwrite the front buffer during this send.
        assert(front == 1);
        assert(pthread_mutex_unlock(&second) == 0);
    });
    acquired.get_future().wait();
    pending.ready = true;
    assert(!attempt());
    assert(scheduled == 1 && publications == 0 && front == 1);
    // Partial acquisition must roll back so another sender can use the first lock.
    assert(pthread_mutex_trylock(&first) == 0);
    assert(pthread_mutex_unlock(&first) == 0);
    pending.invalidate(); back = 3; pending.ready = true;
    assert(!attempt());
    assert(scheduled == 1); // One retry; no queue of images or timer blocks.
    release.set_value(); writer.join();
    pending.retryFired();
    assert(attempt()); // No new capture: the final static change still arrives.
    assert(front == 3 && publications == 1 && !pending.ready);
    pending.retryFired();
    assert(!attempt() && publications == 1);
    pending.ready = true; pending.invalidate();
    assert(!attempt() && publications == 1); // Cancelled/resized image is not sent.
    clients.clear(); back = 4; pending.ready = true;
    assert(attempt() && front == 4); // Last viewer disconnected while deferred.
    assert(pthread_mutex_destroy(&first) == 0);
    assert(pthread_mutex_destroy(&second) == 0);
    std::cout << "PASS: lock rollback, immutable front, latest static frame, one retry, invalidation, zero clients\n";
}
