#include "IosSetupSmoke.h"
#include <OpenLoco/Platform/Platform.h>
#include <OpenLoco/Version.hpp>
#include <SDL3/SDL.h>
#define SDL_MAIN_USE_CALLBACKS
#include <SDL3/SDL_main.h>
#import <UIKit/UIKit.h>
#include <cmath>
#include <exception>
#include <fstream>
#include <memory>
#include <string_view>

@interface OpenLocoSetupController : UIViewController
@property (nonatomic, strong) UILabel* statusLabel;
@property (nonatomic, strong) UIButton* checkButton;
@property (nonatomic) NSUInteger checks;
@property (nonatomic) NSUInteger cancellations;
@property (nonatomic, strong) UIAlertController* activeAlert;
@property (nonatomic) BOOL dialogTransitionPending;
@property (nonatomic) NSUInteger dialogsPresented;
@property (nonatomic) NSUInteger dialogsDismissed;
- (void)checkGameData;
- (void)cancelCheck;
- (void)retryCheck;
- (void)dismissGameData;
@end

@implementation OpenLocoSetupController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.10 blue:0.14 alpha:1.0];

    UILabel* title = [UILabel new];
    title.text = @"OpenLoco";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];
    title.textColor = UIColor.whiteColor;
    title.accessibilityIdentifier = @"setup.title";

    UILabel* description = [UILabel new];
    description.text = @"Your railway starts here.\n\nThis early build opens the setup screen. Game data import and gameplay are not available yet.\n\nNo original game files are included.";
    description.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    description.textColor = UIColor.whiteColor;
    description.numberOfLines = 0;
    description.adjustsFontForContentSizeCategory = YES;

    self.statusLabel = [UILabel new];
    self.statusLabel.text = @"Game data has not been checked.";
    self.statusLabel.textColor = UIColor.lightGrayColor;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.accessibilityIdentifier = @"setup.status";

    self.checkButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.checkButton.configuration = [UIButtonConfiguration filledButtonConfiguration];
    [self.checkButton setTitle:@"Check game data" forState:UIControlStateNormal];
    [self.checkButton addTarget:self action:@selector(checkGameData) forControlEvents:UIControlEventTouchUpInside];
    self.checkButton.accessibilityIdentifier = @"setup.check";

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[ title, description, self.statusLabel, self.checkButton ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 24;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:560],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor
                                                         constant:32],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor
                                                       constant:-32],
        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:safe.topAnchor
                                                     constant:24],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor
                                                     constant:-24],
        [self.checkButton.heightAnchor constraintGreaterThanOrEqualToConstant:48],
    ]];
}

- (void)checkGameData
{
    if (self.activeAlert != nil || self.dialogTransitionPending || self.presentedViewController != nil || self.view.window == nil)
    {
        return;
    }
    self.checks++;
    // Deliberately no importer or engine startup in the unsigned-build milestone.
    self.statusLabel.text = @"Game data import is not available in this build.";
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Game data needed"
                                                                   message:@"Keep your own copy of Locomotion ready. Import will be available in a later build."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak OpenLocoSetupController* weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction*) {
                                                [weakSelf cancelCheck];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Check again"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction*) {
                                                [weakSelf retryCheck];
                                            }]];
    self.activeAlert = alert;
    self.dialogTransitionPending = YES;
    [self presentViewController:alert
                       animated:NO
                     completion:^{
                         OpenLocoSetupController* strongSelf = weakSelf;
                         if (strongSelf != nil)
                         {
                             strongSelf.dialogsPresented++;
                             strongSelf.dialogTransitionPending = NO;
                         }
                     }];
}

- (void)cancelCheck
{
    if (self.activeAlert == nil || self.dialogTransitionPending)
    {
        return;
    }
    self.cancellations++;
    [self dismissGameData];
}

- (void)retryCheck
{
    if (self.activeAlert == nil || self.dialogTransitionPending)
    {
        return;
    }
    self.checks++;
    self.statusLabel.text = @"Game data import is not available in this build.";
    [self dismissGameData];
}

