#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

@interface DisplaySwitchHotkey : NSObject <NSApplicationDelegate>
- (void)switchToPC;
- (void)switchToPCFromHotKey:(UInt32)identifier;
- (void)recordKeyEvent:(NSString *)message;
@end

static DisplaySwitchHotkey *appDelegate;

@interface KeyCaptureView : NSView
@property (strong) NSTextField *label;
@end

@implementation KeyCaptureView

- (BOOL)acceptsFirstResponder { return YES; }

- (void)showEvent:(NSEvent *)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    NSString *message = [NSString stringWithFormat:@"keyCode=%hu control=%d option=%d shift=%d command=%d",
                         event.keyCode,
                         !!(flags & NSEventModifierFlagControl),
                         !!(flags & NSEventModifierFlagOption),
                         !!(flags & NSEventModifierFlagShift),
                         !!(flags & NSEventModifierFlagCommand)];
    self.label.stringValue = message;
    [appDelegate recordKeyEvent:message];
}

- (void)flagsChanged:(NSEvent *)event { [self showEvent:event]; }
- (void)keyDown:(NSEvent *)event { [self showEvent:event]; }
@end

static OSStatus HandleHotKey(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    EventHotKeyID hotKeyID = {0, 0};
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                          NULL, sizeof(hotKeyID), NULL, &hotKeyID) != noErr) return eventNotHandledErr;
    if (hotKeyID.signature != 'DSHK' || (hotKeyID.id != 1 && hotKeyID.id != 2)) return eventNotHandledErr;
    dispatch_async(dispatch_get_main_queue(), ^{ [appDelegate switchToPCFromHotKey:hotKeyID.id]; });
    return noErr;
}

@interface DisplaySwitchHotkey ()
@property (strong) NSStatusItem *statusItem;
@property (strong) NSMenuItem *stateItem;
@property (strong) NSURL *projectRoot;
@property (strong) NSDate *lastTrigger;
@property (strong) NSWindow *captureWindow;
@property (assign) BOOL busy;
@property (assign) EventHotKeyRef hotKeyRef;
@property (assign) EventHotKeyRef optionHotKeyRef;
@property (assign) EventHandlerRef eventHandlerRef;
@end

@implementation DisplaySwitchHotkey

- (NSURL *)switchScript {
    return [self.projectRoot URLByAppendingPathComponent:@"scripts/display-switch"];
}

- (NSURL *)logFile {
    return [self.projectRoot URLByAppendingPathComponent:@".local/logs/mac-hotkey.log"];
}

- (void)log:(NSString *)message {
    NSURL *file = self.logFile;
    [[NSFileManager defaultManager] createDirectoryAtURL:[file URLByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    if (![[NSFileManager defaultManager] fileExistsAtPath:file.path]) {
        [[NSFileManager defaultManager] createFileAtPath:file.path contents:nil attributes:nil];
    }
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], message];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:file.path];
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.projectRoot = [[[NSBundle mainBundle].bundleURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
    self.lastTrigger = [NSDate distantPast];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"⇄";
    self.statusItem.button.toolTip = @"Display Switch: Control+Command/Option+Shift+M";

    NSMenu *menu = [NSMenu new];
    self.stateItem = [[NSMenuItem alloc] initWithTitle:@"Starting…" action:nil keyEquivalent:@""];
    self.stateItem.enabled = NO;
    [menu addItem:self.stateItem];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *switchItem = [[NSMenuItem alloc] initWithTitle:@"Switch to PC" action:@selector(switchToPC) keyEquivalent:@""];
    switchItem.target = self;
    [menu addItem:switchItem];
    NSMenuItem *checkItem = [[NSMenuItem alloc] initWithTitle:@"Check Keys…" action:@selector(checkKeys) keyEquivalent:@""];
    checkItem.target = self;
    [menu addItem:checkItem];
    NSMenuItem *logItem = [[NSMenuItem alloc] initWithTitle:@"Open Log" action:@selector(openLog) keyEquivalent:@""];
    logItem.target = self;
    [menu addItem:logItem];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Display Switch" action:@selector(quit) keyEquivalent:@""];
    quitItem.target = self;
    [menu addItem:quitItem];
    self.statusItem.menu = menu;

    EventTypeSpec eventType = {kEventClassKeyboard, kEventHotKeyPressed};
    OSStatus handlerStatus = InstallEventHandler(GetEventDispatcherTarget(), HandleHotKey, 1,
                                                 &eventType, NULL, &_eventHandlerRef);
    if (handlerStatus != noErr) {
        self.stateItem.title = [NSString stringWithFormat:@"Hotkey registration failed (%d)", (int)handlerStatus];
        [self log:[NSString stringWithFormat:@"event handler failed: %d", (int)handlerStatus]];
        return;
    }
    EventHotKeyID hotKeyID = {'DSHK', 1};
    // Register both common Mac mappings for the physical Alt key.
    OSStatus keyStatus = RegisterEventHotKey(kVK_ANSI_M, controlKey | cmdKey | shiftKey,
                                            hotKeyID, GetEventDispatcherTarget(), 0, &_hotKeyRef);
    if (keyStatus != noErr) {
        self.stateItem.title = [NSString stringWithFormat:@"Hotkey unavailable (%d)", (int)keyStatus];
        [self log:[NSString stringWithFormat:@"hotkey registration failed: %d", (int)keyStatus]];
        return;
    }
    EventHotKeyID optionID = {'DSHK', 2};
    OSStatus optionStatus = RegisterEventHotKey(kVK_ANSI_M, controlKey | optionKey | shiftKey,
                                               optionID, GetEventDispatcherTarget(), 0, &_optionHotKeyRef);
    if (optionStatus != noErr) {
        [self log:[NSString stringWithFormat:@"optional Control+Option+Shift+M registration failed: %d", (int)optionStatus]];
    }
    self.stateItem.title = @"Ready: Control+Command/Option+Shift+M";
    [self log:[NSString stringWithFormat:@"started pid=%d; Control+Command+Shift+M registered", getpid()]];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.hotKeyRef) UnregisterEventHotKey(self.hotKeyRef);
    if (self.optionHotKeyRef) UnregisterEventHotKey(self.optionHotKeyRef);
    if (self.eventHandlerRef) RemoveEventHandler(self.eventHandlerRef);
    [self log:@"stopped"];
}

