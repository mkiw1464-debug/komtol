#import "Menu.h"
#import "../features/Aimbot.h"
#import "../features/ESP.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>

// ─── Globals ──────────────────────────────────────────────────────────────────
static bool g_Streamproof = false;
static bool g_SaveConfig  = false;
static int  currentPage   = 0;

static UIWindow *menuWindow  = nil;
static UIView   *menuView    = nil;
static bool      menuVisible = false;
UIView          *drawView    = nil;

static int            tapCount = 0;
static NSTimeInterval lastTap  = 0;

// ─── Config persistence ───────────────────────────────────────────────────────
static void SaveConfig() {
    if (!g_SaveConfig) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:g_Aimbot.enabled       forKey:@"cfg_aimbot_on"];
    [ud setBool:g_Aimbot.silent        forKey:@"cfg_silent_on"];
    [ud setBool:g_Aimbot.showFov       forKey:@"cfg_fov_vis"];
    [ud setFloat:g_Aimbot.fov          forKey:@"cfg_fov_val"];
    [ud setInteger:g_Aimbot.targetBone forKey:@"cfg_bone"];
    [ud setBool:g_ESP.enabled          forKey:@"cfg_esp_on"];
    [ud setBool:g_ESP.showName         forKey:@"cfg_esp_name"];
    [ud setBool:g_ESP.showBox          forKey:@"cfg_esp_box"];
    [ud setBool:g_ESP.showLine         forKey:@"cfg_esp_line"];
    [ud setBool:g_ESP.showHP           forKey:@"cfg_esp_hp"];
    [ud setBool:g_Streamproof          forKey:@"cfg_streamproof"];
    [ud synchronize];
}

static void LoadConfig() {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (![ud objectForKey:@"cfg_aimbot_on"]) return;
    g_Aimbot.enabled    = [ud boolForKey:@"cfg_aimbot_on"];
    g_Aimbot.silent     = [ud boolForKey:@"cfg_silent_on"];
    g_Aimbot.showFov    = [ud boolForKey:@"cfg_fov_vis"];
    g_Aimbot.fov        = [ud floatForKey:@"cfg_fov_val"];
    g_Aimbot.targetBone = (int)[ud integerForKey:@"cfg_bone"];
    g_ESP.enabled       = [ud boolForKey:@"cfg_esp_on"];
    g_ESP.showName      = [ud boolForKey:@"cfg_esp_name"];
    g_ESP.showBox       = [ud boolForKey:@"cfg_esp_box"];
    g_ESP.showLine      = [ud boolForKey:@"cfg_esp_line"];
    g_ESP.showHP        = [ud boolForKey:@"cfg_esp_hp"];
    g_Streamproof       = [ud boolForKey:@"cfg_streamproof"];
}

// ─── Safe key window getter (iOS 13+) ─────────────────────────────────────────
static UIWindow *GetKeyWindow() {
    UIWindow *kw = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene*)scene).windows) {
                    if (w.isKeyWindow) { kw = w; break; }
                }
            }
            if (kw) break;
        }
    }
    // Fallback
    if (!kw)
        kw = UIApplication.sharedApplication.windows.firstObject;
    return kw;
}

// ─── Draw view — ESP + FOV circle ─────────────────────────────────────────────
@interface FFDrawView : UIView @end
@implementation FFDrawView
- (void)drawRect:(CGRect)r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    ESPRender(ctx);
    if (g_Aimbot.showFov) {
        float sw  = (float)self.bounds.size.width;
        float sh  = (float)self.bounds.size.height;
        float rad = g_Aimbot.fov;
        CGContextSetRGBStrokeColor(ctx, 1.f, 1.f, 1.f, 0.5f);
        CGContextSetLineWidth(ctx, 1.2f);
        CGContextAddEllipseInRect(ctx,
            CGRectMake(sw*0.5f - rad, sh*0.5f - rad, rad*2.f, rad*2.f));
        CGContextStrokePath(ctx);
    }
}
@end

// ─── Action handler ───────────────────────────────────────────────────────────
@interface FFMenuHandler : NSObject
+ (instancetype)shared;
- (void)toggleAimbot:(UISwitch*)s;
- (void)toggleSilent:(UISwitch*)s;
- (void)toggleFovVisual:(UISwitch*)s;
- (void)onBoneChange:(UISegmentedControl*)s;
- (void)onFovSlide:(UISlider*)s;
- (void)toggleESP:(UISwitch*)s;
- (void)toggleESPName:(UISwitch*)s;
- (void)toggleESPBox:(UISwitch*)s;
- (void)toggleESPLine:(UISwitch*)s;
- (void)toggleESPHP:(UISwitch*)s;
- (void)toggleStreamproof:(UISwitch*)s;
- (void)toggleSaveConfig:(UISwitch*)s;
- (void)switchPage:(UISegmentedControl*)s;
- (void)closeMenu;
- (void)handleTap:(UITapGestureRecognizer*)gr;
@end

