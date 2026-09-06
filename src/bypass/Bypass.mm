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
#include "../../fishhook/fishhook.h"
#include "../utils/Memory.h"

// ══════════════════════════════════════════════════════════
// BLOCKLIST — all Garena AC/telemetry/ban domains
// ══════════════════════════════════════════════════════════
static NSSet *s_hosts = nil;
static NSArray *s_paths = nil;

static void InitBlocklists() {
    s_hosts = [NSSet setWithArray:@[
        @"ac.ff.garena.com",        @"ac.garena.com",
        @"anticheat.garena.com",    @"security.garena.com",
        @"detection.garena.com",    @"ban.ff.garena.com",
        @"ban.garena.com",          @"tpsdk.garena.com",
        @"tprt.garena.com",         @"tersafe.garena.com",
        @"tersafe.com",             @"sdk.tersafe.com",
        @"log.ff.garena.com",       @"log.garena.com",
        @"analytics.garena.com",    @"telemetry.garena.com",
        @"stats.garena.com",        @"metrics.garena.com",
        @"event.ff.garena.com",     @"events.garena.com",
        @"report.ff.garena.com",    @"report.garena.com",
        @"feedback.garena.com",     @"integrity.garena.com",
        @"verify.garena.com",       @"check.garena.com",
        @"audit.garena.com",        @"device.garena.com",
        @"fingerprint.garena.com",  @"id.garena.com",
        @"tp2.qq.com",              @"tencent-cloud.com",
        @"datadome.co",             @"monitor.datadome.co",
    ]];
    s_paths = @[
        @"/antiban",  @"/anticheat", @"/report",   @"/integrity",
        @"/cheatdetect", @"/ac/",   @"/security",  @"/detect",
        @"/ban",      @"/heartbeat/ac", @"/tpsdk", @"/tersafe",
        @"/tprt",     @"/telemetry",@"/analytics", @"/fingerprint",
        @"/device",   @"/match/ac", @"/lobby/ac",  @"/room/ac",
        @"/install",  @"/source",   @"/channel",   @"/modifier",
        @"/hack",     @"/cheat",
    ];
}

static BOOL ShouldBlock(NSURL *url) {
    if (!url || !s_hosts) return NO;
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path.lowercaseString;
    if (host) {
        if ([s_hosts containsObject:host]) return YES;
        for (NSString *h in s_hosts)
            if ([host hasSuffix:[@"." stringByAppendingString:h]]) return YES;
    }
    if (path) for (NSString *p in s_paths) if ([path containsString:p]) return YES;
    return NO;
}

// ══════════════════════════════════════════════════════════
// BP1 — 3rd Party Install Detection (GBox/esign/ksign)
// This is WHY you got banned without cheat — Garena detects
// non-AppStore install signature and bans immediately.
// ══════════════════════════════════════════════════════════
static NSString *(*orig_bid)(id,SEL)    = nullptr;
static NSString *(*orig_bpath)(id,SEL)  = nullptr;
static NSString *(*orig_bexe)(id,SEL)   = nullptr;
static NSDictionary *(*orig_info)(id,SEL) = nullptr;
static id (*orig_infoKey)(id,SEL,NSString*) = nullptr;

static NSString *fake_bid(id s,SEL c)   { return @"com.dts.freefireth"; }
static NSString *fake_bpath(id s,SEL c) {
    return @"/var/containers/Bundle/Application/FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF/FreeFire.app";
}
static NSString *fake_bexe(id s,SEL c)  {
    return @"/var/containers/Bundle/Application/FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF/FreeFire.app/FreeFire";
}
static NSDictionary *fake_info(id s,SEL c) {
    NSMutableDictionary *d = [orig_info(s,c) mutableCopy];
    [d removeObjectForKey:@"SignerIdentity"];
    [d removeObjectForKey:@"GBoxInstalled"];
    [d removeObjectForKey:@"FeatherInstalled"];
    [d removeObjectForKey:@"eSignInstalled"];
    [d setObject:@"com.dts.freefireth" forKey:@"CFBundleIdentifier"];
    return d;
}
static id fake_infoKey(id self,SEL cmd,NSString *key) {
    if ([key isEqualToString:@"CFBundleIdentifier"]) return @"com.dts.freefireth";
    if ([key isEqualToString:@"SignerIdentity"])     return nil;
    if ([key isEqualToString:@"CFBundleExecutable"]) return @"FreeFire";
    return orig_infoKey(self,cmd,key);
}

