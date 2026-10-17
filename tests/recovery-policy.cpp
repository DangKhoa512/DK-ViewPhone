#include "../src/DKRecoveryPolicy.h"
#include <cassert>
#include <iostream>

int main() {
    dkviewphone::RecoveryBudget b;
    assert(b.canStart(100));
    for (unsigned i = 0; i < 4; ++i) {
        double now = 100 + i * 20;
        double delay = b.fail(now);
        assert(delay == (2u << i));
        assert(!b.canStart(now));
        assert(!b.canStart(now + delay - .01));
        assert(b.canStart(now + delay));
    }
    assert(b.fail(200) == -1 && b.latched);
    assert(!b.canStart(999999)); // Time alone cannot break a crash loop latch.
    b.manualOff();
    assert(b.canStart(201) && b.failures == 0);
    b.fail(300); b.fail(301);
    assert(b.fail(1300) == 2 && b.failures == 1); // Rolling window reset.
    assert(b.fail(200) == 2 && b.failures == 1); // Clock correction cannot underflow.
    auto persisted = b;
    assert(!persisted.canStart(201) && persisted.canStart(202));
    std::cout << "recovery budget: backoff, latch, persistence and manual-off passed\n";
}
