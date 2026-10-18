// ĐK ViewPhone security policy. GPL-2.0-only; see COPYING.
#pragma once
#include <stdint.h>
#include <string.h>

namespace dkviewphone {
inline bool strongPassword(const char *password) {
    if (!password || strlen(password) != 8)
        return false;
    bool upper = false, lower = false, digit = false, symbol = false;
    for (unsigned i = 0; i < 8; ++i) {
        const unsigned char c = static_cast<unsigned char>(password[i]);
        if (c < 0x21 || c > 0x7e)
            return false;
        if (c >= 'A' && c <= 'Z') upper = true;
        else if (c >= 'a' && c <= 'z') lower = true;
        else if (c >= '0' && c <= '9') digit = true;
        else symbol = true;
    }
    return upper && lower && digit && symbol;
}

// A concrete IPv4 bind address, in host byte order. No wildcard/public binds.
inline bool privateIPv4(uint32_t address) {
    return (address >> 24) == 127 || (address >> 24) == 10 ||
           (address & 0xfff00000u) == 0xac100000u ||
           (address & 0xffff0000u) == 0xc0a80000u;
}

// Explicit local opt-in only. Never offer unauthenticated reverse connections.
inline bool allowPasswordlessLAN(bool enabled, bool trustedLAN, bool reverse, uint32_t address) {
    return enabled && trustedLAN && !reverse && privateIPv4(address);
}
} // namespace dkviewphone
