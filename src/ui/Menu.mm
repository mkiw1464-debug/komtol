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
static UIWindow *logoWindow  = nil;   // <- logo button lives here, always on top
static UIView   *menuView    = nil;
static bool      menuVisible = false;
UIView          *drawView    = nil;

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

// ─── Safe key window ──────────────────────────────────────────────────────────
static UIWindow *GetKeyWindow() {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
            }
            if (ws.windows.count > 0) return ws.windows.firstObject;
        }
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.windows.count > 0) return ws.windows.firstObject;
        }
    }
    return nil;
}

static NSArray<UIWindow*> *GetAllWindows() {
    NSMutableArray<UIWindow*> *all = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            [all addObjectsFromArray:((UIWindowScene*)scene).windows];
        }
    }
    return all;
}

// Helper: get active UIWindowScene
static UIWindowScene *GetActiveWindowScene() {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] &&
                s.activationState == UISceneActivationStateForegroundActive)
                return (UIWindowScene *)s;
        }
    }
    return nil;
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
- (void)logoDragged:(UIPanGestureRecognizer*)pan;
- (void)logoTapped;
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

// ─── Logo button drag ─────────────────────────────────────────────────────────
- (void)logoDragged:(UIPanGestureRecognizer *)pan {
    UIView *btn = pan.view;
    UIView *parent = logoWindow.rootViewController.view;
    CGPoint trans = [pan translationInView:parent];
    CGPoint c = btn.center;
    CGFloat r = btn.bounds.size.width * 0.5f;
    CGSize  s = parent.bounds.size;
    CGFloat nx = c.x + trans.x;
    CGFloat ny = c.y + trans.y;
    // clamp inside screen
    nx = MAX(r, MIN(s.width - r, nx));
    ny = MAX(r, MIN(s.height - r, ny));
    btn.center = CGPointMake(nx, ny);
    [pan setTranslation:CGPointZero inView:parent];
}

// ─── Logo button tap ──────────────────────────────────────────────────────────
- (void)logoTapped { ToggleMenu(); }
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
    ctrl.frame = CGRectMake(mw - cs.width - 12,
                             *y + (ROW_H - cs.height) * 0.5f,
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

    UILabel *bl = [[UILabel alloc] initWithFrame:CGRectMake(14,y,mw-28,18)];
    bl.text = @"Target Bone";
    bl.textColor = [UIColor colorWithWhite:1 alpha:.6f];
    bl.font = [UIFont systemFontOfSize:11.f];
    [v addSubview:bl]; y += 20.f;

    UISegmentedControl *bone = [[UISegmentedControl alloc]
        initWithItems:@[@"Head",@"Neck",@"Body",@"Leg"]];
    bone.frame = CGRectMake(10, y, mw-20, 30);
    int boneMap[] = {0,1,6,19};
    for (int i = 0; i < 4; i++)
        if (boneMap[i] == g_Aimbot.targetBone) { bone.selectedSegmentIndex = i; break; }
    bone.selectedSegmentTintColor = TINT;
    bone.backgroundColor = [UIColor colorWithWhite:.2f alpha:.4f];
    [bone setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor}
                        forState:UIControlStateNormal];
    [bone addTarget:[FFMenuHandler shared] action:@selector(onBoneChange:)
   forControlEvents:UIControlEventValueChanged];
    [v addSubview:bone]; y += 40.f;

    UILabel *fl = [[UILabel alloc] initWithFrame:CGRectMake(14,y,mw-28,18)];
    fl.text = [NSString stringWithFormat:@"AimFov  %.0f", g_Aimbot.fov];
    fl.textColor = UIColor.whiteColor;
    fl.font = [UIFont systemFontOfSize:13.f];
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
    ver.font = [UIFont systemFontOfSize:10.f];
    [v addSubview:ver];
    return v;
}

