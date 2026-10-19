// GPL-2.0-only. Test the real selector with synthetic adapter metadata only.
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <sys/socket.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static int fixtureGetIfAddrs(struct ifaddrs **out);
static void fixtureFreeIfAddrs(struct ifaddrs *addresses);
#define getifaddrs fixtureGetIfAddrs
#define freeifaddrs fixtureFreeIfAddrs
#include "../src/DKNetworkAddress.h"
#undef getifaddrs
#undef freeifaddrs

static struct ifaddrs interfaces[8];
static struct sockaddr_in addresses[8];
static struct ifaddrs *fixtureHead;
static int fixtureFailure;
static unsigned freeCalls;

static int fixtureGetIfAddrs(struct ifaddrs **out) {
    if (fixtureFailure) return -1;
    *out = fixtureHead;
    return 0;
}

static void fixtureFreeIfAddrs(struct ifaddrs *allocated) {
    assert(allocated == fixtureHead);
    ++freeCalls;
}

static void reset(void) {
    memset(interfaces, 0, sizeof(interfaces));
    memset(addresses, 0, sizeof(addresses));
    fixtureHead = NULL;
    fixtureFailure = 0;
    freeCalls = 0;
}

static void add(unsigned slot, const char *name, const char *ipv4, unsigned flags) {
    assert(slot < sizeof(interfaces) / sizeof(*interfaces));
    addresses[slot].sin_family = AF_INET;
    assert(inet_pton(AF_INET, ipv4, &addresses[slot].sin_addr) == 1);
    interfaces[slot].ifa_name = (char *)name;
    interfaces[slot].ifa_flags = flags;
    interfaces[slot].ifa_addr = (struct sockaddr *)&addresses[slot];
    interfaces[slot].ifa_next = fixtureHead;
    fixtureHead = &interfaces[slot];
}

int main(void) {
    char selected[INET_ADDRSTRLEN];
    const unsigned active = IFF_UP | IFF_RUNNING;
    reset(); fixtureFailure = 1;
    assert(!DKAutomaticLANIPv4(selected));
    assert(!strcmp(selected, "127.0.0.1") && freeCalls == 0);
    reset();
    assert(!DKAutomaticLANIPv4(selected));
    assert(!strcmp(selected, "127.0.0.1") && freeCalls == 1);
    assert(!DKAutomaticLANIPv4(NULL) && freeCalls == 1);

    reset();
    add(0, "pdp_ip0", "10.1.1.1", active);
    add(1, "utun0", "10.2.2.2", active);
    add(2, "lo0", "127.0.0.1", active | IFF_LOOPBACK);
    add(3, "en0", "169.254.1.2", active);
    add(4, "en1", "8.8.8.8", active);
    assert(!DKAutomaticLANIPv4(selected));
    assert(!strcmp(selected, "127.0.0.1") && freeCalls == 1);

    reset();
    add(0, "bridge0", "172.20.10.1", active);
    add(1, "en2", "192.168.2.2", active);
    add(2, "en0", "192.168.1.20", active);
    add(3, "en0", "192.168.1.10", active);
    assert(DKAutomaticLANIPv4(selected));
    assert(!strcmp(selected, "192.168.1.10") && freeCalls == 1);

    // Reverse enumeration must select the same concrete address.
    fixtureHead = &interfaces[0];
    for (unsigned i = 0; i < 4; ++i)
        interfaces[i].ifa_next = i == 3 ? NULL : &interfaces[i + 1];
    assert(DKAutomaticLANIPv4(selected));
    assert(!strcmp(selected, "192.168.1.10") && freeCalls == 2);

    // A down/not-running Wi-Fi adapter falls back to Ethernet, then bridge.
    interfaces[2].ifa_flags = IFF_RUNNING;
    interfaces[3].ifa_flags = IFF_UP;
    assert(DKAutomaticLANIPv4(selected));
    assert(!strcmp(selected, "192.168.2.2"));
    interfaces[1].ifa_flags = 0;
    assert(DKAutomaticLANIPv4(selected));
    assert(!strcmp(selected, "172.20.10.1"));

    // Subsequent reads follow new DHCP metadata instead of caching the result.
    interfaces[2].ifa_flags = active;
    assert(inet_pton(AF_INET, "192.168.4.50", &addresses[2].sin_addr) == 1);
    assert(DKAutomaticLANIPv4(selected));
    assert(!strcmp(selected, "192.168.4.50"));
    interfaces[0].ifa_addr = NULL;
    interfaces[1].ifa_addr = NULL;
    interfaces[2].ifa_addr = NULL;
    addresses[3].sin_family = AF_INET6;
    assert(!DKAutomaticLANIPv4(selected));
    assert(!strcmp(selected, "127.0.0.1"));
    puts("Automatic LAN IPv4 synthetic getifaddrs checks passed");
    return 0;
}
