#include "IosLayoutChecks.h"
#include "IosSetupSmoke.h"
#include "IosViewGeometry.h"
#include <OpenLoco/Platform/Platform.h>
#include <OpenLoco/Version.hpp>
#include <SDL3/SDL.h>
#define SDL_MAIN_USE_CALLBACKS
#include <SDL3/SDL_main.h>
#include <TargetConditionals.h>
#import <UIKit/UIKit.h>
#include <dispatch/dispatch.h>
#include <exception>
#include <fstream>
#include <memory>
#include <sstream>
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
@property (nonatomic, strong) UIScrollView* setupScroll;
#if TARGET_OS_SIMULATOR
@property (nonatomic, copy) NSString* layoutRequestStep;
@property (nonatomic, copy) NSString* layoutRequestError;
#endif
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

    UIScrollView* scroll = [UIScrollView new];
    self.setupScroll = scroll;
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    UIView* content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];

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
    [content addSubview:stack];
    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint* preferredHeight = [content.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor];
    preferredHeight.priority = UILayoutPriorityDefaultLow;
    NSLayoutConstraint* preferredWidth = [stack.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-64];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [content.heightAnchor constraintGreaterThanOrEqualToAnchor:scroll.frameLayoutGuide.heightAnchor],
        preferredHeight,
        preferredWidth,
        [stack.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:560],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:content.leadingAnchor
                                                         constant:32],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor
                                                       constant:-32],
        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:content.topAnchor
                                                     constant:24],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor
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
        bool layoutTest = false;
        NSString* layoutSession = nil;
#if TARGET_OS_SIMULATOR
        OpenLoco::Ios::LayoutChecks layout;
        uint64_t layoutRequestFrame = 0;
