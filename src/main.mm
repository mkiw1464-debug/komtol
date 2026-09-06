#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "bypass/Bypass.h"
#import "bypass/AntiDebug.h"
#import "features/Aimbot.h"
#import "features/ESP.h"
#import "ui/Menu.h"

@interface FFTicker:NSObject
@property (nonatomic,strong) CADisplayLink *link;
-(void)tick:(CADisplayLink*)dl;
@end
@implementation FFTicker
-(void)tick:(CADisplayLink*)dl{
    ESPCollect(); AimbotTick();
    if(drawView)[drawView setNeedsDisplay];
}
@end

static FFTicker *g_Ticker  = nil;
static bool      g_Done    = false;

static void DoInit(){
    if(g_Done)return; g_Done=true;
    // Bypass fires FIRST on main thread immediately
    InitAllBypasses();
    dispatch_async(dispatch_get_main_queue(),^{
        InitMenu();
        g_Ticker=[FFTicker new];
        CADisplayLink *dl=[CADisplayLink displayLinkWithTarget:g_Ticker selector:@selector(tick:)];
        [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        g_Ticker.link=dl;
        NSLog(@"[FFNET] ready 6767");
    });
}

// Hook earliest possible AppDelegate method
static BOOL (*orig_finish)(id,SEL,UIApplication*,NSDictionary*)=nullptr;
static BOOL fake_finish(id self,SEL cmd,UIApplication *app,NSDictionary *opts){
    DoInit();
    return orig_finish?orig_finish(self,cmd,app,opts):YES;
}

__attribute__((constructor))
static void Initialize(){
    // Pure C — safe at dylib load
    InitAntiDebug();
    // Hook network at C level immediately (before ObjC runtime fully ready)
    InitAllBypasses();

    dispatch_async(dispatch_get_main_queue(),^{
        // Find AppDelegate, hook didFinishLaunching
        unsigned int n=0;
        Class *all=objc_copyClassList(&n);
        Class found=nil;
        for(unsigned i=0;i<n;i++){
            if(!class_conformsToProtocol(all[i],@protocol(UIApplicationDelegate)))continue;
            SEL s=@selector(application:didFinishLaunchingWithOptions:);
            if(class_getInstanceMethod(all[i],s)){found=all[i];break;}
        }
        free(all);
        if(found){
            SEL s=@selector(application:didFinishLaunchingWithOptions:);
            Method m=class_getInstanceMethod(found,s);
            orig_finish=(BOOL(*)(id,SEL,UIApplication*,NSDictionary*))method_getImplementation(m);
            method_setImplementation(m,(IMP)fake_finish);
        }
        // Also hook via notification as fallback
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n){DoInit();}];
    });
}
