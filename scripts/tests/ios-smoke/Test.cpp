#include "IosSetupSmoke.h"
#include <cstdlib>
#include <iostream>
#include <string_view>

using Smoke = OpenLoco::Ios::SetupSmoke;
using Action = Smoke::Action;

static void require(bool condition, const char* description)
{
    if (!condition)
    {
        std::cerr << "FAIL " << description << '\n';
        std::exit(1);
    }
}

static void delayedTransitions()
{
    Smoke smoke(100);
    Smoke::Observation ui;
    require(smoke.update(101, ui) == Action::wait, "Wait for scene activation");
    ui.sceneReady = ui.dialogIdle = true;
    require(smoke.update(200, ui) == Action::openDialog, "First button dispatched once");
    ui.dialogIdle = false;
    ui.checks = 1;
    require(smoke.update(1500, ui) == Action::wait, "Wait beyond old 700ms for presentation");
    require(smoke.update(2500, ui) == Action::wait, "Do not repeat first button");
    ui.dialogReady = true;
    ui.presentations = 1;
    require(smoke.update(3000, ui) == Action::cancelDialog, "Cancel only after presentation completion");
    ui.dialogReady = false;
    ui.cancellations = 1;
    require(smoke.update(3800, ui) == Action::wait, "Regression: no second button during dismissal");
    require(smoke.update(6000, ui) == Action::wait, "Delayed dismissal does not exit or repeat cancel");
    ui.dismissals = 1;
    ui.dialogIdle = true;
    ui.sceneReady = false;
    require(smoke.update(6500, ui) == Action::wait, "Wait for foreground scene after cancel");
    ui.sceneReady = true;
    require(smoke.update(7000, ui) == Action::openDialog, "Second button after dismissal completion");
    ui.dialogIdle = false;
    ui.checks = 2;
    require(smoke.update(8000, ui) == Action::wait, "Wait for second presentation");
    ui.dialogReady = true;
    ui.presentations = 2;
    require(smoke.update(9000, ui) == Action::retryDialog, "Retry after second presentation");
    ui.dialogReady = false;
    ui.checks = 3;
    require(smoke.update(10000, ui) == Action::wait, "Wait for retry dismissal");
    ui.dialogIdle = true;
    ui.dismissals = 2;
    require(smoke.update(11000, ui) == Action::wait, "Final scene uses a separate run-loop turn");
    ui.sceneReady = false;
    require(smoke.update(12000, ui) == Action::wait, "No success with unsettled final geometry");
    ui.sceneReady = true;
    require(smoke.update(13000, ui) == Action::success && smoke.complete(), "Completed real sequence");
    require(smoke.update(14000, ui) == Action::wait, "Success is reported once");
    std::cout << "PASS delayed presentation, dismissal, foreground and final scene\n";
}

static void everyStageTimesOut()
{
    for (int target = 0; target < 6; ++target)
    {
        Smoke smoke;
        Smoke::Observation ui{ true, false, true, 0, 0, 0, 0 };
        uint64_t now = 100;
        for (int stage = 0; stage < target; ++stage)
        {
            smoke.update(now++, ui);
            switch (stage)
            {
                case 0: ui = { true, true, false, 1, 0, 1, 0 }; break;
                case 1: ui = { true, false, true, 1, 1, 1, 1 }; break;
                case 2: ui = { true, true, false, 2, 1, 2, 1 }; break;
                case 3: ui = { true, false, true, 3, 1, 2, 2 }; break;
                default: break;
            }
        }
        const auto failedStage = smoke.stage();
        require(smoke.update(now + Smoke::kStageTimeoutMs, {}) == Action::failure, "Each stage has a deadline");
        require(smoke.failed() && smoke.stage() == failedStage, "Failure preserves its stage");
        require(std::string_view(smoke.failureReason()) == "transition-timeout", "Timeout reason retained");
        require(smoke.update(now + Smoke::kStageTimeoutMs + 1, ui) == Action::wait, "No action after timeout");
    }
    std::cout << "PASS deadlines in all six waiting stages\n";
}

static void incorrectCountersFail()
{
    Smoke smoke;
    require(smoke.update(1, { true, false, true, 1, 0, 0, 0 }) == Action::failure, "No false pass on unexpected action counts");
    require(std::string_view(smoke.failureReason()) == "action-count-mismatch", "Counter failure explained");
    smoke.fail("later-exit");
    require(std::string_view(smoke.failureReason()) == "action-count-mismatch", "Cleanup preserves first failure");
    std::cout << "PASS incorrect counters and first-failure preservation\n";
}

int main()
{
    delayedTransitions();
    everyStageTimesOut();
    incorrectCountersFail();
    Smoke smoke;
    require(smoke.update(Smoke::kTotalTimeoutMs, {}) == Action::failure, "Overall deadline enforced");
    std::cout << "PASS overall deadline\nPortable state tests only; no UIKit or Apple SDK executed.\n";
}
