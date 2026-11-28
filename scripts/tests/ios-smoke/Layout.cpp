#include "IosLayoutChecks.h"
#include <cstdlib>
#include <iostream>

using Checks = OpenLoco::Ios::LayoutChecks;
using Action = Checks::Action;
static void require(bool condition, const char* message)
{
    if (!condition)
    {
        std::cerr << "FAIL " << message << '\n';
        std::exit(1);
    }
}

int main()
{
    require(OpenLoco::Ios::deviceOrientationForInterface(3) == 4, "Interface left requires device right");
    require(OpenLoco::Ios::deviceOrientationForInterface(4) == 3, "Interface right requires device left");
    require(OpenLoco::Ios::deviceOrientationForInterface(1) == 1, "Portrait constants agree");
    Checks checks;
    require(checks.update(1, false, true, false) == Action::wait, "Initial portrait must be captured before rotation");
    uint64_t now = 10;
    require(checks.update(now++, true, false, false) == Action::begin, "Start after session-matched setup ack");
    for (int index = 0; index < 6; ++index)
    {
        require(checks.index() == index, "No stage skipped");
        require(checks.update(now++, true, false, false) == Action::wait, "Early ack cannot bypass actual geometry");
        require(checks.update(now++, false, true, false) == Action::wait, "One frame not settled");
        require(checks.update(now++, false, false, false) == Action::wait, "Unstable geometry resets frame count");
        require(checks.update(now++, false, true, false) == Action::wait, "Need three fresh observations");
        require(checks.update(now++, false, true, false) == Action::wait, "Two frames not enough");
        require(checks.update(now++, false, true, false) == Action::capture, "Capture stable real geometry");
        require(checks.update(now++, false, true, false) == Action::wait, "Hold actual window for raw screenshot");
        require(checks.update(now++, true, true, false) == (index == 5 ? Action::complete : Action::begin), "Only capture ack advances stage");
    }
    require(checks.done() && checks.update(now, true, true, false) == Action::wait, "Completion requires final restoration ack");
    Checks timeout;
    timeout.update(0, true, false, false);
    require(timeout.update(Checks::kSettleTimeoutMs, false, false, false) == Action::failure, "No-op resize/rotation must time out");
    Checks requestError;
    requestError.update(0, true, false, false);
    require(requestError.update(1, false, true, true) == Action::failure, "Request errors are failures even if geometry seems ready");
    Checks ackTimeout;
    ackTimeout.update(0, true, false, false);
    ackTimeout.update(1, false, true, false);
    ackTimeout.update(2, false, true, false);
    ackTimeout.update(3, false, true, false);
    require(ackTimeout.update(3 + Checks::kAckTimeoutMs, false, true, false) == Action::failure, "Missing capture ack bounded");
    std::cout << "PASS ordered rotation/resize/restoration, stability, capture holds and deadlines. No UIKit executed.\n";
}