static void RefreshPageContent(int page);

@implementation FFMenuHandler
+ (instancetype)shared {
    static FFMenuHandler *h;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ h = [FFMenuHandler new]; });
    return h;
}
- (void)toggleAimbot:(UISwitch*)s    { g_Aimbot.enabled    = s.on; SaveConfig(); }
- (void)toggleSilent:(UISwitch*)s    { g_Aimbot.silent     = s.on; SaveConfig(); }
- (void)toggleFovVisual:(UISwitch*)s { g_Aimbot.showFov    = s.on; SaveConfig(); }
- (void)onBoneChange:(UISegmentedControl*)s {
    int map[] = {0, 1, 6, 19};
    int idx = (int)s.selectedSegmentIndex;
    g_Aimbot.targetBone = (idx >= 0 && idx < 4) ? map[idx] : 0;
    SaveConfig();
}
- (void)onFovSlide:(UISlider*)s { g_Aimbot.fov = s.value; }
- (void)toggleESP:(UISwitch*)s      { g_ESP.enabled  = s.on; SaveConfig(); }
- (void)toggleESPName:(UISwitch*)s  { g_ESP.showName = s.on; SaveConfig(); }
- (void)toggleESPBox:(UISwitch*)s   { g_ESP.showBox  = s.on; SaveConfig(); }
- (void)toggleESPLine:(UISwitch*)s  { g_ESP.showLine = s.on; SaveConfig(); }
- (void)toggleESPHP:(UISwitch*)s    { g_ESP.showHP   = s.on; SaveConfig(); }
- (void)toggleStreamproof:(UISwitch*)s { g_Streamproof = s.on; SaveConfig(); }
- (void)toggleSaveConfig:(UISwitch*)s  {
    g_SaveConfig = s.on;
    if (g_SaveConfig) SaveConfig();
}
- (void)switchPage:(UISegmentedControl*)s {
    currentPage = (int)s.selectedSegmentIndex;
    RefreshPageContent(currentPage);
}
- (void)closeMenu { ToggleMenu(); }
- (void)handleTap:(UITapGestureRecognizer*)gr {
    if (gr.state == UIGestureRecognizerStateEnded)
        HandleTap();
}
@end

// ─── Page builders ────────────────────────────────────────────────────────────
#define kScrollTag 9900
#define ROW_H 46.f
#define TINT [UIColor colorWithRed:.45f green:.45f blue:1.f alpha:1.f]

static UISwitch *MakeSwitch(BOOL on, SEL action) {
    UISwitch *sw = [UISwitch new];
    sw.on = on;
    sw.onTintColor = TINT;
    [sw addTarget:[FFMenuHandler shared]
           action:action
 forControlEvents:UIControlEventValueChanged];
    return sw;
}

static void AddRow(UIView *parent, NSString *label,
                   UIControl *ctrl, float *y, float mw) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, *y+8, mw-80, 22)];
    l.text = label; l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:13.f];
    [parent addSubview:l];
    CGSize cs = ctrl.frame.size;
    ctrl.frame = CGRectMake(mw - cs.width - 12, *y + (ROW_H - cs.height)*0.5f,
                             cs.width, cs.height);
    [parent addSubview:ctrl];
    *y += ROW_H;
}

static UIView *BuildAimbotPage(CGFloat mw, CGFloat ch) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,mw,ch)];
    float y = 8.f;

    AddRow(v, @"Aimbot",
           MakeSwitch((BOOL)g_Aimbot.enabled, @selector(toggleAimbot:)),
           &y, mw);

    // Bone label
    UILabel *bl = [[UILabel alloc] initWithFrame:CGRectMake(14,y,mw-28,18)];
    bl.text = @"Target Bone"; bl.textColor = [UIColor colorWithWhite:1 alpha:.6f];
    bl.font = [UIFont systemFontOfSize:11.f]; [v addSubview:bl]; y += 20.f;

    UISegmentedControl *bone = [[UISegmentedControl alloc]
        initWithItems:@[@"Head",@"Neck",@"Body",@"Leg"]];
    bone.frame = CGRectMake(10, y, mw-20, 30);
    int boneMap[] = {0,1,6,19};
    for (int i=0;i<4;i++) if(boneMap[i]==g_Aimbot.targetBone) {
        bone.selectedSegmentIndex = i; break;
    }
    bone.selectedSegmentTintColor = TINT;
    bone.backgroundColor = [UIColor colorWithWhite:.2f alpha:.4f];
    NSDictionary *ta = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    [bone setTitleTextAttributes:ta forState:UIControlStateNormal];
    [bone addTarget:[FFMenuHandler shared] action:@selector(onBoneChange:)
   forControlEvents:UIControlEventValueChanged];
    [v addSubview:bone]; y += 40.f;

    // FOV label + slider
    UILabel *fl = [[UILabel alloc] initWithFrame:CGRectMake(14,y,mw-28,18)];
    fl.text = [NSString stringWithFormat:@"AimFov  %.0f", g_Aimbot.fov];
    fl.textColor = UIColor.whiteColor; fl.font = [UIFont systemFontOfSize:13.f];
    [v addSubview:fl]; y += 22.f;

    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(12,y,mw-24,28)];
    sl.minimumValue = 0; sl.maximumValue = 200; sl.value = g_Aimbot.fov;
    sl.minimumTrackTintColor = TINT;
    [sl addTarget:[FFMenuHandler shared] action:@selector(onFovSlide:)
 forControlEvents:UIControlEventValueChanged];
    [v addSubview:sl]; y += 38.f;

    AddRow(v, @"Show FOV Circle",
           MakeSwitch((BOOL)g_Aimbot.showFov, @selector(toggleFovVisual:)),
           &y, mw);
    AddRow(v, @"Aim Silent",
           MakeSwitch((BOOL)g_Aimbot.silent, @selector(toggleSilent:)),
           &y, mw);
    return v;
}