static void RefreshPageContent(int page) {
    UIScrollView *sc = (UIScrollView *)[menuView viewWithTag:kScrollTag];
    if (!sc) return;
    for (UIView *sub in sc.subviews.copy) [sub removeFromSuperview];
    CGFloat mw = menuView.bounds.size.width;
    CGFloat ch = sc.bounds.size.height;
    UIView *pg = (page == 0) ? BuildAimbotPage(mw, ch)
               : (page == 1) ? BuildESPPage(mw, ch)
                              : BuildSettingsPage(mw, ch);
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

    UIWindowScene *ws = GetActiveWindowScene();
    if (ws) {
        if (@available(iOS 13.0, *))
            menuWindow = [[UIWindow alloc] initWithWindowScene:ws];
    }
    if (!menuWindow)
        menuWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    menuWindow.windowLevel = UIWindowLevelAlert + 100.f;
    menuWindow.backgroundColor = UIColor.clearColor;
    menuWindow.rootViewController = [UIViewController new];
    menuWindow.rootViewController.view.backgroundColor = UIColor.clearColor;
    menuWindow.hidden = YES;

    menuView = [[UIView alloc] initWithFrame:CGRectMake(mx, my, mw, mh)];
    menuView.layer.cornerRadius = 18.f;
    menuView.clipsToBounds = YES;
    menuView.layer.borderColor = [UIColor colorWithWhite:1.f alpha:.1f].CGColor;
    menuView.layer.borderWidth  = 1.f;

    UIBlurEffect *blur = [UIBlurEffect
        effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *bv = [[UIVisualEffectView alloc] initWithEffect:blur];
    bv.frame = CGRectMake(0, 0, mw, mh);
    [menuView addSubview:bv];

    UIView *tint = [[UIView alloc] initWithFrame:CGRectMake(0, 0, mw, mh)];
    tint.backgroundColor = [UIColor colorWithWhite:.15f alpha:.4f];
    [menuView addSubview:tint];

    // Title bar
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, mw, 44.f)];
    bar.backgroundColor = [UIColor colorWithWhite:.1f alpha:.55f];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 11, mw-52, 22)];
    title.text = @"FFNET iOS  ·  V1.0.0 Beta";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:13.f];
    [bar addSubview:title];

    // ✕ Close button
    UIButton *xBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    xBtn.frame = CGRectMake(mw-38, 8, 30, 30);
    [xBtn setTitle:@"✕" forState:UIControlStateNormal];
    [xBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    xBtn.titleLabel.font = [UIFont systemFontOfSize:16.f];
    [xBtn addTarget:[FFMenuHandler shared] action:@selector(closeMenu)
   forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:xBtn];
    [menuView addSubview:bar];

    // Drag menu by title bar
    UIPanGestureRecognizer *panMenu = [[UIPanGestureRecognizer alloc]
        initWithTarget:[FFMenuHandler shared] action:@selector(logoDragged:)];
    // reuse logoDragged for menu panel drag too — it uses pan.view so works fine
    // Actually need a separate handler — inline block approach:
    // simpler: add a dedicated pan on bar that moves menuView
    __block CGPoint panStart;
    __block CGPoint menuStartCenter;
    UIPanGestureRecognizer *titlePan = [[UIPanGestureRecognizer alloc]
        initWithTarget:[NSBlockOperation blockOperationWithBlock:^{}]
                action:nil];
    // We'll do it the clean way via a category below — skip for now,
    // menu is draggable via logo drag. Title bar drag via separate UIView pan:
    [bar addGestureRecognizer:({
        UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc]
            initWithTarget:[FFMenuHandler shared]
                    action:@selector(menuPanGesture:)];
        p;
    })];

    // Tab bar
    UISegmentedControl *tabs = [[UISegmentedControl alloc]
        initWithItems:@[@"Aimbot", @"ESP", @"Settings"]];
    tabs.frame = CGRectMake(10, 50, mw-20, 30);
    tabs.selectedSegmentIndex = 0;
    tabs.backgroundColor = [UIColor colorWithWhite:.2f alpha:.4f];
    tabs.selectedSegmentTintColor = TINT;
    [tabs setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor}
                        forState:UIControlStateNormal];
    [tabs addTarget:[FFMenuHandler shared] action:@selector(switchPage:)
   forControlEvents:UIControlEventValueChanged];
    [menuView addSubview:tabs];

    CGFloat scrollY = 88.f;
    UIScrollView *sc = [[UIScrollView alloc]
        initWithFrame:CGRectMake(0, scrollY, mw, mh - scrollY)];
    sc.tag = kScrollTag;
    sc.showsVerticalScrollIndicator = YES;
    sc.bounces = YES;
    [menuView addSubview:sc];

    [menuWindow.rootViewController.view addSubview:menuView];
    RefreshPageContent(0);
}

// ─── Logo button window ───────────────────────────────────────────────────────
// Constant size + position; draggable anywhere on screen
#define LOGO_BTN_SIZE 52.f

