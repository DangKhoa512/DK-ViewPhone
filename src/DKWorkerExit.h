// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include <unistd.h>

// This worker never reuses its engine after shutdown. Terminate the process,
// letting the kernel reclaim sockets/memory/threads together. Walking/freeing
// LibVNCServer clients while its detached I/O threads retire them races; exit()
// also runs C++ TLS-registry destructors concurrently with those threads.
[[noreturn]] inline void DKExitWorker(int code) { _exit(code); }