- (void)finish:(NSString *)message success:(BOOL)success {
    [self log:message];
    self.stateItem.title = success ? @"Ready: Control+Command/Option+Shift+M" : @"Last switch failed; open log";
    self.busy = NO;
}

- (void)switchToPC {
    [self startSwitchWithSource:@"menu action"];
}

- (void)switchToPCFromHotKey:(UInt32)identifier {
    NSString *source = identifier == 1 ? @"Control+Command+Shift+M hotkey" : @"Control+Option+Shift+M hotkey";
    [self startSwitchWithSource:source];
}

- (void)startSwitchWithSource:(NSString *)source {
    NSDate *now = [NSDate date];
    if (self.busy || [now timeIntervalSinceDate:self.lastTrigger] < 5) return;
    self.busy = YES;
    self.lastTrigger = now;
    self.stateItem.title = @"Switching to PC…";
    [self log:[NSString stringWithFormat:@"%@ received", source]];

    NSURL *script = self.switchScript;
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:script.path]) {
        [self finish:[NSString stringWithFormat:@"switch script missing or not executable: %@", script.path] success:NO];
        return;
    }
    NSTask *task = [NSTask new];
    task.executableURL = script;
    task.arguments = @[@"pc"];
    task.currentDirectoryURL = self.projectRoot;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [self finish:[NSString stringWithFormat:@"could not start switch script: %@", error] success:NO];
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"<non-UTF8 output>";
        output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        int code = task.terminationStatus;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finish:[NSString stringWithFormat:@"switch exit=%d; %@", code, output] success:(code == 0)];
        });
    });
}

- (void)openLog {
    [[NSWorkspace sharedWorkspace] openURL:self.logFile];
}

- (void)recordKeyEvent:(NSString *)message {
    [self log:[NSString stringWithFormat:@"key check: %@", message]];
}

- (void)checkKeys {
    if (!self.captureWindow) {
        NSRect frame = NSMakeRect(0, 0, 520, 130);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
            backing:NSBackingStoreBuffered defer:NO];
        window.title = @"Display Switch — Check Keys";
        window.releasedWhenClosed = NO;
        KeyCaptureView *view = [[KeyCaptureView alloc] initWithFrame:frame];
        NSTextField *label = [NSTextField labelWithString:@"Press your intended shortcut here to inspect its modifiers."];
        label.frame = NSMakeRect(20, 48, 480, 40);
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.maximumNumberOfLines = 2;
        view.label = label;
        [view addSubview:label];
        window.contentView = view;
        self.captureWindow = window;
    }
    [self.captureWindow center];
    [self.captureWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.captureWindow makeFirstResponder:self.captureWindow.contentView];
    [self log:@"key check opened"];
}

- (void)quit {
    [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        appDelegate = [DisplaySwitchHotkey new];
        application.delegate = appDelegate;
        [application run];
    }
    return 0;
}