#endif
    };

    OpenLoco::Ios::ViewGeometry readViewGeometry(const AppState& app)
    {
        OpenLoco::Ios::ViewGeometry geometry;
        UIWindow* window = app.setup.view.window;
        UIWindowScene* scene = window.windowScene;
        if (scene == nil)
        {
            return geometry;
        }
        const auto rect = [](CGRect value) {
            return OpenLoco::Ios::ViewRect{ value.origin.x, value.origin.y, value.size.width, value.size.height };
        };
        geometry.scene = rect(scene.coordinateSpace.bounds);
        geometry.windowInScene = rect([window convertRect:window.bounds toCoordinateSpace:scene.coordinateSpace]);
        geometry.windowBounds = rect(window.bounds);
        geometry.setupInWindow = rect([app.setup.view convertRect:app.setup.view.bounds toView:window]);
        geometry.screen = rect(scene.screen.coordinateSpace.bounds);
        geometry.windowInScreen = rect([window convertRect:window.bounds toCoordinateSpace:scene.screen.coordinateSpace]);
        geometry.scale = scene.screen.scale;
        if (app.renderer != nullptr && !SDL_GetRenderOutputSize(app.renderer, &geometry.pixelWidth, &geometry.pixelHeight))
        {
            geometry.pixelWidth = geometry.pixelHeight = 0;
        }
        return geometry;
    }

    std::string smokeJson(AppState& app, bool final)
    {
        const auto* rendererName = app.renderer != nullptr ? SDL_GetRendererName(app.renderer) : nullptr;
        const bool metal = rendererName != nullptr && std::string_view(rendererName) == "metal";
        const auto geometry = readViewGeometry(app);
        UIWindow* window = app.setup.view.window;
        const auto orientation = window.windowScene.effectiveGeometry.interfaceOrientation;
        const bool orientationKnown = UIInterfaceOrientationIsLandscape(orientation) || UIInterfaceOrientationIsPortrait(orientation);
        const bool passed = final && app.smoke.complete() && !app.smoke.failed() && metal && orientationKnown && geometry.fillsScreen() && geometry.drawableMatchesScreen() && app.frames > 1 && app.setup.dialogsPresented == 2 && app.setup.dialogsDismissed == 2 && app.setup.checks == 3 && app.setup.cancellations == 1 && app.setup.activeAlert == nil && !app.setup.dialogTransitionPending && app.setup.presentedViewController == nil;
        if (final && !passed && !app.smoke.failed())
        {
            if (!geometry.fillsScreen())
            {
                app.smoke.fail("screen-coverage-mismatch");
            }
            else if (!geometry.drawableMatchesScreen())
            {
                app.smoke.fail("drawable-screen-mismatch");
            }
            else
            {
                app.smoke.fail("final-verification-failed");
            }
        }
        std::ostringstream result;
        result << "{\"resultVersion\":3,\"passed\":" << (passed ? "true" : "false")
               << ",\"layoutSession\":\"" << (app.layoutSession != nil ? app.layoutSession.UTF8String : "") << "\""
               << ",\"orientationPolicy\":\"adaptive-setup\""
               << ",\"interfaceOrientation\":" << static_cast<int>(orientation)
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
               << ",\"pixelWidth\":" << geometry.pixelWidth
               << ",\"pixelHeight\":" << geometry.pixelHeight
               << ",\"setupFillsScene\":" << (geometry.fillsScene() ? "true" : "false")
               << ",\"windowFillsScreen\":" << (geometry.fillsScreen() ? "true" : "false")
               << ",\"drawableMatchesScreen\":" << (geometry.drawableMatchesScreen() ? "true" : "false")
               << ",\"setupFillsWindow\":" << (geometry.setupFillsWindow() ? "true" : "false")
               << ",\"windowFitsScreen\":" << (geometry.windowFitsScreen() ? "true" : "false")
               << ",\"drawableMatchesWindow\":" << (geometry.drawableMatchesWindow() ? "true" : "false")
               << ",\"sceneWidth\":" << geometry.scene.width << ",\"sceneHeight\":" << geometry.scene.height
               << ",\"windowWidth\":" << geometry.windowBounds.width << ",\"windowHeight\":" << geometry.windowBounds.height
               << ",\"setupWidth\":" << geometry.setupInWindow.width << ",\"setupHeight\":" << geometry.setupInWindow.height
               << ",\"screenX\":" << geometry.screen.x << ",\"screenY\":" << geometry.screen.y
               << ",\"screenWidth\":" << geometry.screen.width << ",\"screenHeight\":" << geometry.screen.height
               << ",\"windowScreenX\":" << geometry.windowInScreen.x << ",\"windowScreenY\":" << geometry.windowInScreen.y
               << ",\"windowScreenWidth\":" << geometry.windowInScreen.width << ",\"windowScreenHeight\":" << geometry.windowInScreen.height
               << ",\"screenScale\":" << geometry.scale
               << ",\"gameplayStarted\":false}\n";
        return result.str();
    }

    bool writeSmokeResult(AppState& app, bool final = true)
    {
        const auto path = OpenLoco::Platform::getUserDirectory() / (final ? "ios-smoke-result.json" : "ios-smoke-progress.json");
        auto stagingPath = path;
        stagingPath += ".tmp";
        std::ofstream result(stagingPath);
        result << smokeJson(app, final);
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

#if TARGET_OS_SIMULATOR
    NSString* layoutPath(NSString* name)
    {
        const auto path = OpenLoco::Platform::getUserDirectory() / name.UTF8String;
        return [NSString stringWithUTF8String:path.string().c_str()];
    }

    bool writeLayoutJson(NSDictionary* object, NSString* name)
    {
        NSError* error = nil;
        NSData* data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:&error];
        if (data == nil || ![data writeToFile:layoutPath(name) options:NSDataWritingAtomic error:&error])
        {
            SDL_Log("Layout evidence write failed: %s", error != nil ? error.localizedDescription.UTF8String : "unknown error");
            return false;
        }
        return true;
    }

    bool layoutAcknowledged(const AppState& app)
    {
        NSData* data = [NSData dataWithContentsOfFile:layoutPath(@"ios-layout-ack.json")];
        id ack = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nullptr] : nil;
        const int index = app.layout.index();
        NSString* step = index < 0 ? @"setup" : [NSString stringWithUTF8String:OpenLoco::Ios::kLayoutSteps[index].name];
        return [ack isKindOfClass:NSDictionary.class] && [ack[@"session"] isEqual:app.layoutSession] && [ack[@"step"] isEqual:step];
    }

    bool layoutButtonVisible(const AppState& app)
    {
        UIScrollView* scroll = app.setup.setupScroll;
        UIButton* button = app.setup.checkButton;
        return button.window != nil && button.enabled && !button.hidden && button.alpha > 0.95
            && CGRectContainsRect(CGRectInset(scroll.bounds, -0.5, -0.5), [button convertRect:button.bounds toView:scroll]);
    }

    bool tickLayoutChecks(AppState& app)
    {
        using Checks = OpenLoco::Ios::LayoutChecks;
        if (app.layout.done() || app.layout.failed())
        {
            return true;
        }
        const int index = app.layout.index();
        UIWindow* window = app.setup.view.window;
        UIWindowScene* scene = window.windowScene;
        const auto geometry = readViewGeometry(app);
        bool ready = false;
        if (index >= 0)
        {
            const auto& step = OpenLoco::Ios::kLayoutSteps[index];
            if (step.width > 0)
            {
                UIScrollView* scroll = app.setup.setupScroll;
                [scroll scrollRectToVisible:[app.setup.checkButton convertRect:app.setup.checkButton.bounds toView:scroll] animated:NO];
                ready = geometry.windowFitsScreen() && geometry.drawableMatchesWindow()
                    && std::abs(geometry.windowBounds.width - step.width) < 1 && std::abs(geometry.windowBounds.height - step.height) < 1;
            }
            else
            {
                ready = geometry.fillsScreen() && geometry.drawableMatchesScreen();
            }
            ready = ready && scene.activationState == UISceneActivationStateForegroundActive
                && static_cast<int>(scene.effectiveGeometry.interfaceOrientation) == step.orientation
                && window.rootViewController.transitionCoordinator == nil && layoutButtonVisible(app)
                && app.frames - app.layoutRequestFrame >= 2;
        }
        const auto action = app.layout.update(SDL_GetTicks(), layoutAcknowledged(app), ready, app.setup.layoutRequestError != nil);
        if (action == Checks::Action::begin)
        {
            const auto& step = OpenLoco::Ios::kLayoutSteps[app.layout.index()];
            app.layoutRequestFrame = app.frames;
            app.setup.layoutRequestError = nil;
            app.setup.layoutRequestStep = [NSString stringWithUTF8String:step.name];
            [app.setup.setupScroll setContentOffset:CGPointZero animated:NO];
            if (step.width > 0 || step.restoreWindow)
            {
                window.frame = step.width > 0 ? CGRectMake(32, 64, step.width, step.height) : scene.coordinateSpace.bounds;
                [window setNeedsLayout];
                [window layoutIfNeeded];
            }
            else
            {
                [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
                const auto mask = static_cast<UIInterfaceOrientationMask>(1u << step.orientation);
                UIWindowSceneGeometryPreferencesIOS* preference = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
                __weak OpenLocoSetupController* weakSetup = app.setup;
                NSString* requestStep = app.setup.layoutRequestStep;
                [scene requestGeometryUpdateWithPreferences:preference
                                               errorHandler:^(NSError* error) {
                                                   dispatch_async(dispatch_get_main_queue(), ^{
                                                       OpenLocoSetupController* setup = weakSetup;
                                                       if ([setup.layoutRequestStep isEqual:requestStep])
                                                       {
                                                           setup.layoutRequestError = error.localizedDescription;
                                                       }
                                                   });
                                               }];
            }
            SDL_Log("Layout request: %s", step.name);
        }
        if (action == Checks::Action::complete)
        {
            return writeLayoutJson(@{@"layoutVersion" : @1,
                                     @"passed" : @YES,
                                     @"session" : app.layoutSession,
                                     @"stepsCompleted" : @(OpenLoco::Ios::kLayoutSteps.size())},
                                   @"ios-layout-complete.json");
        }
        if (action == Checks::Action::begin || action == Checks::Action::capture || action == Checks::Action::failure)
        {
            const auto& step = OpenLoco::Ios::kLayoutSteps[app.layout.index()];
            const auto text = smokeJson(app, false);
            NSData* data = [NSData dataWithBytes:text.data() length:text.size()];
            NSMutableDictionary* snapshot = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nullptr];
            if (snapshot == nil)
            {
                SDL_Log("Layout snapshot serialization failed: %s", step.name);
                return false;
            }
            snapshot[@"layoutVersion"] = @1;
            snapshot[@"session"] = app.layoutSession;
            snapshot[@"layoutStep"] = [NSString stringWithUTF8String:step.name];
            snapshot[@"operation"] = step.width > 0 ? @"window-frame-resize" : step.restoreWindow ? @"window-frame-restore"
                                                                                                  : @"scene-orientation";
            snapshot[@"passed"] = @(action == Checks::Action::capture);
            snapshot[@"failureReason"] = [NSString stringWithUTF8String:app.layout.reason()];
            snapshot[@"geometryError"] = app.setup.layoutRequestError ?: @"";
            snapshot[@"requestedOrientation"] = @(step.orientation);
            snapshot[@"requestedWidth"] = @(step.width);
            snapshot[@"requestedHeight"] = @(step.height);
            snapshot[@"requestFrames"] = @(app.layoutRequestFrame);
            snapshot[@"framesAfterRequest"] = @(app.frames - app.layoutRequestFrame);
            snapshot[@"stableFrames"] = @(app.layout.stableFrames());
            snapshot[@"buttonVisible"] = @(layoutButtonVisible(app));
            snapshot[@"buttonWidth"] = @(app.setup.checkButton.bounds.size.width);
            snapshot[@"buttonHeight"] = @(app.setup.checkButton.bounds.size.height);
            snapshot[@"scrollHeight"] = @(app.setup.setupScroll.bounds.size.height);
            snapshot[@"contentHeight"] = @(app.setup.setupScroll.contentSize.height);
            if (!writeLayoutJson(snapshot, @"ios-layout-progress.json"))
            {
                return false;
            }
            if (action != Checks::Action::begin)
            {
                SDL_Log("Layout snapshot: %s; passed=%d; reason=%s", step.name, action == Checks::Action::capture, app.layout.reason());
                return writeLayoutJson(snapshot, [NSString stringWithFormat:@"ios-layout-%s.json", step.name]);
            }
        }
        return true;
    }
