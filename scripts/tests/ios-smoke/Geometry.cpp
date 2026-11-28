#include "IosViewGeometry.h"
#include <cstdlib>
#include <iostream>
#include <limits>

using OpenLoco::Ios::ViewGeometry;

static void require(bool condition, const char* description)
{
    if (!condition)
    {
        std::cerr << "FAIL " << description << '\n';
        std::exit(1);
    }
}

static ViewGeometry fullDisplay(int width, int height)
{
    ViewGeometry geometry;
    geometry.scene = geometry.windowInScene = geometry.windowBounds = geometry.setupInWindow = geometry.screen = geometry.windowInScreen = { 0, 0, static_cast<double>(width), static_cast<double>(height) };
    geometry.scale = 2;
    geometry.pixelWidth = width * 2;
    geometry.pixelHeight = height * 2;
    return geometry;
}

int main()
{
    for (const auto& geometry : { fullDisplay(834, 1210), fullDisplay(1210, 834), fullDisplay(320, 400) })
    {
        require(geometry.fillsScene() && geometry.fillsScreen() && geometry.drawableMatchesScreen(), "Portrait, landscape and resized coordinates are supported");
    }
    std::cout << "PASS full portrait, landscape and resized display geometry\n";

    auto letterbox = fullDisplay(1210, 834);
    letterbox.screen = { 0, 0, 834, 1210 };
    letterbox.windowInScreen = { 0, 317.5, 834, 575 };
    require(letterbox.fillsScene(), "Reproduce the old internal scene success");
    require(!letterbox.fillsScreen() && !letterbox.drawableMatchesScreen(), "Reject the old scaled scene on a portrait display");
    std::cout << "PASS regression: filled landscape scene cannot prove filled portrait screen\n";

    auto geometry = fullDisplay(834, 1210);
    geometry.windowInScreen.y = 10;
    require(!geometry.fillsScreen(), "Reject a displaced window");
    geometry = fullDisplay(834, 1210);
    geometry.setupInWindow.height -= 100;
    require(!geometry.fillsScene() && !geometry.fillsScreen(), "Reject incomplete setup coverage");
    geometry = fullDisplay(834, 1210);
    geometry.pixelWidth = 2420;
    geometry.pixelHeight = 1668;
    require(geometry.fillsScreen() && !geometry.drawableMatchesScreen(), "Reject swapped drawable dimensions");
    geometry = fullDisplay(834, 1210);
    geometry.scale = 1;
    require(!geometry.drawableMatchesScreen(), "Reject incorrect scale");
    geometry.scale = std::numeric_limits<double>::quiet_NaN();
    require(!geometry.drawableMatchesScreen(), "Reject nonfinite scale");
    geometry = fullDisplay(834, 1210);
    geometry.screen.width = std::numeric_limits<double>::infinity();
    require(!geometry.fillsScreen() && !geometry.drawableMatchesScreen(), "Reject nonfinite bounds");
    require(!ViewGeometry{}.fillsScene() && !ViewGeometry{}.fillsScreen() && !ViewGeometry{}.drawableMatchesScreen(), "Reject detached views");
    std::cout << "PASS offsets, clipping, drawable/scale mismatch and invalid geometry\nNo UIKit or Apple SDK executed.\n";
}
