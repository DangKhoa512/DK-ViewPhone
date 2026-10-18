// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include <pthread.h>

namespace dkviewphone {
// Never leave a subset locked when one writer is still sending a frame.
template<class Clients, class Mutex>
bool tryLockAll(const Clients &clients, Mutex mutex) {
    auto current = clients.begin();
    for (; current != clients.end(); ++current) {
        if (pthread_mutex_trylock(mutex(*current)) == 0) continue;
        for (auto rollback = clients.begin(); rollback != current; ++rollback)
            pthread_mutex_unlock(mutex(*rollback));
        return false;
    }
    return true;
}

// Main-thread only. The existing back buffer always contains the latest image.
// A retry is essential: dirty capture may stop after the final static change.
struct LatestFramePublication {
    bool ready = false;
    bool retryScheduled = false;
    void invalidate() { ready = false; }
    void retryFired() { retryScheduled = false; }
    template<class Lock, class Publish, class Unlock, class Schedule>
    bool attempt(Lock lock, Publish publish, Unlock unlock, Schedule schedule) {
        if (!ready) return false;
        if (!lock()) {
            if (!retryScheduled) { retryScheduled = true; schedule(); }
            return false;
        }
        publish();
        ready = false;
        unlock();
        return true;
    }
};
}