- (void)dismissGameData
{
    // Keep the alert until UIKit confirms dismissal, even if its presenting
    // controller's property has already cleared during the transition.
    self.dialogTransitionPending = YES;
    __weak OpenLocoSetupController* weakSelf = self;
    [self.activeAlert dismissViewControllerAnimated:NO
                                         completion:^{
                                             OpenLocoSetupController* strongSelf = weakSelf;
                                             if (strongSelf != nil)
                                             {
                                                 strongSelf.activeAlert = nil;
                                                 strongSelf.dialogsDismissed++;
                                                 strongSelf.dialogTransitionPending = NO;
                                             }
                                         }];
}
@end

namespace
{
    struct AppState
    {
        SDL_Window* window = nullptr;
        SDL_Renderer* renderer = nullptr;
        OpenLocoSetupController* setup = nil;
        uint64_t started = 0;
        uint64_t frames = 0;
        OpenLoco::Ios::SetupSmoke smoke;
        bool smokeResultWritten = false;
        bool smokeTest = false;
        bool background = false;
    };

    bool landscapeFillsScene(const AppState& app)
    {
        UIWindow* window = app.setup.view.window;
        UIWindowScene* scene = window.windowScene;
        if (scene == nil || !UIInterfaceOrientationIsLandscape(scene.effectiveGeometry.interfaceOrientation))
        {
            return false;
        }
        const CGRect sceneBounds = scene.coordinateSpace.bounds;
        const CGRect windowFrame = [window convertRect:window.bounds toCoordinateSpace:scene.coordinateSpace];
        const CGRect setupFrame = [app.setup.view convertRect:app.setup.view.bounds toView:window];
        const auto matches = [](CGRect a, CGRect b) {
            return std::abs(a.origin.x - b.origin.x) < 1 && std::abs(a.origin.y - b.origin.y) < 1
                && std::abs(a.size.width - b.size.width) < 1 && std::abs(a.size.height - b.size.height) < 1;
        };
        return sceneBounds.size.width > sceneBounds.size.height
            && matches(windowFrame, sceneBounds) && matches(setupFrame, window.bounds);
    }

    bool writeSmokeResult(AppState& app, bool final = true)
    {
        const auto* rendererName = app.renderer != nullptr ? SDL_GetRendererName(app.renderer) : nullptr;
        const bool metal = rendererName != nullptr && std::string_view(rendererName) == "metal";
        int pixelWidth = 0;
        int pixelHeight = 0;
        const bool drawable = app.renderer != nullptr && SDL_GetRenderOutputSize(app.renderer, &pixelWidth, &pixelHeight) && pixelWidth > 0 && pixelHeight > 0;
        UIWindow* window = app.setup.view.window;
        const CGSize sceneSize = window.windowScene.coordinateSpace.bounds.size;
        const CGSize windowSize = window.bounds.size;
        const CGSize setupSize = app.setup.view.bounds.size;
        const bool fillsScene = landscapeFillsScene(app);
        const bool passed = final && app.smoke.complete() && !app.smoke.failed() && metal && drawable && fillsScene && pixelWidth > pixelHeight && app.frames > 1 && app.setup.dialogsPresented == 2 && app.setup.dialogsDismissed == 2 && app.setup.checks == 3 && app.setup.cancellations == 1 && app.setup.activeAlert == nil && !app.setup.dialogTransitionPending && app.setup.presentedViewController == nil;
        if (final && !passed && !app.smoke.failed())
        {
            app.smoke.fail("final-verification-failed");
        }
        const auto path = OpenLoco::Platform::getUserDirectory() / (final ? "ios-smoke-result.json" : "ios-smoke-progress.json");
        auto stagingPath = path;
        stagingPath += ".tmp";
        std::ofstream result(stagingPath);
        result << "{\"resultVersion\":2,\"passed\":" << (passed ? "true" : "false")
               << ",\"stage\":\"" << app.smoke.stageName() << "\""
               << ",\"failureReason\":\"" << app.smoke.failureReason() << "\""
               << ",\"elapsedMs\":" << SDL_GetTicks() - app.started
               << ",\"frames\":" << app.frames
               << ",\"checks\":" << app.setup.checks
               << ",\"cancellations\":" << app.setup.cancellations
               << ",\"dialogsPresented\":" << app.setup.dialogsPresented
               << ",\"dialogsDismissed\":" << app.setup.dialogsDismissed
               << ",\"presentationPending\":" << (app.setup.dialogTransitionPending ? "true" : "false")
               << ",\"activeDialog\":" << (app.setup.activeAlert != nil ? "true" : "false")
               << ",\"metalRenderer\":" << (metal ? "true" : "false")
               << ",\"pixelWidth\":" << pixelWidth
               << ",\"pixelHeight\":" << pixelHeight
               << ",\"landscapeFillsScene\":" << (fillsScene ? "true" : "false")
               << ",\"sceneWidth\":" << sceneSize.width << ",\"sceneHeight\":" << sceneSize.height
               << ",\"windowWidth\":" << windowSize.width << ",\"windowHeight\":" << windowSize.height
               << ",\"setupWidth\":" << setupSize.width << ",\"setupHeight\":" << setupSize.height
               << ",\"gameplayStarted\":false}\n";
        result.close();
        if (!result.good())
        {
            SDL_Log("Could not write smoke evidence: %s", path.string().c_str());
            return false;
        }
        std::error_code error;
        fs::rename(stagingPath, path, error);
        if (error)
        {
            SDL_Log("Could not publish smoke evidence: %s", error.message().c_str());
        }
        app.smokeResultWritten |= final && !error;
        return !error;
    }
}

