#pragma once

#include <cmath>

namespace OpenLoco::Ios
{
    struct ViewRect
    {
        double x = 0;
        double y = 0;
        double width = 0;
        double height = 0;
    };

    inline bool validRect(const ViewRect& rect)
    {
        return std::isfinite(rect.x) && std::isfinite(rect.y) && std::isfinite(rect.width) && std::isfinite(rect.height)
            && rect.width > 0 && rect.height > 0;
    }

    inline bool sameRect(const ViewRect& a, const ViewRect& b)
    {
        return validRect(a) && validRect(b) && std::abs(a.x - b.x) < 1 && std::abs(a.y - b.y) < 1
            && std::abs(a.width - b.width) < 1 && std::abs(a.height - b.height) < 1;
    }

    struct ViewGeometry
    {
        ViewRect scene;
        ViewRect windowInScene;
        ViewRect windowBounds;
        ViewRect setupInWindow;
        ViewRect screen;
        ViewRect windowInScreen;
        double scale = 0;
        int pixelWidth = 0;
        int pixelHeight = 0;

        bool fillsScene() const
        {
            return sameRect(windowInScene, scene) && sameRect(setupInWindow, windowBounds);
        }

        bool fillsScreen() const
        {
            // A compatibility scene may fill its own window while being scaled
            // into a smaller rectangle on the display. Compare both spaces.
            return fillsScene() && sameRect(windowInScreen, screen)
                && std::abs(scene.width - screen.width) < 1 && std::abs(scene.height - screen.height) < 1;
        }

        bool drawableMatchesScreen() const
        {
            return validRect(screen) && std::isfinite(scale) && scale > 0 && pixelWidth > 0 && pixelHeight > 0
                && std::abs(pixelWidth - screen.width * scale) < 1 && std::abs(pixelHeight - screen.height * scale) < 1;
        }
    };
}
