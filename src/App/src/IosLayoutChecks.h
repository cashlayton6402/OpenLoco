#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace OpenLoco::Ios
{
    // UIKit's landscape device and interface constants are opposite (3 <-> 4).
    constexpr int deviceOrientationForInterface(int orientation)
    {
        return orientation == 3 ? 4 : orientation == 4 ? 3
                                                       : orientation;
    }

    struct LayoutStep
    {
        const char* name;
        int orientation; // UIInterfaceOrientation, not UIDeviceOrientation.
        int width;
        int height;
        bool restoreWindow = false;
    };

    inline constexpr std::array<LayoutStep, 6> kLayoutSteps{ {
        { "landscape-left", 3, 0, 0 },
        { "landscape-right", 4, 0, 0 },
        { "portrait-return", 1, 0, 0 },
        { "resize-wide", 1, 640, 480 },
        { "resize-compact", 1, 320, 300 },
        { "restore-full", 1, 0, 0, true },
    } };

    // The app holds each actual geometry until the external driver captures and
    // validates it. No elapsed delay is treated as evidence of a successful resize.
    class LayoutChecks
    {
    public:
        enum class Action
        {
            wait,
            begin,
            capture,
            failure,
            complete
        };
        static constexpr uint64_t kSettleTimeoutMs = 60000;
        static constexpr uint64_t kAckTimeoutMs = 180000;

        int index() const { return _index; }
        int stableFrames() const { return _stableFrames; }
        bool failed() const { return _failed; }
        bool done() const { return _index == static_cast<int>(kLayoutSteps.size()); }
        const char* reason() const { return _reason; }

        Action update(uint64_t now, bool acknowledged, bool geometryReady, bool requestFailed)
        {
            if (_failed || done())
            {
                return Action::wait;
            }
            if (_index < 0)
            {
                if (!acknowledged)
                {
                    return Action::wait;
                }
                return advance(now);
            }
            if (requestFailed)
            {
                return fail("geometry-request-failed");
            }
            if (_captured)
            {
                if (acknowledged)
                {
                    return advance(now);
                }
                if (now - _started >= kAckTimeoutMs)
                {
                    return fail("capture-ack-timeout");
                }
                return Action::wait;
            }
            if (now - _started >= kSettleTimeoutMs)
            {
                return fail("geometry-settle-timeout");
            }
            _stableFrames = geometryReady ? _stableFrames + 1 : 0;
            if (_stableFrames >= 3)
            {
                _captured = true;
                _started = now;
                return Action::capture;
            }
            return Action::wait;
        }

    private:
        Action advance(uint64_t now)
        {
            ++_index;
            _started = now;
            _stableFrames = 0;
            _captured = false;
            return done() ? Action::complete : Action::begin;
        }
        Action fail(const char* reason)
        {
            _failed = true;
            _reason = reason;
            return Action::failure;
        }
        int _index = -1;
        int _stableFrames = 0;
        uint64_t _started = 0;
        bool _captured = false;
        bool _failed = false;
        const char* _reason = "";
    };
}
