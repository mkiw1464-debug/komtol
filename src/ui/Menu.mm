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

static UIWindow    *menuWindow   = nil;
static UIView      *menuView     = nil;
static UIButton    *floatBtn     = nil;   // floating logo button
static UIWindow    *overlayWindow = nil;   // window for button + drawView
static bool         menuVisible  = false;
UIView             *drawView     = nil;

// ─── Config ───────────────────────────────────────────────────────────────────
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

// ─── Safe window helpers ──────────────────────────────────────────────────────
static UIWindowScene *GetActiveScene() {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        if (s.activationState == UISceneActivationStateForegroundActive)
            return (UIWindowScene *)s;
    }
    return nil;
}

// ─── ESP Draw View ────────────────────────────────────────────────────────────
@interface FFDrawView : UIView @end
@implementation FFDrawView
- (void)drawRect:(CGRect)r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    ESPRender(ctx);
    if (g_Aimbot.showFov) {
        float sw = (float)self.bounds.size.width;
        float sh = (float)self.bounds.size.height;
        float rad = g_Aimbot.fov;
        CGContextSetRGBStrokeColor(ctx,1,1,1,0.5f);
        CGContextSetLineWidth(ctx,1.2f);
        CGContextAddEllipseInRect(ctx,
            CGRectMake(sw*.5f-rad, sh*.5f-rad, rad*2, rad*2));
        CGContextStrokePath(ctx);
    }
}
@end

