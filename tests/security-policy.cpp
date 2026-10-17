#include "../src/DKViewPhonePolicy.h"
#include <cassert>
#include <iostream>

int main() {
    using namespace dkviewphone;
    // Synthetic test fixtures, never deployment credentials.
    assert(strongPassword("Az3!pR8?"));
    assert(!strongPassword(nullptr));
    assert(!strongPassword(""));
    assert(!strongPassword("Az3!pR8"));
    assert(!strongPassword("Az3!pR8?X"));
    assert(!strongPassword("az3!pr8?"));
    assert(!strongPassword("AZ3!PR8?"));
    assert(!strongPassword("AzX!pRz?"));
    assert(!strongPassword("Az39pR80"));
    assert(!strongPassword("Az3 pR8?"));
    assert(!strongPassword("Az3\npR8?"));
    assert(!strongPassword("Az3\x7fpR8?"));
    assert(!strongPassword("Az3\x80pR8?"));
    assert(!privateIPv4(0));
    assert(!privateIPv4(0xffffffff));
    assert(privateIPv4(0x7f000001));
    assert(privateIPv4(0x0a000001));
    assert(privateIPv4(0x0afffffe));
    assert(!privateIPv4(0x0b000001));
    assert(!privateIPv4(0xac0fffff));
    assert(privateIPv4(0xac100001));
    assert(privateIPv4(0xac1ffffe));
    assert(!privateIPv4(0xac200001));
    assert(privateIPv4(0xc0a80001));
    assert(privateIPv4(0xc0a8fffe));
    assert(!privateIPv4(0xc0a90001));
    assert(!privateIPv4(0x08080808));
    assert(!privateIPv4(0xa9fe0001));
    std::cout << "Password policy and IPv4 boundary checks passed\n";
}
