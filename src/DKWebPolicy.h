// GPL-2.0-only. Explicit opt-in for unencrypted LAN web access.
#pragma once
#include <string_view>
namespace dkviewphone {
inline bool containsCurrentRoot(std::string_view path, std::string_view root) {
    while (root.size() > 1 && root.back() == '/') root.remove_suffix(1);
    root.remove_prefix(root.find_last_of('/') + 1);
    if (!root.starts_with(".jbroot-")) return false;
    while (!path.empty()) {
        size_t next = path.find('/');
        if (path.substr(0, next) == root) return true;
        if (next == std::string_view::npos) break;
        path.remove_prefix(next + 1);
    }
    return false;
}
inline bool validWebPort(int web, int vnc) { return web >= 1024 && web <= 65535 && web != vnc; }
inline bool allowWeb(bool enabled, bool tls, bool trustedLAN, bool certificate, bool key, int web, int vnc) {
    return enabled && validWebPort(web, vnc) && (tls ? certificate && key : trustedLAN);
}
}
