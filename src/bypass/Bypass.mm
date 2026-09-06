#import "Bypass.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <string.h>
#import <CommonCrypto/CommonDigest.h>
#include "../../fishhook/fishhook.h"
#include "../utils/Memory.h"

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER — shared blocklist init
// ═══════════════════════════════════════════════════════════════════════════════
static NSSet *s_blockedHosts = nil;
static NSSet *s_blockedPaths = nil;

static void InitBlocklists() {
    // ALL known Garena/FF AC, telemetry, ban, report domains
    s_blockedHosts = [NSSet setWithArray:@[
        // Garena AC
        @"ac.ff.garena.com",
        @"ac.garena.com",
        @"anticheat.garena.com",
        @"security.garena.com",
        @"detection.garena.com",
        @"ban.ff.garena.com",
        @"ban.garena.com",
        @"tpsdk.garena.com",
        @"tprt.garena.com",
        @"tersafe.garena.com",
        // Telemetry / analytics
        @"log.ff.garena.com",
        @"log.garena.com",
        @"analytics.garena.com",
        @"telemetry.garena.com",
        @"stats.garena.com",
        @"metrics.garena.com",
        @"event.ff.garena.com",
        @"events.garena.com",
        // Report
        @"report.ff.garena.com",
        @"report.garena.com",
        @"feedback.garena.com",
        // Integrity check
        @"integrity.garena.com",
        @"verify.garena.com",
        @"check.garena.com",
        @"audit.garena.com",
        // Device fingerprint
        @"device.garena.com",
        @"fingerprint.garena.com",
        @"id.garena.com",
        // 3rd party AC SDKs Garena uses
        @"sdk.tersafe.com",
        @"tersafe.com",
        @"tencent-cloud.com",
        @"tp2.qq.com",
        @"tsdk.garena.com",
    ]];
    s_blockedPaths = [NSSet setWithArray:@[
        @"/antiban", @"/anticheat", @"/report", @"/integrity",
        @"/cheatdetect", @"/ac/", @"/security", @"/detect",
        @"/ban", @"/heartbeat/ac", @"/tpsdk", @"/tersafe",
        @"/tprt", @"/telemetry", @"/analytics", @"/fingerprint",
        @"/device", @"/match/ac", @"/lobby/ac", @"/room/ac",
        @"/install", @"/source", @"/channel",
    ]];
}