SDL_AppResult SDL_AppInit(void** appstate, int argc, char** argv)
{
    auto app = std::make_unique<AppState>();
    for (int i = 1; i < argc; ++i)
    {
        app->smokeTest |= std::string_view(argv[i]) == "--smoke-test";
    }
    try
    {
        OpenLoco::Platform::initialise();
    }
    catch (const std::exception& error)
    {
        SDL_Log("Application storage initialization failed: %s", error.what());
        return SDL_APP_FAILURE;
    }
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    if (!SDL_Init(SDL_INIT_VIDEO))
    {
        SDL_Log("SDL initialization failed: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }
    *appstate = app.release();
    auto& state = *static_cast<AppState*>(*appstate);
    state.window = SDL_CreateWindow("OpenLoco", 1024, 768, SDL_WINDOW_HIGH_PIXEL_DENSITY | SDL_WINDOW_FULLSCREEN);
    if (state.window != nullptr)
    {
        state.renderer = SDL_CreateRenderer(state.window, "metal");
    }
    if (state.window == nullptr || state.renderer == nullptr)
    {
        SDL_Log("Window/renderer creation failed: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }

    UIWindow* window = (__bridge UIWindow*)SDL_GetPointerProperty(SDL_GetWindowProperties(state.window), SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, nullptr);
    UIViewController* root = window.rootViewController;
    if (root == nil)
    {
        SDL_Log("SDL did not provide a UIKit root controller.");
        return SDL_APP_FAILURE;
    }
    state.setup = [OpenLocoSetupController new];
    [root addChildViewController:state.setup];
    state.setup.view.translatesAutoresizingMaskIntoConstraints = NO;
    [root.view addSubview:state.setup.view];
    [NSLayoutConstraint activateConstraints:@[
        [state.setup.view.leadingAnchor constraintEqualToAnchor:root.view.leadingAnchor],
        [state.setup.view.trailingAnchor constraintEqualToAnchor:root.view.trailingAnchor],
        [state.setup.view.topAnchor constraintEqualToAnchor:root.view.topAnchor],
        [state.setup.view.bottomAnchor constraintEqualToAnchor:root.view.bottomAnchor],
    ]];
    [state.setup didMoveToParentViewController:root];
    [root setNeedsUpdateOfSupportedInterfaceOrientations];
    UIWindowSceneGeometryPreferencesIOS* geometry = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape];
    [window.windowScene requestGeometryUpdateWithPreferences:geometry
                                                errorHandler:^(NSError* error) {
                                                    SDL_Log("Landscape geometry request failed: %s", error.localizedDescription.UTF8String);
                                                }];
    state.started = SDL_GetTicks();
    state.smoke = OpenLoco::Ios::SetupSmoke(state.started);
    if (state.smokeTest)
    {
        writeSmokeResult(state, false);
    }
    SDL_Log("OpenLoco iOS setup ready; renderer=%s; core=%s", SDL_GetRendererName(state.renderer), OpenLoco::Version::kVersion);
    return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppEvent(void* appstate, SDL_Event* event)
{
    auto& app = *static_cast<AppState*>(appstate);
    switch (event->type)
    {
        case SDL_EVENT_QUIT:
        case SDL_EVENT_TERMINATING:
            return SDL_APP_SUCCESS;
        case SDL_EVENT_WILL_ENTER_BACKGROUND:
            app.background = true;
            break;
        case SDL_EVENT_DID_ENTER_FOREGROUND:
            app.background = false;
            break;
    }
    return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppIterate(void* appstate)
{
    auto& app = *static_cast<AppState*>(appstate);
    // Keep the final app/dialog visible until the external checker captures it.
    // A failed JSON result still makes the external checker fail.
    if (app.smokeTest && app.smokeResultWritten)
    {
        return SDL_APP_CONTINUE;
    }
    if (app.background)
    {
        return SDL_APP_CONTINUE;
    }
    SDL_SetRenderDrawColor(app.renderer, 18, 26, 36, 255);
    if (!SDL_RenderClear(app.renderer) || !SDL_RenderPresent(app.renderer))
    {
        SDL_Log("Presentation failed: %s", SDL_GetError());
        if (app.smokeTest)
        {
            app.smoke.fail("render-presentation-failed");
            if (writeSmokeResult(app))
            {
                return SDL_APP_CONTINUE;
            }
        }
        return SDL_APP_FAILURE;
    }
    app.frames++;

    // Exercise the actual setup action handlers across separate UIKit run-loop turns.
    // This is a smoke check, not a substitute for XCTest taps or real device tests.
    if (app.smokeTest)
    {
        using Smoke = OpenLoco::Ios::SetupSmoke;
        UIWindow* window = app.setup.view.window;
        UIAlertController* alert = app.setup.activeAlert;
        const Smoke::Observation ui{
            .sceneReady = landscapeFillsScene(app) && window.windowScene.activationState == UISceneActivationStateForegroundActive && window.rootViewController.transitionCoordinator == nil,
            .dialogReady = alert != nil && !app.setup.dialogTransitionPending && alert.viewIfLoaded.window != nil && !alert.isBeingPresented && !alert.isBeingDismissed,
            .dialogIdle = alert == nil && !app.setup.dialogTransitionPending && app.setup.presentedViewController == nil,
            .checks = app.setup.checks,
            .cancellations = app.setup.cancellations,
            .presentations = app.setup.dialogsPresented,
            .dismissals = app.setup.dialogsDismissed,
        };
        const auto previous = app.smoke.stage();
        const auto action = app.smoke.update(SDL_GetTicks(), ui);
        switch (action)
        {
            case Smoke::Action::openDialog: [app.setup.checkButton sendActionsForControlEvents:UIControlEventTouchUpInside]; break;
            case Smoke::Action::cancelDialog: [app.setup cancelCheck]; break;
            case Smoke::Action::retryDialog: [app.setup retryCheck]; break;
            default: break;
        }
        if (previous != app.smoke.stage() || action == Smoke::Action::failure)
        {
            SDL_Log("Setup smoke stage=%s; reason=%s; checks=%lu; presentations=%lu; dismissals=%lu; pending=%d", app.smoke.stageName(), app.smoke.failureReason(), static_cast<unsigned long>(app.setup.checks), static_cast<unsigned long>(app.setup.dialogsPresented), static_cast<unsigned long>(app.setup.dialogsDismissed), app.setup.dialogTransitionPending);
            writeSmokeResult(app, false);
        }
        if (action == Smoke::Action::success || action == Smoke::Action::failure)
        {
            if (!writeSmokeResult(app))
            {
                return SDL_APP_FAILURE;
            }
            SDL_Log("OpenLoco iOS setup smoke check %s.", app.smoke.failed() ? "failed" : "passed");
        }
    }
    return SDL_APP_CONTINUE;
}

void SDL_AppQuit(void* appstate, SDL_AppResult)
{
    std::unique_ptr<AppState> app(static_cast<AppState*>(appstate));
    if (app)
    {
        if (app->smokeTest && !app->smokeResultWritten)
        {
            app->smoke.fail("application-exited-before-smoke-completion");
            writeSmokeResult(*app);
        }
        [app->setup willMoveToParentViewController:nil];
        [app->setup.view removeFromSuperview];
        [app->setup removeFromParentViewController];
        SDL_DestroyRenderer(app->renderer);
        SDL_DestroyWindow(app->window);
    }
}
