#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

// Standalone UI test: the unsigned application is installed by the host script.
// Do not link this helper into OpenLoco or change application orientation policy.
@interface RotationTests : XCTestCase
@end

@implementation RotationTests
- (void)testDeviceRotation
{
    self.continueAfterFailure = NO;
    XCUIDevice* device = XCUIDevice.sharedDevice;
    device.orientation = UIDeviceOrientationPortrait;
    XCTAssertEqual(device.orientation, UIDeviceOrientationPortrait, @"Simulator did not establish the portrait baseline");
    XCUIApplication* app = [[XCUIApplication alloc] initWithBundleIdentifier:@"io.openloco.ios.development"];
    app.launchArguments = @[ @"--smoke-test", @"--layout-test" ];
    [app launch];
    XCUIElement* button = app.buttons[@"setup.check"];
    NSPredicate* setup = [NSPredicate predicateWithFormat:@"exists == YES AND value MATCHES %@", @"rotation:[0-9A-Fa-f-]{36}:setup"];
    XCTNSPredicateExpectation* initial = [[XCTNSPredicateExpectation alloc] initWithPredicate:setup object:button];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[ initial ] timeout:300], XCTWaiterResultCompleted, @"No session-tagged setup marker");
    NSString* session = [[button.value componentsSeparatedByString:@":"] objectAtIndex:1];
    XCTAssertNotNil([[NSUUID alloc] initWithUUIDString:session]);
    // The host waits for this exact per-launch marker before acknowledging setup.
    // Otherwise a fast host could advance before this test has read the UUID.
    NSLog(@"OpenLoco rotation ready: %@", session);

    NSArray<NSString*>* steps = @[ @"landscape-left", @"landscape-right", @"portrait-return" ];
    // UIInterfaceOrientation landscapeLeft (3) is UIDeviceOrientation landscapeRight (4).
    NSArray<NSNumber*>* orientations = @[ @(UIDeviceOrientationLandscapeRight), @(UIDeviceOrientationLandscapeLeft), @(UIDeviceOrientationPortrait) ];
    for (NSUInteger index = 0; index < steps.count; ++index)
    {
        NSString* marker = [NSString stringWithFormat:@"rotation:%@:%@", session, steps[index]];
        NSString* failed = [NSString stringWithFormat:@"rotation:%@:failed", session];
        NSPredicate* requested = [NSPredicate predicateWithFormat:@"exists == YES AND (value == %@ OR value == %@)", marker, failed];
        XCTNSPredicateExpectation* stage = [[XCTNSPredicateExpectation alloc] initWithPredicate:requested object:button];
        XCTAssertEqual([XCTWaiter waitForExpectations:@[ stage ] timeout:240], XCTWaiterResultCompleted, @"Rotation stage never requested: %@", steps[index]);
        XCTAssertEqualObjects(button.value, marker, @"Native layout checks failed");
        device.orientation = (UIDeviceOrientation)orientations[index].integerValue;
        XCTAssertEqual(device.orientation, orientations[index].integerValue, @"Simulator did not accept device rotation");
        NSLog(@"OpenLoco rotation driver: session=%@ step=%@ device=%@", session, steps[index], orientations[index]);
    }

    // The host must validate and acknowledge every raw capture, including the
    // resized windows and final full-display restoration, before this can pass.
    NSString* complete = [NSString stringWithFormat:@"rotation:%@:complete", session];
    NSString* failed = [NSString stringWithFormat:@"rotation:%@:failed", session];
    NSPredicate* finished = [NSPredicate predicateWithFormat:@"exists == YES AND (value == %@ OR value == %@)", complete, failed];
    XCTNSPredicateExpectation* restored = [[XCTNSPredicateExpectation alloc] initWithPredicate:finished object:button];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[ restored ] timeout:600], XCTWaiterResultCompleted, @"Captures and restoration never completed");
    XCTAssertEqualObjects(button.value, complete, @"Native layout checks failed before restoration");
}
@end