static void BypassInstallDetection() {
    Class bc = [NSBundle class];
    auto sw = [](Class c, SEL s, IMP f, IMP *o) {
        Method m = class_getInstanceMethod(c,s);
        if (m) { *o=(IMP)method_getImplementation(m); method_setImplementation(m,f); }
    };
    sw(bc,@selector(bundleIdentifier),(IMP)fake_bid,(IMP*)&orig_bid);
    sw(bc,@selector(bundlePath),(IMP)fake_bpath,(IMP*)&orig_bpath);
    sw(bc,@selector(executablePath),(IMP)fake_bexe,(IMP*)&orig_bexe);
    sw(bc,@selector(infoDictionary),(IMP)fake_info,(IMP*)&orig_info);
    sw(bc,@selector(objectForInfoDictionaryKey:),(IMP)fake_infoKey,(IMP*)&orig_infoKey);
}

// ══════════════════════════════════════════════════════════
// BP2 — Device ID spoof (IDFV + IDFA)
// ══════════════════════════════════════════════════════════
static NSUUID *s_idfv = nil, *s_idfa = nil;
static NSString *GetOrMake(NSString *k) {
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
    NSString *s=[ud objectForKey:k];
    if(!s){s=[[NSUUID UUID]UUIDString];[ud setObject:s forKey:k];[ud synchronize];}
    return s;
}
static NSUUID *(*orig_idfv)(id,SEL)=nullptr;
static NSUUID *fake_idfv(id s,SEL c){
    if(!s_idfv) s_idfv=[[NSUUID alloc]initWithUUIDString:GetOrMake(@"ffnet_idfv_v4")];
    return s_idfv;
}
static id (*orig_idfa)(id,SEL)=nullptr;
static id fake_idfa(id s,SEL c){
    if(!s_idfa) s_idfa=[[NSUUID alloc]initWithUUIDString:GetOrMake(@"ffnet_idfa_v4")];
    return s_idfa;
}
static void SpoofDeviceIDs(){
    Method m1=class_getInstanceMethod([UIDevice class],@selector(identifierForVendor));
    if(m1){orig_idfv=(NSUUID*(*)(id,SEL))method_getImplementation(m1);method_setImplementation(m1,(IMP)fake_idfv);}
    Class ac=NSClassFromString(@"ASIdentifierManager");
    if(ac){Method m2=class_getInstanceMethod(ac,NSSelectorFromString(@"advertisingIdentifier"));
        if(m2){orig_idfa=(id(*)(id,SEL))method_getImplementation(m2);method_setImplementation(m2,(IMP)fake_idfa);}}
}

// ══════════════════════════════════════════════════════════
// BP3 — Hide dylib + block AC module loading
// ══════════════════════════════════════════════════════════
static const char *(*orig_imgname)(uint32_t)=nullptr;
static const char *fake_imgname(uint32_t i){
    const char *n=orig_imgname(i);
    if(n&&(strstr(n,"FFNET")||strstr(n,"ffnet")||strstr(n,"cheat")||strstr(n,"inject")))
        return "/usr/lib/libobjc.A.dylib";
    return n;
}
static void *(*orig_dlopen)(const char*,int)=nullptr;
static void *fake_dlopen(const char *p,int m){
    if(p&&(strstr(p,"libtersafe")||strstr(p,"libtprt")||strstr(p,"libpframe")||strstr(p,"libgua")))
        return nullptr;
    return orig_dlopen(p,m);
}
static void HideFromImageList(){
    struct rebinding r[]={
        {"_dyld_get_image_name",(void*)fake_imgname,(void**)&orig_imgname},
        {"dlopen",(void*)fake_dlopen,(void**)&orig_dlopen},
    };
    rebind_symbols(r,2);
}