static UIView *BuildESPPage(CGFloat mw, CGFloat ch) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,mw,ch)];
    float y = 8.f;
    struct { NSString *lbl; SEL sel; BOOL state; } rows[] = {
        {@"ESP",        @selector(toggleESP:),     (BOOL)g_ESP.enabled},
        {@"Esp Name",   @selector(toggleESPName:),  (BOOL)g_ESP.showName},
        {@"Esp Box",    @selector(toggleESPBox:),   (BOOL)g_ESP.showBox},
        {@"Esp Line",   @selector(toggleESPLine:),  (BOOL)g_ESP.showLine},
        {@"Health Bar", @selector(toggleESPHP:),    (BOOL)g_ESP.showHP},
    };
    for (auto &r : rows)
        AddRow(v, r.lbl, MakeSwitch(r.state, r.sel), &y, mw);
    return v;
}

static UIView *BuildSettingsPage(CGFloat mw, CGFloat ch) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,mw,ch)];
    float y = 8.f;
    AddRow(v, @"Streamproof",
           MakeSwitch((BOOL)g_Streamproof, @selector(toggleStreamproof:)), &y, mw);
    AddRow(v, @"Save Config",
           MakeSwitch((BOOL)g_SaveConfig,  @selector(toggleSaveConfig:)),  &y, mw);

    UILabel *ver = [[UILabel alloc] initWithFrame:CGRectMake(14,ch-24,mw-28,18)];
    ver.text = @"FFNET iOS  V1.0.0 Beta";
    ver.textColor = [UIColor colorWithWhite:1.f alpha:.35f];
    ver.font = [UIFont systemFontOfSize:10.f]; [v addSubview:ver];
    return v;
}

static void RefreshPageContent(int page) {
    UIScrollView *sc = (UIScrollView*)[menuView viewWithTag:kScrollTag];
    if (!sc) return;
    for (UIView *sub in sc.subviews.copy) [sub removeFromSuperview];
    CGFloat mw = menuView.bounds.size.width;
    CGFloat ch = sc.bounds.size.height;
    UIView *pg = (page == 0) ? BuildAimbotPage(mw,ch)
               : (page == 1) ? BuildESPPage(mw,ch)
                              : BuildSettingsPage(mw,ch);
    [sc addSubview:pg];
    sc.contentSize = pg.bounds.size;
}

