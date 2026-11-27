#include <OpenLoco/Platform/Platform.h>
#include <OpenLoco/Version.hpp>
#include <SDL3/SDL.h>
#define SDL_MAIN_USE_CALLBACKS
#include <SDL3/SDL_main.h>
#import <UIKit/UIKit.h>
#include <exception>
#include <fstream>
#include <memory>
#include <string_view>

@interface OpenLocoSetupController : UIViewController
@property (nonatomic, strong) UILabel* statusLabel;
@property (nonatomic, strong) UIButton* checkButton;
@property (nonatomic) NSUInteger checks;
@property (nonatomic) NSUInteger cancellations;
- (void)checkGameData;
- (void)cancelCheck;
- (void)retryCheck;
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
    if (self.presentedViewController != nil)
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
    [self presentViewController:alert animated:NO completion:nil];
}

- (void)cancelCheck
{
    self.cancellations++;
    [self dismissViewControllerAnimated:NO completion:nil];
}

- (void)retryCheck
{
    self.checks++;
    self.statusLabel.text = @"Game data import is not available in this build.";
    [self dismissViewControllerAnimated:NO completion:nil];
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
        uint64_t smokeNextStep = 0;
        uint64_t frames = 0;
        int smokeStage = 0;
        int smokeDialogs = 0;
        bool smokeTest = false;
        bool background = false;
    };

    bool writeSmokeResult(const AppState& app)
    {
        const auto* rendererName = SDL_GetRendererName(app.renderer);
        const bool metal = rendererName != nullptr && std::string_view(rendererName) == "metal";
        int pixelWidth = 0;
        int pixelHeight = 0;
        const bool drawable = SDL_GetRenderOutputSize(app.renderer, &pixelWidth, &pixelHeight) && pixelWidth > 0 && pixelHeight > 0;
        const bool passed = metal && drawable && app.frames > 1 && app.smokeDialogs == 2 && app.setup.checks == 3 && app.setup.cancellations == 1 && app.setup.presentedViewController == nil;
        const auto path = OpenLoco::Platform::getUserDirectory() / "ios-smoke-result.json";
        auto stagingPath = path;
        stagingPath += ".tmp";
        std::ofstream result(stagingPath);
        result << "{\"passed\":" << (passed ? "true" : "false")
               << ",\"frames\":" << app.frames
               << ",\"checks\":" << app.setup.checks
               << ",\"cancellations\":" << app.setup.cancellations
               << ",\"dialogsPresented\":" << app.smokeDialogs
               << ",\"metalRenderer\":" << (metal ? "true" : "false")
               << ",\"pixelWidth\":" << pixelWidth
               << ",\"pixelHeight\":" << pixelHeight
               << ",\"gameplayStarted\":false}\n";
        result.close();
        if (!result.good())
        {
            return false;
        }
        std::error_code error;
        fs::rename(stagingPath, path, error);
        return passed && !error;
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
    if (!SDL_Init(SDL_INIT_VIDEO))
    {
        SDL_Log("SDL initialization failed: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }
    *appstate = app.release();
    auto& state = *static_cast<AppState*>(*appstate);
    state.window = SDL_CreateWindow("OpenLoco", 1024, 768, SDL_WINDOW_HIGH_PIXEL_DENSITY);
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
    state.setup.view.frame = root.view.bounds;
    state.setup.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root.view addSubview:state.setup.view];
    [state.setup didMoveToParentViewController:root];
    state.started = SDL_GetTicks();
    state.smokeNextStep = state.started + 1000;
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
    if (app.background)
    {
        return SDL_APP_CONTINUE;
    }
    SDL_SetRenderDrawColor(app.renderer, 18, 26, 36, 255);
    if (!SDL_RenderClear(app.renderer) || !SDL_RenderPresent(app.renderer))
    {
        SDL_Log("Presentation failed: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }
    app.frames++;

    // Exercise the actual setup action handlers across separate UIKit run-loop turns.
    // This is a smoke check, not a substitute for XCTest taps or real device tests.
    if (app.smokeTest && app.smokeStage <= 4 && SDL_GetTicks() >= app.smokeNextStep)
    {
        app.smokeNextStep = SDL_GetTicks() + 700;
        switch (app.smokeStage++)
        {
            case 0: [app.setup.checkButton sendActionsForControlEvents:UIControlEventTouchUpInside]; break;
            case 1:
                if (![app.setup.presentedViewController isKindOfClass:UIAlertController.class])
                {
                    return SDL_APP_FAILURE;
                }
                app.smokeDialogs++;
                [app.setup cancelCheck];
                break;
            case 2: [app.setup.checkButton sendActionsForControlEvents:UIControlEventTouchUpInside]; break;
            case 3:
                if (![app.setup.presentedViewController isKindOfClass:UIAlertController.class])
                {
                    return SDL_APP_FAILURE;
                }
                app.smokeDialogs++;
                [app.setup retryCheck];
                break;
            case 4:
                if (!writeSmokeResult(app))
                {
                    SDL_Log("OpenLoco iOS setup smoke check failed.");
                    return SDL_APP_FAILURE;
                }
                SDL_Log("OpenLoco iOS setup smoke check passed.");
                break;
        }
    }
    return SDL_APP_CONTINUE;
}

void SDL_AppQuit(void* appstate, SDL_AppResult)
{
    std::unique_ptr<AppState> app(static_cast<AppState*>(appstate));
    if (app)
    {
        [app->setup willMoveToParentViewController:nil];
        [app->setup.view removeFromSuperview];
        [app->setup removeFromParentViewController];
        SDL_DestroyRenderer(app->renderer);
        SDL_DestroyWindow(app->window);
    }
}
