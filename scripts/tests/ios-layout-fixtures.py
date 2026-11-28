"""Synthetic metadata/PNG-header fixtures, never Apple runtime evidence."""

SESSION = "00000000-0000-4000-8000-000000000001"
PLAN = (("landscape-left", 3, 0, 0), ("landscape-right", 4, 0, 0),
        ("portrait-return", 1, 0, 0), ("resize-wide", 1, 640, 480),
        ("resize-compact", 1, 320, 300), ("restore-full", 1, 0, 0))


def baseline(portrait=True):
    width, height = (834, 1210) if portrait else (1210, 834)
    result = dict(resultVersion=3, orientationPolicy="adaptive-setup", interfaceOrientation=1 if portrait else 3,
                  layoutSession=SESSION, stage="complete", failureReason="", passed=True,
                  gameplayStarted=False, frames=50, checks=3, cancellations=1, dialogsPresented=2,
                  dialogsDismissed=2, presentationPending=False, activeDialog=False, metalRenderer=True,
                  setupFillsScene=True, windowFillsScreen=True, drawableMatchesScreen=True,
                  setupFillsWindow=True, windowFitsScreen=True, drawableMatchesWindow=True,
                  screenX=0, screenY=0, windowScreenX=0, windowScreenY=0, screenScale=2,
                  pixelWidth=width*2, pixelHeight=height*2)
    for prefix in ("scene", "window", "setup", "screen", "windowScreen"):
        result[prefix+"Width"], result[prefix+"Height"] = width, height
    return result


def snapshots(initial):
    results = []
    for index, (name, orientation, width, height) in enumerate(PLAN):
        result = baseline(portrait=orientation == 1)
        result.update(layoutVersion=2, session=initial["layoutSession"], layoutStep=name,
                      rotationDriver="XCUIDevice.orientation", deviceOrientation={3: 4, 4: 3}.get(orientation, orientation),
                      requestedOrientation=orientation, interfaceOrientation=orientation,
                      requestedWidth=width, requestedHeight=height, stableFrames=3,
                      geometryError="", buttonVisible=True, buttonWidth=256, buttonHeight=48,
                      scrollHeight=(height or result["screenHeight"])-48, contentHeight=600,
                      requestFrames=initial["frames"]+10*index, framesAfterRequest=4,
                      frames=initial["frames"]+10*index+4,
                      operation="window-frame-resize" if width else "window-frame-restore" if name == "restore-full" else "device-rotation")
        if width:
            for prefix in ("window", "setup", "windowScreen"):
                result[prefix+"Width"], result[prefix+"Height"] = width, height
            result.update(windowScreenX=32, windowScreenY=64, setupFillsScene=False,
                          windowFillsScreen=False, drawableMatchesScreen=False,
                          pixelWidth=width*2, pixelHeight=height*2)
        results.append(result)
    return results
