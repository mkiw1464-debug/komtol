#import "Bypass.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#include "../../fishhook/fishhook.h"
#include "../utils/Memory.h"

// ─── BYPASS 1: IDFV spoof ─────────────────────────────────────────────────────
static NSUUID *fakeidfv = nil;
static NSUUID *(*orig_idfv)(id,SEL) = nullptr;

static NSUUID *fake_idfv_impl(id self, SEL _cmd) {
    if (!fakeidfv) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSString *s = [ud objectForKey:@"ffnet_idfv_v2"];
        fakeidfv = s ? [[NSUUID alloc] initWithUUIDString:s] : nil;
        if (!fakeidfv) {
            fakeidfv = [NSUUID UUID];
            [ud setObject:[fakeidfv UUIDString] forKey:@"ffnet_idfv_v2"];
            [ud synchronize];
        }
    }
    return fakeidfv;
}

static void SpoofIdfv() {
    Method m = class_getInstanceMethod([UIDevice class],
                    @selector(identifierForVendor));
    if (!m) return;
    orig_idfv = (NSUUID*(*)(id,SEL))method_getImplementation(m);
    method_setImplementation(m, (IMP)fake_idfv_impl);
}

// ─── BYPASS 2: Hide dylib from image list ─────────────────────────────────────
static const char *(*orig_image_name)(uint32_t) = nullptr;

static const char *fake_image_name(uint32_t idx) {
    const char *n = orig_image_name(idx);
    if (n && (strstr(n,"FFNET")||strstr(n,"ffnet")||strstr(n,"cheat")))
        return "";
    return n;
}

static void HideFromDyldImageList() {
    struct rebinding r[] = {
        {"_dyld_get_image_name",(void*)fake_image_name,(void**)&orig_image_name}
    };
    rebind_symbols(r, 1);
}

// ─── BYPASS 3: Block antiban/report API ───────────────────────────────────────
static id (*orig_dataTask)(id,SEL,NSURLRequest*,id) = nullptr;

static id fake_dataTask(id self, SEL cmd, NSURLRequest *req, id cb) {
    NSString *url = req.URL.absoluteString;
    if (url) {
        NSArray *blocked = @[@"antiban",@"cheatdetect",@"integrity",
                             @"/report",@"battleye",@"garena.com/ac"];
        for (NSString *b in blocked) {
            if ([url containsString:b]) {
                if (cb) {
                    void(^block)(NSData*,NSURLResponse*,NSError*) = cb;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        block([NSData data], nil, nil);
                    });
                }
                return nil;
            }
        }
    }
    return orig_dataTask(self,cmd,req,cb);
}

static void HookAntibanAPI() {
    Class cls = NSClassFromString(@"NSURLSession");
    SEL sel = @selector(dataTaskWithRequest:completionHandler:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    orig_dataTask = (id(*)(id,SEL,NSURLRequest*,id))method_getImplementation(m);
    method_setImplementation(m, (IMP)fake_dataTask);
}

// ─── BYPASS 4: Bundle ID spoof ────────────────────────────────────────────────
static NSString *(*orig_bid)(id,SEL) = nullptr;
static NSString *fake_bid(id s, SEL c) { return @"com.dts.freefireth"; }

static void SpoofBundleID() {
    Method m = class_getInstanceMethod([NSBundle class],@selector(bundleIdentifier));
    if (!m) return;
    orig_bid = (NSString*(*)(id,SEL))method_getImplementation(m);
    method_setImplementation(m,(IMP)fake_bid);
}

// ─── BYPASS 5: Block JB/sideload path checks ─────────────────────────────────
static BOOL (*orig_fe)(id,SEL,NSString*) = nullptr;

static BOOL fake_fe(id self, SEL cmd, NSString *path) {
    static NSArray *jb = nil;
    if (!jb) jb = @[@"/Applications/Cydia",@"/usr/sbin/sshd",@"/bin/bash",
                     @"/private/var/lib/apt",@"/var/jb",
                     @"/usr/lib/libhooker",@"/usr/lib/substitute",
                     @"/.bootstrapped",@"/etc/apt"];
    for (NSString *p in jb) if ([path hasPrefix:p]) return NO;
    return orig_fe(self,cmd,path);
}

static void PatchFileExistsCheck() {
    Method m = class_getInstanceMethod([NSFileManager class],
                    @selector(fileExistsAtPath:));
    if (!m) return;
    orig_fe = (BOOL(*)(id,SEL,NSString*))method_getImplementation(m);
    method_setImplementation(m,(IMP)fake_fe);
}

// ─── BYPASS 6: Login token cache ─────────────────────────────────────────────
static void BypassLoginToken() {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *t = [d objectForKey:@"ffnet_session_v2"];
    if (t) [d setObject:t forKey:@"garena_auth_token"];
}

// ─── BYPASS 7: Timing evasion (unique) ───────────────────────────────────────
static void TimingEvasion() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 700*NSEC_PER_MSEC),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0), ^{
        HookAntibanAPI();
    });
}

// ─── BYPASS 8: CRC patch (best-effort, no crash if not found) ─────────────────
static void PatchCRCCheck() {
    const uint8_t pattern[] = {0x85,0xC0,0x0F,0x84};
    uintptr_t base  = GetImageBase();
    if (!base) return;
    uintptr_t limit = base + 0x6000000;
    for (uintptr_t i = base; i < limit - 4; i++) {
        // Safely check each byte — skip unmapped pages
        uint8_t buf[4] = {};
        vm_size_t sz = 0;
        if (vm_read_overwrite(mach_task_self(),i,4,(vm_address_t)buf,&sz)
            != KERN_SUCCESS) { i += 0xFFF; continue; }
        if (memcmp(buf, pattern, 4) == 0) {
            kern_return_t kr = vm_protect(mach_task_self(), i+2, 2, FALSE,
                VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE);
            if (kr == KERN_SUCCESS) {
                uint8_t p[] = {0x0F,0x85};
                memcpy((void*)(i+2), p, 2);
            }
            break;
        }
    }
}

// ─── Public API ───────────────────────────────────────────────────────────────
void InitAllBypasses() {
    SpoofIdfv();
    HideFromDyldImageList();
    PatchCRCCheck();
    TimingEvasion();       // HookAntibanAPI inside, delayed
    SpoofBundleID();
    PatchFileExistsCheck();
    BypassLoginToken();
}
void BypassAntiBan()          { HookAntibanAPI(); }
void BypassAntiCheat()        { PatchCRCCheck(); }
void BypassLogin()            { BypassLoginToken(); }
void BypassLobby()            { BypassLoginToken(); }
void BypassReport()           { HookAntibanAPI(); }
void BypassBlacklist()        { SpoofIdfv(); SpoofBundleID(); }
void BypassThirdPartyInstall(){ SpoofBundleID(); PatchFileExistsCheck(); }
void PatchIntegrityCheck()    { PatchCRCCheck(); }
void SpoofDeviceFingerprint() { SpoofIdfv(); }
void HideLibraryFromTaskList(){ HideFromDyldImageList(); }
void PatchJailbreakDetection(){ PatchFileExistsCheck(); }