// ══════════════════════════════════════════════════════════
// BP4 — Full network block (NSURLSession)
// ══════════════════════════════════════════════════════════
static id (*orig_dt)(id,SEL,NSURLRequest*,id)=nullptr;
static id fake_dt(id self,SEL cmd,NSURLRequest *req,id cb){
    if(ShouldBlock(req.URL)){
        if(cb){
            void(^block)(NSData*,NSURLResponse*,NSError*)=cb;
            dispatch_async(dispatch_get_main_queue(),^{
                NSHTTPURLResponse *r=[[NSHTTPURLResponse alloc]
                    initWithURL:req.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
                block([NSData data],r,nil);
            });
        }
        return nil;
    }
    return orig_dt(self,cmd,req,cb);
}
static id (*orig_ut)(id,SEL,NSURLRequest*,NSData*,id)=nullptr;
static id fake_ut(id self,SEL cmd,NSURLRequest *req,NSData *data,id cb){
    if(ShouldBlock(req.URL)) return nil;
    // Wipe AC payload on match entry
    NSString *path=req.URL.path.lowercaseString;
    if(path&&([path containsString:@"/match"]||[path containsString:@"/lobby"]||
              [path containsString:@"/room"]||[path containsString:@"/ac"])){
        data=[@"{\"status\":0,\"result\":0}" dataUsingEncoding:NSUTF8StringEncoding];
    }
    return orig_ut(self,cmd,req,data,cb);
}
static void HookNetwork(){
    Class sc=NSClassFromString(@"NSURLSession");
    Method m1=class_getInstanceMethod(sc,@selector(dataTaskWithRequest:completionHandler:));
    if(m1){orig_dt=(id(*)(id,SEL,NSURLRequest*,id))method_getImplementation(m1);method_setImplementation(m1,(IMP)fake_dt);}
    Method m2=class_getInstanceMethod(sc,@selector(uploadTaskWithRequest:fromData:completionHandler:));
    if(m2){orig_ut=(id(*)(id,SEL,NSURLRequest*,NSData*,id))method_getImplementation(m2);method_setImplementation(m2,(IMP)fake_ut);}
}

// ══════════════════════════════════════════════════════════
// BP5 — Filesystem (JB + sideload paths)
// ══════════════════════════════════════════════════════════
static NSArray *BadPaths(){
    static NSArray *p=nil;
    if(!p) p=@[@"/Applications/Cydia",@"/usr/sbin/sshd",@"/bin/bash",
               @"/private/var/lib/apt",@"/var/jb",@"/.bootstrapped",
               @"/etc/apt",@"/usr/lib/libhooker",@"/usr/lib/substitute",
               @"AppSync",@"SBInjectFix",@".gbox",@"/Library/GBox",
               @"gbox",@"GBox",@"esign",@"ksign",@"feather",
               @"FFNET",@"ffnet",@"cheat",@"hack",@"inject"];
    return p;
}
static BOOL IsBad(NSString *path){
    if(!path)return NO;
    for(NSString *p in BadPaths()) if([path containsString:p])return YES;
    return NO;
}
static BOOL (*orig_fe)(id,SEL,NSString*)=nullptr;
static BOOL fake_fe(id s,SEL c,NSString *p){return IsBad(p)?NO:orig_fe(s,c,p);}
static int (*orig_stat)(const char*,struct stat*)=nullptr;
static int fake_stat(const char *p,struct stat *b){
    if(p) for(NSString *bp in BadPaths()) if(strstr(p,bp.UTF8String)){errno=ENOENT;return -1;}
    return orig_stat(p,b);
}
static int (*orig_access)(const char*,int)=nullptr;
static int fake_access(const char *p,int m){
    if(p) for(NSString *bp in BadPaths()) if(strstr(p,bp.UTF8String)){errno=ENOENT;return -1;}
    return orig_access(p,m);
}
static void PatchFilesystem(){
    Method m=class_getInstanceMethod([NSFileManager class],@selector(fileExistsAtPath:));
    if(m){orig_fe=(BOOL(*)(id,SEL,NSString*))method_getImplementation(m);method_setImplementation(m,(IMP)fake_fe);}
    struct rebinding r[]={
        {"stat",(void*)fake_stat,(void**)&orig_stat},
        {"access",(void*)fake_access,(void**)&orig_access},
    };
    rebind_symbols(r,2);
}

// ══════════════════════════════════════════════════════════
// BP6 — Sysctl
// ══════════════════════════════════════════════════════════
static int (*orig_sc)(int*,u_int,void*,size_t*,void*,size_t)=nullptr;
static int fake_sc(int *n,u_int nl,void *op,size_t *ol,void *np,size_t nlen){
    int r=orig_sc(n,nl,op,ol,np,nlen);
    if(nl>=4&&n[0]==CTL_KERN&&n[1]==KERN_PROC&&n[2]==KERN_PROC_PID&&op)
        ((struct kinfo_proc*)op)->kp_proc.p_flag&=~P_TRACED;
    return r;
}
static int (*orig_scbn)(const char*,void*,size_t*,void*,size_t)=nullptr;
static int fake_scbn(const char *n,void *op,size_t *ol,void *np,size_t nlen){
    if(n&&(strstr(n,"security.mac")||strstr(n,"kern.codesign")))return -1;
    return orig_scbn(n,op,ol,np,nlen);
}
static void HookSysctl(){
    struct rebinding r[]={
        {"sysctl",(void*)fake_sc,(void**)&orig_sc},
        {"sysctlbyname",(void*)fake_scbn,(void**)&orig_scbn},
    };
    rebind_symbols(r,2);
}

// ══════════════════════════════════════════════════════════
// BP7 — Wipe local ban flags
// ══════════════════════════════════════════════════════════
static void WipeBanFlags(){
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
    for(NSString *k in @[@"gg_ban_flag",@"garena_ban",@"ac_ban_status",
                         @"ff_ban_local",@"cheat_detect_flag",@"ac_result",
                         @"tersafe_result",@"tprt_flag",@"gbox_detected",
                         @"sideload_detected",@"install_source",@"modifier_flag"])
        [ud removeObjectForKey:k];
    [ud synchronize];
}

// ══════════════════════════════════════════════════════════
// BP8 — CRC patch
// ══════════════════════════════════════════════════════════
static void PatchCRC(){
    const uint8_t pat[]={0x85,0xC0,0x0F,0x84};
    uintptr_t base=GetImageBase(); if(!base)return;
    for(uintptr_t i=base;i<base+0x6000000;i+=4){
        uint8_t buf[4]={};vm_size_t sz=0;
        if(vm_read_overwrite(mach_task_self(),i,4,(vm_address_t)buf,&sz)!=KERN_SUCCESS){i+=0xFFC;continue;}
        if(!memcmp(buf,pat,4)){
            if(vm_protect(mach_task_self(),i+2,2,FALSE,VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE)==KERN_SUCCESS){
                uint8_t p[]={0x0F,0x85};memcpy((void*)(i+2),p,2);}
            break;
        }
    }
}

// ══════════════════════════════════════════════════════════
// PUBLIC
// ══════════════════════════════════════════════════════════
void InitAllBypasses(){
    InitBlocklists();
    WipeBanFlags();
    SpoofDeviceIDs();
    BypassInstallDetection();
    HideFromImageList();
    PatchFilesystem();
    HookSysctl();
    PatchCRC();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,650*NSEC_PER_MSEC),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0),^{
        HookNetwork();
    });
}
void BypassAntiBan()          { HookNetwork(); }
void BypassAntiCheat()        { PatchCRC(); HookNetwork(); }
void BypassThirdPartyInstall(){ BypassInstallDetection(); PatchFilesystem(); }
void SpoofDeviceFingerprint() { SpoofDeviceIDs(); }
void HideLibraryFromTaskList(){ HideFromImageList(); }
void PatchJailbreakDetection(){ PatchFilesystem(); }
