// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include "../Common/Config.h"
#include "../Common/Frame.h"
#include "../Common/Protocol.h"
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace dkss {
class StreamServer {
    struct Impl;
    std::unique_ptr<Impl> impl;
public:
    StreamServer(Config config,std::string webRoot,Metrics &metrics,std::function<void(size_t)> viewersChanged);
    ~StreamServer();
    bool start(std::string &error);
    void publish(const FrameInfo &info,const std::vector<uint8_t> &jpeg);
    void publishMetrics(const std::string &json);
    size_t viewers() const;
    bool healthy() const;
    uint16_t localPort() const;
    void stop();
};
}
