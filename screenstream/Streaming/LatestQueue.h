// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include <condition_variable>
#include <mutex>
#include <optional>
#include <utility>

namespace dkss {
// One pending value. A value already consumed by the encoder/writer is immutable.
template<class T> class LatestQueue {
    std::mutex mutex;
    std::condition_variable changed;
    std::optional<T> pending;
    bool stopped = false;
public:
    enum class Push { accepted, replaced, closed };
    Push push(T value) {
        std::lock_guard guard(mutex);
        if (stopped) return Push::closed;
        bool replaced=pending.has_value();
        pending=std::move(value); changed.notify_one();
        return replaced ? Push::replaced : Push::accepted;
    }
    std::optional<T> wait() {
        std::unique_lock lock(mutex);
        changed.wait(lock,[&] { return stopped || pending.has_value(); });
        if (stopped) return {};
        auto value=std::move(pending); pending.reset(); return value;
    }
    std::optional<T> take() {
        std::lock_guard guard(mutex);
        if (stopped) return {};
        auto value=std::move(pending); pending.reset(); return value;
    }
    void clear() { std::lock_guard guard(mutex); pending.reset(); }
    void close() { std::lock_guard guard(mutex); stopped=true; pending.reset(); changed.notify_all(); }
};
} // namespace dkss