// ─── Build menu window ────────────────────────────────────────────────────────
static void BuildMenu() {
    LoadConfig();

    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat mw = 300.f, mh = 400.f;
    CGFloat mx = (screen.width  - mw) * 0.5f;
    CGFloat my = (screen.height - mh) * 0.5f;

    // Use a fresh UIWindow — NOT keyWindow
    if (@available(iOS 13.0, *)) {
        UIWindowScene *ws = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
            if ([s isKindOfClass:[UIWindowScene class]]) { ws = (UIWindowScene*)s; break; }
        if (ws) menuWindow = [[UIWindow alloc] initWithWindowScene:ws];
    }
    if (!menuWindow)
        menuWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    menuWindow.windowLevel = UIWindowLevelAlert + 100.f;
    menuWindow.backgroundColor = UIColor.clearColor;
    menuWindow.hidden = YES;
    // Need a root VC or window won't display on iOS 13+
    menuWindow.rootViewController = [UIViewController new];

    menuView = [[UIView alloc] initWithFrame:CGRectMake(mx, my, mw, mh)];
    menuView.layer.cornerRadius = 18.f;
    menuView.clipsToBounds = YES;
    menuView.layer.borderColor = [UIColor colorWithWhite:1.f alpha:.1f].CGColor;
    menuView.layer.borderWidth  = 1.f;

    // Blur (glassmorphism)
    UIBlurEffect *blur = [UIBlurEffect
        effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *bv = [[UIVisualEffectView alloc] initWithEffect:blur];
    bv.frame = CGRectMake(0,0,mw,mh); [menuView addSubview:bv];

    // Grey tint
    UIView *tint = [[UIView alloc] initWithFrame:CGRectMake(0,0,mw,mh)];
    tint.backgroundColor = [UIColor colorWithWhite:.15f alpha:.4f];
    [menuView addSubview:tint];

    // Title bar
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0,0,mw,44.f)];
    bar.backgroundColor = [UIColor colorWithWhite:.1f alpha:.55f];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14,11,mw-52,22)];
    title.text = @"FFNET iOS  ·  V1.0.0 Beta";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:13.f];
    [bar addSubview:title];

    UIButton *xBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    xBtn.frame = CGRectMake(mw-38, 8, 30, 30);
    [xBtn setTitle:@"✕" forState:UIControlStateNormal];
    [xBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    xBtn.titleLabel.font = [UIFont systemFontOfSize:16.f];
    [xBtn addTarget:[FFMenuHandler shared] action:@selector(closeMenu)
   forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:xBtn];
    [menuView addSubview:bar];

    // Tab bar
    UISegmentedControl *tabs = [[UISegmentedControl alloc]
        initWithItems:@[@"Aimbot",@"ESP",@"Settings"]];
    tabs.frame = CGRectMake(10, 50, mw-20, 30);
    tabs.selectedSegmentIndex = 0;
    tabs.backgroundColor = [UIColor colorWithWhite:.2f alpha:.4f];
    tabs.selectedSegmentTintColor = TINT;
    NSDictionary *ta = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    [tabs setTitleTextAttributes:ta forState:UIControlStateNormal];
    [tabs addTarget:[FFMenuHandler shared] action:@selector(switchPage:)
   forControlEvents:UIControlEventValueChanged];
    [menuView addSubview:tabs];

    // Scroll content area
    CGFloat scrollY = 88.f;
    UIScrollView *sc = [[UIScrollView alloc]
        initWithFrame:CGRectMake(0, scrollY, mw, mh-scrollY)];
    sc.tag = kScrollTag;
    sc.showsVerticalScrollIndicator = YES;
    sc.bounces = YES;
    [menuView addSubview:sc];

    [menuWindow.rootViewController.view addSubview:menuView];
    RefreshPageContent(0);
}

// ─── Streamproof ──────────────────────────────────────────────────────────────
static void ApplyStreamproof() {
    if (!g_Streamproof) return;
    UITextField *sf = [[UITextField alloc] initWithFrame:CGRectZero];
    sf.secureTextEntry = YES;
    [menuView addSubview:sf];
    [sf becomeFirstResponder];
    [sf resignFirstResponder];
    [sf removeFromSuperview];
}

void ToggleMenu() {
    NSAssert([NSThread isMainThread], @"ToggleMenu must be called on main thread");
    menuVisible = !menuVisible;
    if (menuVisible) {
        menuWindow.hidden = NO;
        [menuWindow makeKeyAndVisible];
        ApplyStreamproof();
    } else {
        menuWindow.hidden = YES;
        // Return key status to FF's window
        UIWindow *ffWin = nil;
        for (UIWindow *w in UIApplication.sharedApplication.windows)
            if (w != menuWindow) { ffWin = w; break; }
        [ffWin makeKeyWindow];
    }
}

void HandleTap() {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastTap > 1.5) tapCount = 0;
    lastTap = now;
    if (++tapCount >= 3) {
        tapCount = 0;
        dispatch_async(dispatch_get_main_queue(), ^{ ToggleMenu(); });
    }
}

void InitMenu() {
    NSAssert([NSThread isMainThread], @"InitMenu must be called on main thread");

    BuildMenu();

    UIWindow *kw = GetKeyWindow();
    if (!kw) {
        NSLog(@"[FFNET] WARNING: no key window found");
        return;
    }

    // Tap gesture — 3 fingers OR 3 taps (3 taps easier on phone)
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:[FFMenuHandler shared]
                action:@selector(handleTap:)];
    tap.numberOfTapsRequired    = 3;
    tap.numberOfTouchesRequired = 1;
    tap.cancelsTouchesInView    = NO;  // don't block FF's own touches
    [kw addGestureRecognizer:tap];

    // ESP overlay on top of FF's window
    drawView = [[FFDrawView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    drawView.backgroundColor       = UIColor.clearColor;
    drawView.userInteractionEnabled = NO;
    [kw addSubview:drawView];

    NSLog(@"[FFNET] Menu + DrawView initialized");
}
