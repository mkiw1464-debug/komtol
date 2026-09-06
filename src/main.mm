#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "bypass/Bypass.h"
#import "bypass/AntiDebug.h"
#import "features/Aimbot.h"
#import "features/ESP.h"
#import "ui/Menu.h"

// ─── Game tick — runs on main thread via CADisplayLink ────────────────────────
@interface FFTicker : NSObject
@property (nonatomic, strong) CADisplayLink *link;
- (void)tick:(CADisplayLink*)dl;
@end

@implementation FFTicker
- (void)tick:(CADisplayLink*)dl {
    // ESPCollect and AimbotTick do safe memory reads — no crash risk
    ESPCollect();
    AimbotTick();
    // drawView setNeedsDisplay must be main thread — CADisplayLink already is
    if (drawView) [drawView setNeedsDisplay];
}
@end

static FFTicker *g_Ticker = nil;
static bool      g_Initialized = false;

// ─── Wait for UIApplication to be fully ready ─────────────────────────────────
// applicationDidBecomeActive fires after launch — safe point to init UI
static void HookAppDidBecomeActive();

static void (*orig_appDidBecomeActive)(id, SEL, UIApplication*) = nullptr;
static void swizzled_appDidBecomeActive(id self, SEL _cmd, UIApplication *app) {
    if (orig_appDidBecomeActive)
        orig_appDidBecomeActive(self, _cmd, app);

    if (g_Initialized) return;
    g_Initialized = true;

    // Now safe — UIWindow exists, main runloop running
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[FFNET] applicationDidBecomeActive — init start");
        InitAntiDebug();
        InitAllBypasses();
        InitMenu();

        g_Ticker = [FFTicker new];
        CADisplayLink *dl = [CADisplayLink
            displayLinkWithTarget:g_Ticker
                         selector:@selector(tick:)];
        [dl addToRunLoop:[NSRunLoop mainRunLoop]
                 forMode:NSRunLoopCommonModes];
        g_Ticker.link = dl;

        NSLog(@"[FFNET] V1.0.0 Beta — loaded 6767");
    });
}

static void HookAppDidBecomeActive() {
    // Find the app delegate class at runtime
    // Works regardless of what FF names their AppDelegate
    Class appDelegateClass = nil;

    // Walk all classes looking for UIApplicationDelegate implementors
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        if (!class_conformsToProtocol(cls, @protocol(UIApplicationDelegate)))
            continue;
        // Check if it implements applicationDidBecomeActive
        if (class_getInstanceMethod(cls,
                @selector(application:didFinishLaunchingWithOptions:))) {
            appDelegateClass = cls;
            break;
        }
    }
    free(classes);

    if (!appDelegateClass) {
        // Fallback — hook NSObject applicationDidBecomeActive
        NSLog(@"[FFNET] AppDelegate not found, using notification fallback");
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            if (g_Initialized) return;
            g_Initialized = true;
            dispatch_async(dispatch_get_main_queue(), ^{
                InitAntiDebug();
                InitAllBypasses();
                InitMenu();
                g_Ticker = [FFTicker new];
                CADisplayLink *dl = [CADisplayLink
                    displayLinkWithTarget:g_Ticker selector:@selector(tick:)];
                [dl addToRunLoop:[NSRunLoop mainRunLoop]
                         forMode:NSRunLoopCommonModes];
                g_Ticker.link = dl;
                NSLog(@"[FFNET] V1.0.0 Beta — loaded via notification 6767");
            });
        }];
        return;
    }

    // Swizzle applicationDidBecomeActive on the found AppDelegate
    SEL sel = @selector(applicationDidBecomeActive:);
    Method m = class_getInstanceMethod(appDelegateClass, sel);
    if (m) {
        orig_appDidBecomeActive =
            (void(*)(id,SEL,UIApplication*))method_getImplementation(m);
        method_setImplementation(m, (IMP)swizzled_appDidBecomeActive);
    } else {
        // Method doesn't exist yet — add it
        class_addMethod(appDelegateClass, sel,
                        (IMP)swizzled_appDidBecomeActive, "v@:@");
    }
}

// ─── Constructor ─────────────────────────────────────────────────────────────
// __attribute__((constructor)) fires during dylib load — before main().
// UIKit is NOT ready here. We ONLY set up the hook, nothing else.
__attribute__((constructor))
static void Initialize() {
    // Anti-debug can go here — it's pure C, no UIKit
    InitAntiDebug();

    // Hook app lifecycle — actual UI init happens inside the hook
    dispatch_async(dispatch_get_main_queue(), ^{
        HookAppDidBecomeActive();
    });
}