#endif
}

SDL_AppResult SDL_AppInit(void** appstate, int argc, char** argv)
{
    auto app = std::make_unique<AppState>();
    for (int i = 1; i < argc; ++i)
    {
        app->smokeTest |= std::string_view(argv[i]) == "--smoke-test";
        if (std::string_view(argv[i]) == "--layout-test")
        {
#if TARGET_OS_SIMULATOR
            app->layoutTest = app->smokeTest = true;
            app->layoutSession = NSUUID.UUID.UUIDString;
#else
            SDL_Log("Layout checks are available only in the simulator.");
            return SDL_APP_FAILURE;
#endif
        }
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
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight Portrait PortraitUpsideDown");
    if (!SDL_Init(SDL_INIT_VIDEO))
    {
        SDL_Log("SDL initialization failed: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }
    *appstate = app.release();
    auto& state = *static_cast<AppState*>(*appstate);
    state.window = SDL_CreateWindow("OpenLoco", 1024, 768, SDL_WINDOW_HIGH_PIXEL_DENSITY | SDL_WINDOW_FULLSCREEN | SDL_WINDOW_RESIZABLE);
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
    if (app.smokeTest && app.smokeResultWritten && !app.layoutTest)
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
    if (app.smokeTest && !app.smokeResultWritten)
    {
        using Smoke = OpenLoco::Ios::SetupSmoke;
        UIWindow* window = app.setup.view.window;
        UIAlertController* alert = app.setup.activeAlert;
        const auto geometry = readViewGeometry(app);
        const Smoke::Observation ui{
            .sceneReady = geometry.fillsScreen() && geometry.drawableMatchesScreen() && window.windowScene.activationState == UISceneActivationStateForegroundActive && window.rootViewController.transitionCoordinator == nil,
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
#if TARGET_OS_SIMULATOR
    if (app.layoutTest && app.smokeResultWritten && !app.smoke.failed() && !tickLayoutChecks(app))
    {
        return SDL_APP_FAILURE;
    }
#endif
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