// ─── Draggable float button ───────────────────────────────────────────────────
@interface FFFloatButton : UIButton
@property CGPoint lastTouch;
@property BOOL dragging;
@end
@implementation FFFloatButton
- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)e {
    self.lastTouch = [touches.anyObject locationInView:self.superview];
    self.dragging = NO;
    [super touchesBegan:touches withEvent:e];
}
- (void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)e {
    CGPoint p = [touches.anyObject locationInView:self.superview];
    CGFloat dx = p.x - self.lastTouch.x;
    CGFloat dy = p.y - self.lastTouch.y;
    if (!self.dragging && (fabs(dx)+fabs(dy)) > 5) self.dragging = YES;
    if (self.dragging) {
        self.center = CGPointMake(self.center.x+dx, self.center.y+dy);
        self.lastTouch = p;
    }
}
- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)e {
    if (!self.dragging) [super touchesEnded:touches withEvent:e];
    // Snap to nearest edge
    CGSize ss = self.superview.bounds.size;
    CGFloat bw = self.bounds.size.width * 0.5f;
    CGFloat cx = self.center.x < ss.width*0.5f ? bw+8 : ss.width-bw-8;
    [UIView animateWithDuration:0.2 animations:^{
        self.center = CGPointMake(cx, self.center.y);
    }];
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
- (void)openMenu;
@end

static void RefreshPageContent(int page);

@implementation FFMenuHandler
+ (instancetype)shared {
    static FFMenuHandler *h; static dispatch_once_t t;
    dispatch_once(&t, ^{ h = [FFMenuHandler new]; }); return h;
}
- (void)toggleAimbot:(UISwitch*)s    { g_Aimbot.enabled    = s.on; SaveConfig(); }
- (void)toggleSilent:(UISwitch*)s    { g_Aimbot.silent     = s.on; SaveConfig(); }
- (void)toggleFovVisual:(UISwitch*)s { g_Aimbot.showFov    = s.on; SaveConfig(); }
- (void)onBoneChange:(UISegmentedControl*)s {
    int m[]={0,1,6,19}; int i=(int)s.selectedSegmentIndex;
    g_Aimbot.targetBone=(i>=0&&i<4)?m[i]:0; SaveConfig();
}
- (void)onFovSlide:(UISlider*)s { g_Aimbot.fov=s.value; }
- (void)toggleESP:(UISwitch*)s      { g_ESP.enabled =s.on; SaveConfig(); }
- (void)toggleESPName:(UISwitch*)s  { g_ESP.showName=s.on; SaveConfig(); }
- (void)toggleESPBox:(UISwitch*)s   { g_ESP.showBox =s.on; SaveConfig(); }
- (void)toggleESPLine:(UISwitch*)s  { g_ESP.showLine=s.on; SaveConfig(); }
- (void)toggleESPHP:(UISwitch*)s    { g_ESP.showHP  =s.on; SaveConfig(); }
- (void)toggleStreamproof:(UISwitch*)s { g_Streamproof=s.on; SaveConfig(); }
- (void)toggleSaveConfig:(UISwitch*)s  { g_SaveConfig=s.on; if(g_SaveConfig)SaveConfig(); }
- (void)switchPage:(UISegmentedControl*)s {
    currentPage=(int)s.selectedSegmentIndex; RefreshPageContent(currentPage);
}
- (void)closeMenu  { ToggleMenu(); }
- (void)openMenu   { ToggleMenu(); }
@end

// ─── Page builders ────────────────────────────────────────────────────────────
#define kScrollTag 9900
#define ROW_H 46.f
#define TINT [UIColor colorWithRed:.45f green:.45f blue:1.f alpha:1.f]

static UISwitch *MakeSW(BOOL on, SEL sel) {
    UISwitch *sw=[UISwitch new]; sw.on=on; sw.onTintColor=TINT;
    [sw addTarget:[FFMenuHandler shared] action:sel
 forControlEvents:UIControlEventValueChanged]; return sw;
}
static void AddRow(UIView *v, NSString *lbl, UIControl *ctrl, float *y, float mw) {
    UILabel *l=[[UILabel alloc] initWithFrame:CGRectMake(14,*y+8,mw-80,22)];
    l.text=lbl; l.textColor=UIColor.whiteColor; l.font=[UIFont systemFontOfSize:13];
    [v addSubview:l];
    CGSize cs=ctrl.frame.size;
    ctrl.frame=CGRectMake(mw-cs.width-12,*y+(ROW_H-cs.height)*.5f,cs.width,cs.height);
    [v addSubview:ctrl]; *y+=ROW_H;
}

static UIView *BuildAimbotPage(CGFloat mw, CGFloat ch) {
    UIView *v=[[UIView alloc] initWithFrame:CGRectMake(0,0,mw,ch)]; float y=8;
    AddRow(v,@"Aimbot",MakeSW((BOOL)g_Aimbot.enabled,@selector(toggleAimbot:)),&y,mw);
    UILabel *bl=[[UILabel alloc] initWithFrame:CGRectMake(14,y,mw-28,18)];
    bl.text=@"Target Bone"; bl.textColor=[UIColor colorWithWhite:1 alpha:.6];
    bl.font=[UIFont systemFontOfSize:11]; [v addSubview:bl]; y+=20;
    UISegmentedControl *bone=[[UISegmentedControl alloc] initWithItems:@[@"Head",@"Neck",@"Body",@"Leg"]];
    bone.frame=CGRectMake(10,y,mw-20,30);
    int bm[]={0,1,6,19}; for(int i=0;i<4;i++) if(bm[i]==g_Aimbot.targetBone){bone.selectedSegmentIndex=i;break;}
    bone.selectedSegmentTintColor=TINT; bone.backgroundColor=[UIColor colorWithWhite:.2 alpha:.4];
    [bone setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor} forState:UIControlStateNormal];
    [bone addTarget:[FFMenuHandler shared] action:@selector(onBoneChange:) forControlEvents:UIControlEventValueChanged];
    [v addSubview:bone]; y+=40;
    UILabel *fl=[[UILabel alloc] initWithFrame:CGRectMake(14,y,mw-28,18)];
    fl.text=[NSString stringWithFormat:@"AimFov  %.0f",g_Aimbot.fov];
    fl.textColor=UIColor.whiteColor; fl.font=[UIFont systemFontOfSize:13]; [v addSubview:fl]; y+=22;
    UISlider *sl=[[UISlider alloc] initWithFrame:CGRectMake(12,y,mw-24,28)];
    sl.minimumValue=0; sl.maximumValue=200; sl.value=g_Aimbot.fov; sl.minimumTrackTintColor=TINT;
    [sl addTarget:[FFMenuHandler shared] action:@selector(onFovSlide:) forControlEvents:UIControlEventValueChanged];
    [v addSubview:sl]; y+=38;
    AddRow(v,@"Show FOV Circle",MakeSW((BOOL)g_Aimbot.showFov,@selector(toggleFovVisual:)),&y,mw);
    AddRow(v,@"Aim Silent",MakeSW((BOOL)g_Aimbot.silent,@selector(toggleSilent:)),&y,mw);
    return v;
}
static UIView *BuildESPPage(CGFloat mw, CGFloat ch) {
    UIView *v=[[UIView alloc] initWithFrame:CGRectMake(0,0,mw,ch)]; float y=8;
    struct{NSString*l;SEL s;BOOL b;}rows[]={
        {@"ESP",@selector(toggleESP:),(BOOL)g_ESP.enabled},
        {@"Esp Name",@selector(toggleESPName:),(BOOL)g_ESP.showName},
        {@"Esp Box",@selector(toggleESPBox:),(BOOL)g_ESP.showBox},
        {@"Esp Line",@selector(toggleESPLine:),(BOOL)g_ESP.showLine},
        {@"Health Bar",@selector(toggleESPHP:),(BOOL)g_ESP.showHP},
    };
    for(auto &r:rows) AddRow(v,r.l,MakeSW(r.b,r.s),&y,mw);
    return v;
}
static UIView *BuildSettingsPage(CGFloat mw, CGFloat ch) {
    UIView *v=[[UIView alloc] initWithFrame:CGRectMake(0,0,mw,ch)]; float y=8;
    AddRow(v,@"Streamproof",MakeSW((BOOL)g_Streamproof,@selector(toggleStreamproof:)),&y,mw);
    AddRow(v,@"Save Config",MakeSW((BOOL)g_SaveConfig,@selector(toggleSaveConfig:)),&y,mw);
    UILabel *ver=[[UILabel alloc] initWithFrame:CGRectMake(14,ch-24,mw-28,18)];
    ver.text=@"FFNET iOS  V1.0.0 Beta";
    ver.textColor=[UIColor colorWithWhite:1 alpha:.3]; ver.font=[UIFont systemFontOfSize:10];
    [v addSubview:ver]; return v;
}
static void RefreshPageContent(int page) {
    UIScrollView *sc=(UIScrollView*)[menuView viewWithTag:kScrollTag]; if(!sc)return;
    for(UIView *s in sc.subviews.copy)[s removeFromSuperview];
    CGFloat mw=menuView.bounds.size.width, ch=sc.bounds.size.height;
    UIView *pg=(page==0)?BuildAimbotPage(mw,ch):(page==1)?BuildESPPage(mw,ch):BuildSettingsPage(mw,ch);
    [sc addSubview:pg]; sc.contentSize=pg.bounds.size;
}