static BOOL ShouldBlock(NSURL *url) {
    if (!url) return NO;
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path.lowercaseString;
    if (host) {
        if ([s_blockedHosts containsObject:host]) return YES;
        // Also block subdomains
        for (NSString *h in s_blockedHosts)
            if ([host hasSuffix:h]) return YES;
    }
    if (path)
        for (NSString *p in s_blockedPaths)
            if ([path containsString:p]) return YES;
    return NO;
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 1 — 3RD PARTY INSTALL DETECTION (GBox/esign/feather/ksign)
// Garena detects: bundle path, provisioning profile, entitlements,
// MobileInstallation source, and app install date vs first-run delta.
// ═══════════════════════════════════════════════════════════════════════════════

// 1a — Bundle path spoof (GBox puts app in non-standard path)
static NSString *(*orig_bpath)(id,SEL) = nullptr;
static NSString *fake_bpath(id s, SEL c) {
    return @"/var/containers/Bundle/Application/FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF/FreeFire.app";
}

// 1b — Bundle ID always legit
static NSString *(*orig_bid)(id,SEL) = nullptr;
static NSString *fake_bid(id s, SEL c) { return @"com.dts.freefireth"; }

// 1c — Executable path spoof
static NSString *(*orig_expath)(id,SEL) = nullptr;
static NSString *fake_expath(id s, SEL c) {
    return @"/var/containers/Bundle/Application/FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF/FreeFire.app/FreeFire";
}

// 1d — Info.plist spoof — remove GBox/sideload markers
static NSDictionary *(*orig_infod)(id,SEL) = nullptr;
static NSDictionary *fake_infod(id s, SEL c) {
    NSMutableDictionary *d = [orig_infod(s,c) mutableCopy];
    // Remove keys Garena checks for sideload detection
    [d removeObjectForKey:@"SignerIdentity"];
    [d removeObjectForKey:@"DTPlatformName"];
    [d removeObjectForKey:@"GBoxInstalled"];
    [d removeObjectForKey:@"FeatherInstalled"];
    [d setObject:@"com.dts.freefireth" forKey:@"CFBundleIdentifier"];
    return d;
}

// 1e — NSBundle objectForInfoDictionaryKey — per-key intercept
static id (*orig_infoKey)(id,SEL,NSString*) = nullptr;
static id fake_infoKey(id self, SEL cmd, NSString *key) {
    if ([key isEqualToString:@"CFBundleIdentifier"])
        return @"com.dts.freefireth";
    if ([key isEqualToString:@"SignerIdentity"])
        return nil;
    if ([key isEqualToString:@"CFBundleExecutable"])
        return @"FreeFire";
    return orig_infoKey(self, cmd, key);
}

static void BypassInstallDetection() {
    Class bc = [NSBundle class];

    Method m1 = class_getInstanceMethod(bc, @selector(bundleIdentifier));
    if (m1) { orig_bid = (NSString*(*)(id,SEL))method_getImplementation(m1);
               method_setImplementation(m1, (IMP)fake_bid); }

    Method m2 = class_getInstanceMethod(bc, @selector(bundlePath));
    if (m2) { orig_bpath = (NSString*(*)(id,SEL))method_getImplementation(m2);
               method_setImplementation(m2, (IMP)fake_bpath); }

    Method m3 = class_getInstanceMethod(bc, @selector(executablePath));
    if (m3) { orig_expath = (NSString*(*)(id,SEL))method_getImplementation(m3);
               method_setImplementation(m3, (IMP)fake_expath); }

    Method m4 = class_getInstanceMethod(bc, @selector(infoDictionary));
    if (m4) { orig_infod = (NSDictionary*(*)(id,SEL))method_getImplementation(m4);
               method_setImplementation(m4, (IMP)fake_infod); }

    Method m5 = class_getInstanceMethod(bc, @selector(objectForInfoDictionaryKey:));
    if (m5) { orig_infoKey = (id(*)(id,SEL,NSString*))method_getImplementation(m5);
               method_setImplementation(m5, (IMP)fake_infoKey); }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 2 — Device ID spoof (IDFV + IDFA)
// Garena cross-references both to detect ban evasion
// ═══════════════════════════════════════════════════════════════════════════════
static NSUUID *s_fakeIDFV = nil;
static NSUUID *s_fakeIDFA = nil;

static NSString *GetOrMakeUUID(NSString *key) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *s = [ud objectForKey:key];
    if (!s) { s = [[NSUUID UUID] UUIDString]; [ud setObject:s forKey:key]; [ud synchronize]; }
    return s;
}

static NSUUID *(*orig_idfv)(id,SEL) = nullptr;
static NSUUID *fake_idfv(id self, SEL c) {
    if (!s_fakeIDFV) s_fakeIDFV = [[NSUUID alloc] initWithUUIDString:GetOrMakeUUID(@"ffnet_idfv_v3")];
    return s_fakeIDFV;
}

static id (*orig_idfa)(id,SEL) = nullptr;
static id fake_idfa(id self, SEL c) {
    if (!s_fakeIDFA) s_fakeIDFA = [[NSUUID alloc] initWithUUIDString:GetOrMakeUUID(@"ffnet_idfa_v3")];
    return s_fakeIDFA;
}

static void SpoofDeviceIDs() {
    Method m1 = class_getInstanceMethod([UIDevice class], @selector(identifierForVendor));
    if (m1) { orig_idfv = (NSUUID*(*)(id,SEL))method_getImplementation(m1);
               method_setImplementation(m1, (IMP)fake_idfv); }
    Class asClass = NSClassFromString(@"ASIdentifierManager");
    if (asClass) {
        Method m2 = class_getInstanceMethod(asClass, NSSelectorFromString(@"advertisingIdentifier"));
        if (m2) { orig_idfa = (id(*)(id,SEL))method_getImplementation(m2);
                   method_setImplementation(m2, (IMP)fake_idfa); }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 3 — Hide dylib from image list
// ═══════════════════════════════════════════════════════════════════════════════
static const char *(*orig_img_name)(uint32_t) = nullptr;
static const char *fake_img_name(uint32_t idx) {
    const char *n = orig_img_name(idx);
    if (n && (strstr(n,"FFNET")||strstr(n,"ffnet")||
              strstr(n,"cheat")||strstr(n,"hack")||strstr(n,"inject")))
        return "/usr/lib/libobjc.A.dylib";
    return n;
}

static void *(*orig_dlopen)(const char*,int) = nullptr;
static void *fake_dlopen(const char *path, int mode) {
    if (path && (strstr(path,"libtersafe")||strstr(path,"libtprt")||
                 strstr(path,"libpframe")||strstr(path,"libgua")))
        return nullptr; // block Garena AC module loading
    return orig_dlopen(path, mode);
}

static void HideFromImageList() {
    struct rebinding r[] = {
        {"_dyld_get_image_name",(void*)fake_img_name,(void**)&orig_img_name},
        {"dlopen",(void*)fake_dlopen,(void**)&orig_dlopen},
    };
    rebind_symbols(r, 2);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 4 — Full network block (NSURLSession + CFNetwork)
// ═══════════════════════════════════════════════════════════════════════════════
static id (*orig_dataTask)(id,SEL,NSURLRequest*,id) = nullptr;
static id fake_dataTask(id self, SEL cmd, NSURLRequest *req, id cb) {
    if (ShouldBlock(req.URL)) {
        if (cb) {
            void(^block)(NSData*,NSURLResponse*,NSError*) = cb;
            dispatch_async(dispatch_get_main_queue(), ^{
                NSHTTPURLResponse *fakeR = [[NSHTTPURLResponse alloc]
                    initWithURL:req.URL statusCode:200
                    HTTPVersion:@"HTTP/1.1" headerFields:@{}];
                block([NSData data], fakeR, nil);
            });
        }
        return nil;
    }
    return orig_dataTask(self,cmd,req,cb);
}

static id (*orig_uploadTask)(id,SEL,NSURLRequest*,NSData*,id) = nullptr;
static id fake_uploadTask(id self, SEL cmd, NSURLRequest *req, NSData *data, id cb) {
    if (ShouldBlock(req.URL)) return nil;
    // Wipe AC payload for match/lobby requests
    NSString *path = req.URL.path.lowercaseString;
    if (path && ([path containsString:@"/match"]||[path containsString:@"/lobby"]||
                 [path containsString:@"/room"]||[path containsString:@"/ac"])) {
        NSData *clean = [@"{\"status\":0,\"result\":0}" dataUsingEncoding:NSUTF8StringEncoding];
        return orig_uploadTask(self,cmd,req,clean,cb);
    }
    return orig_uploadTask(self,cmd,req,data,cb);
}

static void HookNetworkAPIs() {
    Class sc = NSClassFromString(@"NSURLSession");

    Method m1 = class_getInstanceMethod(sc, @selector(dataTaskWithRequest:completionHandler:));
    if (m1) { orig_dataTask = (id(*)(id,SEL,NSURLRequest*,id))method_getImplementation(m1);
               method_setImplementation(m1,(IMP)fake_dataTask); }

    Method m2 = class_getInstanceMethod(sc, @selector(uploadTaskWithRequest:fromData:completionHandler:));
    if (m2) { orig_uploadTask = (id(*)(id,SEL,NSURLRequest*,NSData*,id))method_getImplementation(m2);
               method_setImplementation(m2,(IMP)fake_uploadTask); }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 5 — Filesystem (JB + sideload + 3rd party paths)
// ═══════════════════════════════════════════════════════════════════════════════
static NSArray *BadPaths() {
    static NSArray *p = nil;
    if (!p) p = @[
        @"/Applications/Cydia",@"/usr/sbin/sshd",@"/bin/bash",
        @"/private/var/lib/apt",@"/var/jb",@"/.bootstrapped",
        @"/etc/apt",@"/usr/lib/libhooker",@"/usr/lib/substitute",
        @"/usr/lib/TweakInject",@"AppSync",@"SBInjectFix",
        // GBox/esign detection paths
        @"/var/mobile/Containers/Data/Application/.gbox",
        @"/var/mobile/Library/GBox",
        @"gbox",@"GBox",@"esign",@"eSign",@"ksign",@"feather",
        @"sideload",@"Sideload",
        // Our dylib
        @"FFNET",@"ffnet",@"cheat",@"hack",@"inject",
    ];
    return p;
}

static BOOL IsBadPath(NSString *path) {
    if (!path) return NO;
    for (NSString *p in BadPaths())
        if ([path containsString:p]) return YES;
    return NO;
}

static BOOL (*orig_fe)(id,SEL,NSString*) = nullptr;
static BOOL fake_fe(id s, SEL c, NSString *path) {
    if (IsBadPath(path)) return NO;
    return orig_fe(s,c,path);
}

static int (*orig_stat)(const char*,struct stat*) = nullptr;
static int fake_stat(const char *path, struct stat *buf) {
    if (path) {
        for (NSString *p in BadPaths())
            if (strstr(path, p.UTF8String)) { errno=ENOENT; return -1; }
    }
    return orig_stat(path,buf);
}

// access() — some AC uses this instead of stat
static int (*orig_access)(const char*,int) = nullptr;
static int fake_access(const char *path, int mode) {
    if (path) {
        for (NSString *p in BadPaths())
            if (strstr(path, p.UTF8String)) { errno=ENOENT; return -1; }
    }
    return orig_access(path,mode);
}

static void PatchFilesystem() {
    Method m1 = class_getInstanceMethod([NSFileManager class], @selector(fileExistsAtPath:));
    if (m1) { orig_fe=(BOOL(*)(id,SEL,NSString*))method_getImplementation(m1);
               method_setImplementation(m1,(IMP)fake_fe); }
    struct rebinding r[] = {
        {"stat",   (void*)fake_stat,   (void**)&orig_stat},
        {"access", (void*)fake_access, (void**)&orig_access},
    };
    rebind_symbols(r, 2);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 6 — sysctl / process info
// ═══════════════════════════════════════════════════════════════════════════════
static int (*orig_sysctl)(int*,u_int,void*,size_t*,void*,size_t) = nullptr;
static int fake_sysctl(int *name, u_int nlen, void *oldp,
                        size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctl(name,nlen,oldp,oldlenp,newp,newlen);
    if (nlen>=4 && name[0]==CTL_KERN && name[1]==KERN_PROC
               && name[2]==KERN_PROC_PID && oldp)
        ((struct kinfo_proc*)oldp)->kp_proc.p_flag &= ~P_TRACED;
    return ret;
}

static int (*orig_sysctlbn)(const char*,void*,size_t*,void*,size_t) = nullptr;
static int fake_sysctlbn(const char *name,void *oldp,size_t *oldlenp,
                          void *newp,size_t newlen) {
    if (name && (strstr(name,"security.mac")||strstr(name,"kern.codesign")||
                 strstr(name,"com.apple.private"))) return -1;
    return orig_sysctlbn(name,oldp,oldlenp,newp,newlen);
}

static void HookSysctl() {
    struct rebinding r[] = {
        {"sysctl",       (void*)fake_sysctl,   (void**)&orig_sysctl},
        {"sysctlbyname", (void*)fake_sysctlbn, (void**)&orig_sysctlbn},
    };
    rebind_symbols(r, 2);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 7 — Wipe local ban flags + session token cache
// ═══════════════════════════════════════════════════════════════════════════════
static void WipeBanFlags() {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *k in @[@"gg_ban_flag",@"garena_ban",@"ac_ban_status",
                          @"ff_ban_local",@"cheat_detect_flag",@"ac_result",
                          @"tersafe_result",@"tprt_flag",@"gbox_detected",
                          @"sideload_detected",@"install_source"])
        [ud removeObjectForKey:k];
    [ud synchronize];
}

static void CacheSessionToken() {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *t = [d objectForKey:@"ffnet_session_v3"];
    if (t) [d setObject:t forKey:@"garena_auth_token"];
}

// ═══════════════════════════════════════════════════════════════════════════════
// BYPASS 8 — CRC patch
// ═══════════════════════════════════════════════════════════════════════════════
static void PatchCRCCheck() {
    const uint8_t pat[] = {0x85,0xC0,0x0F,0x84};
    uintptr_t base = GetImageBase();
    if (!base) return;
    for (uintptr_t i = base; i < base+0x6000000; i+=4) {
        uint8_t buf[4]={};vm_size_t sz=0;
        if (vm_read_overwrite(mach_task_self(),i,4,(vm_address_t)buf,&sz)!=KERN_SUCCESS){
            i+=0xFFC;continue;}
        if (!memcmp(buf,pat,4)) {
            if (vm_protect(mach_task_self(),i+2,2,FALSE,
                VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE)==KERN_SUCCESS) {
                uint8_t p[]={0x0F,0x85};memcpy((void*)(i+2),p,2);}
            break;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PUBLIC API
// ═══════════════════════════════════════════════════════════════════════════════
void InitAllBypasses() {
    InitBlocklists();
    WipeBanFlags();
    SpoofDeviceIDs();
    BypassInstallDetection();  // ← GBox/esign/3rd party fix
    HideFromImageList();
    PatchFilesystem();
    HookSysctl();
    CacheSessionToken();
    PatchCRCCheck();
    // Network hooks — delayed 650ms (timing evasion)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 650*NSEC_PER_MSEC),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0), ^{
        HookNetworkAPIs();
    });
}
void BypassAntiBan()          { HookNetworkAPIs(); }
void BypassAntiCheat()        { PatchCRCCheck(); HookNetworkAPIs(); }
void BypassLogin()            { CacheSessionToken(); }
void BypassLobby()            { CacheSessionToken(); HookNetworkAPIs(); }
void BypassReport()           { HookNetworkAPIs(); }
void BypassBlacklist()        { SpoofDeviceIDs(); BypassInstallDetection(); WipeBanFlags(); }
void BypassThirdPartyInstall(){ BypassInstallDetection(); PatchFilesystem(); }
void PatchIntegrityCheck()    { PatchCRCCheck(); }
void SpoofDeviceFingerprint() { SpoofDeviceIDs(); }
void HideLibraryFromTaskList(){ HideFromImageList(); }
void PatchJailbreakDetection(){ PatchFilesystem(); }
void BypassMatchmaking()      { HookNetworkAPIs(); }
