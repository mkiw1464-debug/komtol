#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "bypass/Bypass.h"
#import "bypass/AntiDebug.h"
#import "features/Aimbot.h"
#import "features/ESP.h"
#import "ui/Menu.h"

@interface FFTicker : NSObject
@property (nonatomic, strong) CADisplayLink *link;
- (void)tick:(CADisplayLink*)dl;
@end
@implementation FFTicker
- (void)tick:(CADisplayLink*)dl {
    ESPCollect();
    AimbotTick();
    if (drawView) [drawView setNeedsDisplay];
}
@end

static FFTicker *g_Ticker  = nil;
static bool      g_InitDone = false;

static void DoInit() {
    if (g_InitDone) return;
    g_InitDone = true;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Bypass FIRST — before any Garena code runs
        InitAntiDebug();
        InitAllBypasses();
        // Give bypasses 800ms to hook everything
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 800*NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            InitMenu();
            g_Ticker = [FFTicker new];
            CADisplayLink *dl = [CADisplayLink
                displayLinkWithTarget:g_Ticker selector:@selector(tick:)];
            [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
            g_Ticker.link = dl;
            NSLog(@"[FFNET] V1.0.0 — 6767");
        });
    });
}

// Hook applicationDidFinishLaunching — earliest safe UIKit point
static void (*orig_didFinish)(id,SEL,UIApplication*,NSDictionary*) = nullptr;
static void fake_didFinish(id self, SEL cmd, UIApplication *app, NSDictionary *opts) {
    if (orig_didFinish) orig_didFinish(self, cmd, app, opts);
    DoInit();
}

__attribute__((constructor))
static void Initialize() {
    // Pure C bypass — safe at dylib load time
    InitAntiDebug();

    dispatch_async(dispatch_get_main_queue(), ^{
        // Find AppDelegate and hook didFinishLaunching
        Class found = nil;
        unsigned int n = 0;
        Class *all = objc_copyClassList(&n);
        for (unsigned i = 0; i < n; i++) {
            if (!class_conformsToProtocol(all[i], @protocol(UIApplicationDelegate))) continue;
            if (class_getInstanceMethod(all[i],
                    @selector(application:didFinishLaunchingWithOptions:))) {
                found = all[i]; break;
            }
        }
        free(all);

        if (found) {
            SEL sel = @selector(application:didFinishLaunchingWithOptions:);
            Method m = class_getInstanceMethod(found, sel);
            orig_didFinish = (void(*)(id,SEL,UIApplication*,NSDictionary*))
                              method_getImplementation(m);
            method_setImplementation(m, (IMP)fake_didFinish);
        } else {
            // Fallback — notification
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *n) { DoInit(); }];
        }
    });
}
