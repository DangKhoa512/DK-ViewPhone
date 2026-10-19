// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
// Shared C/Objective-C/C++ policy for a concrete, private LAN listener.
#pragma once
#include <stdint.h>
#include <string.h>

static inline int DKBindHostIsAutomatic(const char *host) {
    if (!host) return 1;
    while (*host == ' ' || *host == '\t' || *host == '\r' || *host == '\n') ++host;
    size_t length = strlen(host);
    while (length && (host[length - 1] == ' ' || host[length - 1] == '\t' ||
                      host[length - 1] == '\r' || host[length - 1] == '\n')) --length;
    if (!length) return 1;
    return length == 4 && (host[0] == 'a' || host[0] == 'A') &&
        (host[1] == 'u' || host[1] == 'U') && (host[2] == 't' || host[2] == 'T') &&
        (host[3] == 'o' || host[3] == 'O');
}

// A LAN candidate is RFC1918 only; loopback is an explicit fallback, never a
// discovery candidate. This is narrower than the bind policy, which permits it.
static inline int DKLANPrivateIPv4(uint32_t hostAddress) {
    return (hostAddress >> 24) == 10 ||
        (hostAddress & 0xfff00000u) == 0xac100000u ||
        (hostAddress & 0xffff0000u) == 0xc0a80000u;
}

// Wi-Fi first, then Ethernet adapters, then local bridges. Cellular (pdp_ip*),
// VPN (utun*, ipsec*), peer-to-peer and loopback interfaces cannot be selected.
static inline unsigned DKLANInterfacePriority(const char *name) {
    if (!name) return 0;
    if (!strcmp(name, "en0")) return 3;
    const char *suffix = NULL;
    unsigned priority = 0;
    if (!strncmp(name, "en", 2)) { suffix = name + 2; priority = 2; }
    else if (!strncmp(name, "bridge", 6)) { suffix = name + 6; priority = 1; }
    if (!suffix || !*suffix) return 0;
    for (; *suffix; ++suffix) if (*suffix < '0' || *suffix > '9') return 0;
    return priority;
}

// Stable tie-breaking avoids interface enumeration order changing the listener.
// Addresses are in host byte order. NULL bestName means no candidate yet.
static inline int DKLANIPv4CandidatePreferred(const char *name, uint32_t address,
        int isUp, int isRunning, int isLoopback, const char *bestName, uint32_t bestAddress) {
    const unsigned priority = DKLANInterfacePriority(name);
    if (!priority || !isUp || !isRunning || isLoopback || !DKLANPrivateIPv4(address)) return 0;
    if (!bestName) return 1;
    const unsigned bestPriority = DKLANInterfacePriority(bestName);
    if (priority != bestPriority) return priority > bestPriority;
    const int order = strcmp(name, bestName);
    return order < 0 || (order == 0 && address < bestAddress);
}

#ifndef DK_NETWORK_ADDRESS_POLICY_ONLY
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <sys/socket.h>

// Read local interface metadata only. No DNS, packets, scanning or preferences.
// Return 1 when a LAN address was found; otherwise write the safe loopback
// fallback and return 0. Re-evaluate after network changes; do not persist the
// resolved result over the user's "auto" preference.
static inline int DKAutomaticLANIPv4(char out[INET_ADDRSTRLEN]) {
    if (!out) return 0;
    strcpy(out, "127.0.0.1");
    struct ifaddrs *addresses = NULL;
    if (getifaddrs(&addresses) != 0) return 0;
    const char *bestName = NULL;
    uint32_t bestAddress = 0;
    struct in_addr bestNetworkAddress;
    memset(&bestNetworkAddress, 0, sizeof(bestNetworkAddress));
    for (const struct ifaddrs *item = addresses; item; item = item->ifa_next) {
        if (!item->ifa_addr || item->ifa_addr->sa_family != AF_INET) continue;
        const struct sockaddr_in *address = (const struct sockaddr_in *)item->ifa_addr;
        const uint32_t hostAddress = ntohl(address->sin_addr.s_addr);
        if (!DKLANIPv4CandidatePreferred(item->ifa_name, hostAddress,
                !!(item->ifa_flags & IFF_UP), !!(item->ifa_flags & IFF_RUNNING),
                !!(item->ifa_flags & IFF_LOOPBACK), bestName, bestAddress)) continue;
        bestName = item->ifa_name;
        bestAddress = hostAddress;
        bestNetworkAddress = address->sin_addr;
    }
    const int found = bestName != NULL &&
        inet_ntop(AF_INET, &bestNetworkAddress, out, INET_ADDRSTRLEN) != NULL;
    freeifaddrs(addresses);
    if (!found) strcpy(out, "127.0.0.1");
    return found;
}
#endif