// ─── Streamproof ──────────────────────────────────────────────────────────────
static void ApplyStreamproof() {
    if (!g_Streamproof) return;
    UITextField *sf=[[UITextField alloc] initWithFrame:CGRectZero];
    sf.secureTextEntry=YES; [menuView addSubview:sf];
    [sf becomeFirstResponder]; [sf resignFirstResponder]; [sf removeFromSuperview];
}

// ─── Build menu panel ─────────────────────────────────────────────────────────
static void BuildMenuPanel() {
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat mw=300, mh=400;
    CGFloat mx=(screen.width-mw)*.5f, my=(screen.height-mh)*.5f;

    menuView=[[UIView alloc] initWithFrame:CGRectMake(mx,my,mw,mh)];
    menuView.layer.cornerRadius=18; menuView.clipsToBounds=YES;
    menuView.layer.borderColor=[UIColor colorWithWhite:1 alpha:.1].CGColor;
    menuView.layer.borderWidth=1;

    // Blur
    UIBlurEffect *blur=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *bv=[[UIVisualEffectView alloc] initWithEffect:blur];
    bv.frame=CGRectMake(0,0,mw,mh); [menuView addSubview:bv];

    // Tint
    UIView *tint=[[UIView alloc] initWithFrame:CGRectMake(0,0,mw,mh)];
    tint.backgroundColor=[UIColor colorWithWhite:.15 alpha:.4]; [menuView addSubview:tint];

    // Title bar
    UIView *bar=[[UIView alloc] initWithFrame:CGRectMake(0,0,mw,44)];
    bar.backgroundColor=[UIColor colorWithWhite:.1 alpha:.55];
    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(14,11,mw-52,22)];
    title.text=@"FFNET iOS  ·  V1.0.0"; title.textColor=UIColor.whiteColor;
    title.font=[UIFont boldSystemFontOfSize:13]; [bar addSubview:title];

    // X close button
    UIButton *xBtn=[UIButton buttonWithType:UIButtonTypeSystem];
    xBtn.frame=CGRectMake(mw-38,8,30,30);
    [xBtn setTitle:@"✕" forState:UIControlStateNormal];
    [xBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    xBtn.titleLabel.font=[UIFont systemFontOfSize:16];
    [xBtn addTarget:[FFMenuHandler shared] action:@selector(closeMenu)
   forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:xBtn]; [menuView addSubview:bar];

    // Tabs
    UISegmentedControl *tabs=[[UISegmentedControl alloc] initWithItems:@[@"Aimbot",@"ESP",@"Settings"]];
    tabs.frame=CGRectMake(10,50,mw-20,30); tabs.selectedSegmentIndex=0;
    tabs.backgroundColor=[UIColor colorWithWhite:.2 alpha:.4];
    tabs.selectedSegmentTintColor=TINT;
    [tabs setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor} forState:UIControlStateNormal];
    [tabs addTarget:[FFMenuHandler shared] action:@selector(switchPage:)
   forControlEvents:UIControlEventValueChanged]; [menuView addSubview:tabs];

    // Scroll
    CGFloat sy=88;
    UIScrollView *sc=[[UIScrollView alloc] initWithFrame:CGRectMake(0,sy,mw,mh-sy)];
    sc.tag=kScrollTag; sc.bounces=YES; [menuView addSubview:sc];
    RefreshPageContent(0);

    menuView.hidden=YES;
}

