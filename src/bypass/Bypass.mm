#import "Bypass.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <netdb.h>
#import <sys/socket.h>
#include "../../fishhook/fishhook.h"
#include "../utils/Memory.h"

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 1: IDFV spoof — stable fake UUID persisted across launches
// ═══════════════════════════════════════════════════════════════════════════════
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

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 2: Hide dylib from _dyld_get_image_name
// ═══════════════════════════════════════════════════════════════════════════════
static const char *(*orig_image_name)(uint32_t) = nullptr;

static const char *fake_image_name(uint32_t idx) {
    const char *n = orig_image_name(idx);
    if (n && (strstr(n,"FFNET")||strstr(n,"ffnet")||strstr(n,"cheat")||
              strstr(n,"komtol")||strstr(n,"inject")||strstr(n,"hook")))
        return "";
    return n;
}

static void HideFromDyldImageList() {
    struct rebinding r[] = {
        {"_dyld_get_image_name",(void*)fake_image_name,(void**)&orig_image_name}
    };
    rebind_symbols(r, 1);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 3: DNS block — getaddrinfo hook via fishhook
// Kills anticheat phone-home at the resolver level — URL session never fires
// ═══════════════════════════════════════════════════════════════════════════════
static const char *BLOCKED_DNS[] = {
    // Garena anticheat / telemetry
    "security.garena.com",
    "anticheat.garena.com",
    "fg.garena.com",
    "log.garena.com",
    "report.garena.com",
    "crash.garena.com",
    "ds.garena.com",
    "detect.garena.com",
    "sdk.garena.com",
    "analytics.garena.com",
    "stat.garena.com",
    "monitor.garena.com",
    "trace.garena.com",
    "event.garena.com",
    // Free Fire specific
    "ff.garena.com",
    "ffstats.garena.com",
    "fflog.garena.com",
    "ff-log.garena.com",
    "fflive.garena.com",
    "ffban.garena.com",
    "ffcheat.garena.com",
    "ffac.garena.com",
    "ffintegrity.garena.com",
    // ACE anticheat (used by Garena)
    "anticheat.battleye.com",
    "cloud.battleye.com",
    "report.battleye.com",
    // Tencent anticheat (FF hybrid)
    "msdk.qq.com",
    "report.msdk.qq.com",
    "stat.msdk.qq.com",
    "log.msdk.qq.com",
    "beacon.qq.com",
    "bugs.qq.com",
    // GBox sideload detection phone-home
    "api.gbox.cloud",
    "device.gbox.cloud",
    "verify.gbox.cloud",
    "auth.gbox.cloud",
    "log.gbox.cloud",
    // AltStore/TrollStore
    "api.altstore.io",
    "updates.altstore.io",
    NULL
};

static BOOL isDNSBlocked(const char *host) {
    if (!host) return NO;
    for (int i = 0; BLOCKED_DNS[i]; i++) {
        if (strstr(host, BLOCKED_DNS[i])) return YES;
    }
    // Block any subdomain of garena.com that's security/AC related
    if (strstr(host, "garena.com")) {
        const char *ac_subs[] = {"ac","anticheat","security","detect","report",
                                  "ban","integrity","log","stat","monitor",NULL};
        for (int i = 0; ac_subs[i]; i++) {
            if (strstr(host, ac_subs[i])) return YES;
        }
    }
    return NO;
}

static int (*orig_getaddrinfo)(const char*, const char*,
                               const struct addrinfo*,
                               struct addrinfo**) = nullptr;

static int hook_getaddrinfo(const char *node, const char *service,
                             const struct addrinfo *hints,
                             struct addrinfo **res) {
    if (isDNSBlocked(node)) return EAI_NONAME;
    return orig_getaddrinfo(node, service, hints, res);
}

static void HookDNS() {
    struct rebinding r[] = {
        {"getaddrinfo", (void*)hook_getaddrinfo, (void**)&orig_getaddrinfo}
    };
    rebind_symbols(r, 1);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 4: NSURLSession dataTask block — second layer after DNS
// Catches any requests that bypass resolver (preconnect, HTTP/2 coalescing)
// ═══════════════════════════════════════════════════════════════════════════════
static id (*orig_dataTask)(id,SEL,NSURLRequest*,id) = nullptr;

static id fake_dataTask(id self, SEL cmd, NSURLRequest *req, id cb) {
    NSString *url = req.URL.absoluteString;
    if (url) {
        NSArray *blocked = @[
            @"antiban", @"cheatdetect", @"integrity", @"/report",
            @"battleye", @"garena.com/ac", @"garena.com/security",
            @"garena.com/log", @"garena.com/stat", @"garena.com/detect",
            @"garena.com/ban", @"garena.com/monitor", @"msdk.qq.com",
            @"beacon.qq.com", @"gbox.cloud", @"altstore.io",
        ];
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

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 5: Bundle ID spoof
// ═══════════════════════════════════════════════════════════════════════════════
static NSString *(*orig_bid)(id,SEL) = nullptr;
static NSString *fake_bid(id s, SEL c) { return @"com.dts.freefireth"; }

static void SpoofBundleID() {
    Method m = class_getInstanceMethod([NSBundle class],@selector(bundleIdentifier));
    if (!m) return;
    orig_bid = (NSString*(*)(id,SEL))method_getImplementation(m);
    method_setImplementation(m,(IMP)fake_bid);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 6: fileExistsAtPath — block JB + sideload path detection
// ═══════════════════════════════════════════════════════════════════════════════
static BOOL (*orig_fe)(id,SEL,NSString*) = nullptr;

static BOOL fake_fe(id self, SEL cmd, NSString *path) {
    static NSArray *blocked = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        blocked = @[
            // JB indicators
            @"/Applications/Cydia", @"/usr/sbin/sshd", @"/bin/bash",
            @"/private/var/lib/apt", @"/var/jb", @"/usr/lib/libhooker",
            @"/usr/lib/substitute", @"/.bootstrapped", @"/etc/apt",
            @"/Library/MobileSubstrate", @".cydiasubstrate",
            @"libsubstrate", @"Substrate", @"/usr/lib/TweakInject",
            // Sideload store apps
            @"/Applications/GBox.app", @"GBox.app",
            @"/Applications/TrollStore.app", @"TrollStore",
            @"/Applications/AltStore.app", @"AltStore",
            @"/Applications/Sileo.app", @"Sileo",
            @"/Applications/Zebra.app",
            // GBox internal paths
            @"gbox", @"GBox", @"com.gbox",
            // Codesign bypass tools
            @"ldid", @"appsync",
        ];
    });
    for (NSString *p in blocked)
        if ([path containsString:p]) return NO;
    return orig_fe(self,cmd,path);
}

static void PatchFileExistsCheck() {
    Method m = class_getInstanceMethod([NSFileManager class],
                    @selector(fileExistsAtPath:));
    if (!m) return;
    orig_fe = (BOOL(*)(id,SEL,NSString*))method_getImplementation(m);
    method_setImplementation(m,(IMP)fake_fe);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 7: NSProcessInfo environment — scrub DYLD_INSERT_LIBRARIES
// GBox/sideload injects via DYLD; AC reads env to detect it
// ═══════════════════════════════════════════════════════════════════════════════
static NSDictionary *(*orig_env)(id,SEL) = nullptr;

static NSDictionary *fake_env(id self, SEL _cmd) {
    NSMutableDictionary *env = [orig_env(self, _cmd) mutableCopy];
    NSArray *strip = @[
        @"DYLD_INSERT_LIBRARIES", @"DYLD_LIBRARY_PATH",
        @"DYLD_FRAMEWORK_PATH",   @"_MSSafeMode",
        @"SUBSTRATE_ACTIVE",      @"GBOX_INJECT",
        @"ALTSTORE_INJECT",
    ];
    for (NSString *k in strip) [env removeObjectForKey:k];
    return [env copy];
}

static void HookEnvVars() {
    Method m = class_getInstanceMethod([NSProcessInfo class],
                    @selector(environment));
    if (!m) return;
    orig_env = (NSDictionary*(*)(id,SEL))method_getImplementation(m);
    method_setImplementation(m, (IMP)fake_env);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 8: AppStore receipt URL spoof
// FF checks [[NSBundle mainBundle] appStoreReceiptURL] to verify AppStore install
// GBox/sideload apps get a sandbox receipt path — we return the AppStore path
// ═══════════════════════════════════════════════════════════════════════════════
static NSURL *(*orig_receiptURL)(id,SEL) = nullptr;

static NSURL *fake_receiptURL(id self, SEL _cmd) {
    // Return the canonical AppStore receipt path
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *receiptPath = [bundlePath stringByAppendingPathComponent:
                             @"_MASReceipt/receipt"];
    return [NSURL fileURLWithPath:receiptPath];
}

static void SpoofReceiptURL() {
    Method m = class_getInstanceMethod([NSBundle class],
                    @selector(appStoreReceiptURL));
    if (!m) return;
    orig_receiptURL = (NSURL*(*)(id,SEL))method_getImplementation(m);
    method_setImplementation(m, (IMP)fake_receiptURL);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 9: LSApplicationProxy spoof — AppStore install source markers
// FF reads private LSApplicationProxy properties to check install origin
// ═══════════════════════════════════════════════════════════════════════════════
static id (*orig_lsValueForKey)(id,SEL,NSString*) = nullptr;

static id fake_lsValueForKey(id self, SEL _cmd, NSString *key) {
    // Spoof install source properties to look like AppStore install
    if ([key isEqualToString:@"ApplicationVariant"])        return @"Bitcode";
    if ([key isEqualToString:@"StoreAccountType"])          return @(1);
    if ([key isEqualToString:@"DownloadTaskIdentifier"])    return @"0";
    if ([key isEqualToString:@"IsAdHocSigned"])             return @(NO);
    if ([key isEqualToString:@"SignerOrganization"])        return @"Apple Inc.";
    if ([key isEqualToString:@"SignerOrganizationalUnit"])  return @"";
    return orig_lsValueForKey(self, _cmd, key);
}

static void SpoofLSApplicationProxy() {
    Class cls = objc_getClass("LSApplicationProxy");
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, @selector(valueForKey:));
    if (!m) return;
    orig_lsValueForKey = (id(*)(id,SEL,NSString*))method_getImplementation(m);
    method_setImplementation(m, (IMP)fake_lsValueForKey);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 10: Login token cache
// ═══════════════════════════════════════════════════════════════════════════════
static void BypassLoginToken() {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *t = [d objectForKey:@"ffnet_session_v2"];
    if (t) [d setObject:t forKey:@"garena_auth_token"];
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 11: CRC check patch
// ═══════════════════════════════════════════════════════════════════════════════
static void PatchCRCCheck() {
    const uint8_t pattern[] = {0x85,0xC0,0x0F,0x84};
    uintptr_t base  = GetImageBase();
    if (!base) return;
    uintptr_t limit = base + 0x6000000;
    for (uintptr_t i = base; i < limit - 4; i++) {
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

// ═══════════════════════════════════════════════════════════════════════════════
// Timing evasion — delay network hooks so they install after AC init window
// ═══════════════════════════════════════════════════════════════════════════════
static void TimingEvasion() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 700*NSEC_PER_MSEC),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0), ^{
        HookAntibanAPI();
    });
}

// ═══════════════════════════════════════════════════════════════════════════════
// Public API
// ═══════════════════════════════════════════════════════════════════════════════
void InitAllBypasses() {
    // Immediate hooks — before any AC code runs
    SpoofIdfv();
    HideFromDyldImageList();
    HookDNS();              // <- DNS block installed immediately
    HookEnvVars();          // <- scrub DYLD env vars immediately
    PatchCRCCheck();
    SpoofBundleID();
    PatchFileExistsCheck();
    SpoofReceiptURL();
    SpoofLSApplicationProxy();
    BypassLoginToken();
    TimingEvasion();        // HookAntibanAPI inside, delayed 700ms
}

// Individual exports — unchanged API
void BypassAntiBan()          { HookAntibanAPI(); HookDNS(); }
void BypassAntiCheat()        { PatchCRCCheck(); }
void BypassLogin()            { BypassLoginToken(); }
void BypassLobby()            { BypassLoginToken(); }
void BypassReport()           { HookAntibanAPI(); HookDNS(); }
void BypassBlacklist()        { SpoofIdfv(); SpoofBundleID(); }
void BypassThirdPartyInstall(){ SpoofBundleID(); PatchFileExistsCheck();
                                SpoofReceiptURL(); SpoofLSApplicationProxy();
                                HookEnvVars(); HookDNS(); }
void PatchIntegrityCheck()    { PatchCRCCheck(); }
void SpoofDeviceFingerprint() { SpoofIdfv(); }
void HideLibraryFromTaskList(){ HideFromDyldImageList(); }
void PatchJailbreakDetection(){ PatchFileExistsCheck(); }