static void BuildLogoButton() {
    UIWindowScene *ws = GetActiveWindowScene();

    if (ws) {
        if (@available(iOS 13.0, *))
            logoWindow = [[UIWindow alloc] initWithWindowScene:ws];
    }
    if (!logoWindow)
        logoWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    logoWindow.windowLevel  = UIWindowLevelAlert + 200.f;  // above menuWindow
    logoWindow.backgroundColor = UIColor.clearColor;
    logoWindow.userInteractionEnabled = YES;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    logoWindow.rootViewController = vc;
    logoWindow.hidden = NO;
    [logoWindow makeKeyAndVisible];

    CGSize sc = UIScreen.mainScreen.bounds.size;
    CGFloat bx = sc.width  - LOGO_BTN_SIZE - 14.f;
    CGFloat by = sc.height * 0.28f;

    UIButton *logoBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    logoBtn.frame = CGRectMake(bx, by, LOGO_BTN_SIZE, LOGO_BTN_SIZE);
    logoBtn.layer.cornerRadius  = LOGO_BTN_SIZE * 0.5f;
    logoBtn.clipsToBounds       = YES;
    logoBtn.backgroundColor     = [UIColor colorWithWhite:0.08f alpha:0.88f];
    logoBtn.layer.borderColor   = [UIColor colorWithRed:.45f green:.45f blue:1.f alpha:.9f].CGColor;
    logoBtn.layer.borderWidth   = 2.f;
    logoBtn.layer.shadowColor   = [UIColor colorWithRed:.3f green:.3f blue:1.f alpha:.5f].CGColor;
    logoBtn.layer.shadowOpacity = 0.8f;
    logoBtn.layer.shadowOffset  = CGSizeMake(0, 2);
    logoBtn.layer.shadowRadius  = 8.f;

    // ⚡ label — swap with UIImageView if you have an asset
    UILabel *icon = [[UILabel alloc] initWithFrame:logoBtn.bounds];
    icon.text            = @"⚡";
    icon.textAlignment   = NSTextAlignmentCenter;
    icon.font            = [UIFont systemFontOfSize:22.f];
    icon.userInteractionEnabled = NO;
    [logoBtn addSubview:icon];

    [logoBtn addTarget:[FFMenuHandler shared]
                action:@selector(logoTapped)
      forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:[FFMenuHandler shared]
                action:@selector(logoDragged:)];
    pan.minimumNumberOfTouches = 1;
    pan.maximumNumberOfTouches = 1;
    [logoBtn addGestureRecognizer:pan];

    [vc.view addSubview:logoBtn];
}

// ─── Menu panel drag (via title bar) ─────────────────────────────────────────
@implementation FFMenuHandler (MenuDrag)
- (void)menuPanGesture:(UIPanGestureRecognizer *)pan {
    CGPoint trans = [pan translationInView:menuWindow.rootViewController.view];
    menuView.center = CGPointMake(menuView.center.x + trans.x,
                                  menuView.center.y + trans.y);
    [pan setTranslation:CGPointZero inView:menuWindow.rootViewController.view];
}
@end

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

// ─── Toggle menu ──────────────────────────────────────────────────────────────
void ToggleMenu() {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ ToggleMenu(); });
        return;
    }
    menuVisible = !menuVisible;
    if (menuVisible) {
        menuWindow.hidden = NO;
        [menuWindow makeKeyAndVisible];
        menuView.alpha     = 0.f;
        menuView.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
        [UIView animateWithDuration:0.22
                              delay:0
             usingSpringWithDamping:0.75
              initialSpringVelocity:0.4f
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            menuView.alpha     = 1.f;
            menuView.transform = CGAffineTransformIdentity;
        } completion:nil];
        ApplyStreamproof();
    } else {
        [UIView animateWithDuration:0.18
                         animations:^{
            menuView.alpha     = 0.f;
            menuView.transform = CGAffineTransformMakeScale(0.9f, 0.9f);
        } completion:^(BOOL done) {
            menuWindow.hidden  = YES;
            menuView.alpha     = 1.f;
            menuView.transform = CGAffineTransformIdentity;
        }];
    }
    // Always return key window to logo window (keeps logo interactive)
    [logoWindow makeKeyAndVisible];
}

// HandleTap kept as fallback (volume button etc.) — kept for compatibility
void HandleTap() {}

// ─── Init ─────────────────────────────────────────────────────────────────────
void InitMenu() {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ InitMenu(); });
        return;
    }

    BuildMenu();
    BuildLogoButton();

    UIWindow *kw = GetKeyWindow();
    if (!kw) {
        NSLog(@"[FFNET] WARNING: no key window — retrying in 1s");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ InitMenu(); });
        return;
    }

    // ESP overlay — sits on game, under logo + menu
    drawView = [[FFDrawView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    drawView.backgroundColor        = UIColor.clearColor;
    drawView.userInteractionEnabled = NO;
    [kw addSubview:drawView];

    NSLog(@"[FFNET] Menu + Logo button + DrawView ready 6767");
}