// ─── Build floating logo button ───────────────────────────────────────────────
static void BuildFloatButton(UIView *parent) {
    CGSize ss = UIScreen.mainScreen.bounds.size;
    CGFloat bsz = 48;

    floatBtn = [[FFFloatButton alloc] initWithFrame:
                CGRectMake(ss.width-bsz-12, ss.height*0.35f, bsz, bsz)];
    floatBtn.layer.cornerRadius = bsz*0.5f;
    floatBtn.clipsToBounds = YES;

    // Glassmorphism button background
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *bv = [[UIVisualEffectView alloc] initWithEffect:blur];
    bv.frame = CGRectMake(0,0,bsz,bsz);
    bv.userInteractionEnabled = NO;
    [floatBtn addSubview:bv];

    // Border
    floatBtn.layer.borderColor = [UIColor colorWithWhite:1 alpha:.25].CGColor;
    floatBtn.layer.borderWidth = 1;

    // Logo label — "FF" text logo
    UILabel *logo = [[UILabel alloc] initWithFrame:CGRectMake(0,0,bsz,bsz)];
    logo.text = @"FF";
    logo.textAlignment = NSTextAlignmentCenter;
    logo.textColor = UIColor.whiteColor;
    logo.font = [UIFont boldSystemFontOfSize:16];
    logo.userInteractionEnabled = NO;
    [floatBtn addSubview:logo];

    [floatBtn addTarget:[FFMenuHandler shared] action:@selector(openMenu)
      forControlEvents:UIControlEventTouchUpInside];

    [parent addSubview:floatBtn];
}

// ─── Overlay window (button + ESP, always on top) ─────────────────────────────
static void BuildOverlayWindow() {
    UIWindowScene *ws = GetActiveScene();
    if (ws) overlayWindow = [[UIWindow alloc] initWithWindowScene:ws];
    else    overlayWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    overlayWindow.windowLevel = UIWindowLevelAlert + 50;
    overlayWindow.backgroundColor = UIColor.clearColor;
    overlayWindow.rootViewController = [UIViewController new];
    overlayWindow.hidden = NO;
    [overlayWindow makeKeyAndVisible];

    UIView *root = overlayWindow.rootViewController.view;
    root.userInteractionEnabled = YES;

    // ESP draw view (non-interactive, full screen)
    drawView = [[FFDrawView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    drawView.backgroundColor = UIColor.clearColor;
    drawView.userInteractionEnabled = NO;
    [root addSubview:drawView];

    // Menu panel
    BuildMenuPanel();
    [root addSubview:menuView];

    // Floating button
    BuildFloatButton(root);
}

// ─── Menu window (separate, highest level) ────────────────────────────────────
static void BuildMenuWindow() {
    UIWindowScene *ws = GetActiveScene();
    if (ws) menuWindow = [[UIWindow alloc] initWithWindowScene:ws];
    else    menuWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    menuWindow.windowLevel = UIWindowLevelAlert + 100;
    menuWindow.backgroundColor = UIColor.clearColor;
    menuWindow.rootViewController = [UIViewController new];
    menuWindow.hidden = YES;
}

// ─── Public ───────────────────────────────────────────────────────────────────
void ToggleMenu() {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ ToggleMenu(); }); return;
    }
    menuVisible = !menuVisible;
    menuView.hidden = !menuVisible;

    // Dim float button when menu open
    [UIView animateWithDuration:0.15 animations:^{
        floatBtn.alpha = menuVisible ? 0.3f : 1.0f;
    }];

    if (menuVisible) ApplyStreamproof();
}

void InitMenu() {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ InitMenu(); }); return;
    }
    LoadConfig();
    BuildOverlayWindow();
    BuildMenuWindow();
    NSLog(@"[FFNET] Menu ready — tap FF button to open");
}
