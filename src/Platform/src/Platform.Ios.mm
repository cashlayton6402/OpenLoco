#include "Platform.h"
#import <Foundation/Foundation.h>
#include <SDL3/SDL_log.h>
#include <chrono>
#include <cstdlib>

namespace OpenLoco::Platform
{
    void initialise()
    {
        fs::create_directories(getUserDirectory());
    }

    uint32_t getTime()
    {
        const auto elapsed = std::chrono::steady_clock::now().time_since_epoch();
        return static_cast<uint32_t>(std::chrono::duration_cast<std::chrono::milliseconds>(elapsed).count());
    }

    fs::path getBundlePath()
    {
        @autoreleasepool
        {
            return fs::u8path(NSBundle.mainBundle.resourcePath.UTF8String);
        }
    }

    fs::path getDataDirectory()
    {
        return getBundlePath();
    }

    fs::path getUserDirectory()
    {
        @autoreleasepool
        {
            NSURL* support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
            return fs::u8path([support URLByAppendingPathComponent:@"OpenLoco" isDirectory:YES].path.UTF8String);
        }
    }

    fs::path getCurrentExecutablePath()
    {
        @autoreleasepool
        {
            return fs::u8path(NSBundle.mainBundle.executablePath.UTF8String);
        }
    }

    fs::path showFolderPicker(const std::string&)
    {
        // Desktop synchronous path APIs cannot retain iOS security-scoped grants.
        // The setup shell must import data asynchronously before engine startup.
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "Folder selection requires the iOS setup screen.");
        return {};
    }

    std::vector<fs::path> getDrives()
    {
        return {};
    }

    std::vector<fs::path> getLocoInstallSearchPaths()
    {
        return { getUserDirectory() / "Locomotion" };
    }

    std::string getEnvironmentVariable(const std::string& name)
    {
        const auto* value = std::getenv(name.c_str());
        return value == nullptr ? std::string{} : value;
    }

    std::vector<std::string> getCmdLineVector(int argc, const char** argv)
    {
        return { argv, argv + argc };
    }

    bool isRunningInWine() { return false; }
    bool isStdOutRedirected() { return true; }
    bool hasTerminalVT100Support() { return false; }
    bool enableVT100TerminalMode() { return false; }
    bool lockSingleInstance() { return true; }
}
