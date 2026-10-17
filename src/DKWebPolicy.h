// GPL-2.0-only. Explicit opt-in for unencrypted LAN web access.
#pragma once
namespace dkviewphone {
inline bool validWebPort(int web, int vnc) { return web >= 1024 && web <= 65535 && web != vnc; }
inline bool allowWeb(bool enabled, bool tls, bool trustedLAN, bool certificate, bool key, int web, int vnc) {
    return enabled && validWebPort(web, vnc) && (tls ? certificate && key : trustedLAN);
}
}
