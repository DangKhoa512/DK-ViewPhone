// GPL-2.0-only. Deterministic network policy checks; never inspect real adapters.
#define DK_NETWORK_ADDRESS_POLICY_ONLY
#include "../src/DKNetworkAddress.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    assert(DKBindHostIsAutomatic(NULL));
    assert(DKBindHostIsAutomatic(""));
    assert(DKBindHostIsAutomatic(" \t\r\n"));
    assert(DKBindHostIsAutomatic(" AUTO \n"));
    assert(!DKBindHostIsAutomatic("automatic"));
    assert(!DKBindHostIsAutomatic("auto.example"));
    assert(!DKBindHostIsAutomatic("192.168.1.2"));
    assert(!DKBindHostIsAutomatic("127.0.0.1"));
    const uint32_t accepted[] = {0x0a000001u, 0x0afffffeu, 0xac100001u,
        0xac1ffffeu, 0xc0a80001u, 0xc0a8fffeu};
    const uint32_t rejected[] = {0u, 0xffffffffu, 0x7f000001u, 0x08080808u,
        0xa9fe0001u, 0xac0fffffu, 0xac200001u, 0xc0a90001u};
    for (size_t i = 0; i < sizeof(accepted) / sizeof(*accepted); ++i)
        assert(DKLANPrivateIPv4(accepted[i]));
    for (size_t i = 0; i < sizeof(rejected) / sizeof(*rejected); ++i)
        assert(!DKLANPrivateIPv4(rejected[i]));

    assert(DKLANInterfacePriority("en0") > DKLANInterfacePriority("en1"));
    assert(DKLANInterfacePriority("en1") > DKLANInterfacePriority("bridge0"));
    const char *excluded[] = {NULL, "", "en", "en0x", "bridge", "bridge-1", "lo0",
        "pdp_ip0", "utun0", "ipsec0", "awdl0", "llw0"};
    for (size_t i = 0; i < sizeof(excluded) / sizeof(*excluded); ++i)
        assert(!DKLANInterfacePriority(excluded[i]));

    const uint32_t lan = 0xc0a80101u;
    assert(DKLANIPv4CandidatePreferred("en0", lan, 1, 1, 0, NULL, 0));
    assert(!DKLANIPv4CandidatePreferred("en0", lan, 0, 1, 0, NULL, 0));
    assert(!DKLANIPv4CandidatePreferred("en0", lan, 1, 0, 0, NULL, 0));
    assert(!DKLANIPv4CandidatePreferred("en0", lan, 1, 1, 1, NULL, 0));
    assert(!DKLANIPv4CandidatePreferred("en0", 0x08080808u, 1, 1, 0, NULL, 0));
    assert(!DKLANIPv4CandidatePreferred("pdp_ip0", lan, 1, 1, 0, NULL, 0));
    assert(DKLANIPv4CandidatePreferred("en0", lan, 1, 1, 0, "en1", lan));
    assert(!DKLANIPv4CandidatePreferred("en1", lan, 1, 1, 0, "en0", lan));
    assert(DKLANIPv4CandidatePreferred("en1", lan, 1, 1, 0, "bridge0", lan));
    assert(DKLANIPv4CandidatePreferred("en1", lan, 1, 1, 0, "en2", lan));
    assert(!DKLANIPv4CandidatePreferred("en2", lan, 1, 1, 0, "en1", lan));
    assert(DKLANIPv4CandidatePreferred("en0", lan, 1, 1, 0, "en0", lan + 1));
    assert(!DKLANIPv4CandidatePreferred("en0", lan + 1, 1, 1, 0, "en0", lan));
    puts("Automatic LAN IPv4 policy checks passed");
    return 0;
}
