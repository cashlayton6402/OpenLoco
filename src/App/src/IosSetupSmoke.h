#pragma once

#include <cstdint>

namespace OpenLoco::Ios
{
    // UIKit supplies observations; this sequence never assumes a transition has
    // finished just because a fixed delay has elapsed.
    class SetupSmoke
    {
    public:
        enum class Stage
        {
            scene,
            firstDialog,
            cancelDismissal,
            secondDialog,
            retryDismissal,
            finalScene,
            complete,
        };

        enum class Action
        {
            wait,
            openDialog,
            cancelDialog,
            retryDialog,
            success,
            failure,
        };

        struct Observation
        {
            bool sceneReady = false;
            bool dialogReady = false;
            bool dialogIdle = false;
            uint64_t checks = 0;
            uint64_t cancellations = 0;
            uint64_t presentations = 0;
            uint64_t dismissals = 0;
        };

        static constexpr uint64_t kStageTimeoutMs = 15000;
        static constexpr uint64_t kTotalTimeoutMs = 90000;

        explicit SetupSmoke(uint64_t now = 0)
            : _started(now)
            , _stageStarted(now)
        {
        }

        Stage stage() const { return _stage; }
        const char* failureReason() const { return _failureReason; }
        bool failed() const { return _failed; }
        bool complete() const { return _stage == Stage::complete; }
        void fail(const char* reason)
        {
            if (!_failed)
            {
                _failureReason = reason;
                _failed = true;
            }
        }

        const char* stageName() const
        {
            switch (_stage)
            {
                case Stage::scene: return "wait-for-scene";
                case Stage::firstDialog: return "wait-for-first-dialog";
                case Stage::cancelDismissal: return "wait-for-cancel-dismissal";
                case Stage::secondDialog: return "wait-for-second-dialog";
                case Stage::retryDismissal: return "wait-for-retry-dismissal";
                case Stage::finalScene: return "wait-for-final-scene";
                case Stage::complete: return "complete";
            }
            return "unknown";
        }

        Action update(uint64_t now, const Observation& ui)
        {
            if (_failed || complete())
            {
                return Action::wait;
            }
            if (now - _started >= kTotalTimeoutMs || now - _stageStarted >= kStageTimeoutMs)
            {
                fail("transition-timeout");
                return Action::failure;
            }
            switch (_stage)
            {
                case Stage::scene:
                    if (ui.sceneReady && ui.dialogIdle)
                    {
                        return advance(now, Stage::firstDialog, Action::openDialog, ui, 0, 0, 0, 0);
                    }
                    break;
                case Stage::firstDialog:
                    if (ui.dialogReady)
                    {
                        return advance(now, Stage::cancelDismissal, Action::cancelDialog, ui, 1, 0, 1, 0);
                    }
                    break;
                case Stage::cancelDismissal:
                    if (ui.sceneReady && ui.dialogIdle)
                    {
                        return advance(now, Stage::secondDialog, Action::openDialog, ui, 1, 1, 1, 1);
                    }
                    break;
                case Stage::secondDialog:
                    if (ui.dialogReady)
                    {
                        return advance(now, Stage::retryDismissal, Action::retryDialog, ui, 2, 1, 2, 1);
                    }
                    break;
                case Stage::retryDismissal:
                    if (ui.dialogIdle)
                    {
                        return advance(now, Stage::finalScene, Action::wait, ui, 3, 1, 2, 2);
                    }
                    break;
                case Stage::finalScene:
                    if (ui.sceneReady && ui.dialogIdle)
                    {
                        return advance(now, Stage::complete, Action::success, ui, 3, 1, 2, 2);
                    }
                    break;
                case Stage::complete: break;
            }
            return Action::wait;
        }

    private:
        Action advance(uint64_t now, Stage next, Action action, const Observation& ui, uint64_t checks, uint64_t cancellations, uint64_t presentations, uint64_t dismissals)
        {
            if (ui.checks != checks || ui.cancellations != cancellations || ui.presentations != presentations || ui.dismissals != dismissals)
            {
                fail("action-count-mismatch");
                return Action::failure;
            }
            _stage = next;
            _stageStarted = now;
            return action;
        }

        Stage _stage = Stage::scene;
        uint64_t _started;
        uint64_t _stageStarted;
        bool _failed = false;
        const char* _failureReason = "";
    };
}
