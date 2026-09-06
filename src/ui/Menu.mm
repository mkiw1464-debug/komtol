#import "Menu.h"
#import "../features/Aimbot.h"
#import "../features/ESP.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>

static bool g_SP=false,g_SC=false;
static int  g_Page=0;
static UIWindow *g_Win=nil;
static UIView   *g_Panel=nil,*g_FloatBtn=nil;
static bool      g_Visible=false;
UIView          *drawView=nil;

// ─── Config ───────────────────────────────────────────────
static void Save(){
    if(!g_SC)return;
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
    [ud setBool:g_Aimbot.enabled forKey:@"a_on"]; [ud setBool:g_Aimbot.silent forKey:@"a_si"];
    [ud setBool:g_Aimbot.showFov forKey:@"a_fv"]; [ud setFloat:g_Aimbot.fov forKey:@"a_fr"];
    [ud setInteger:g_Aimbot.targetBone forKey:@"a_bn"];
    [ud setBool:g_ESP.enabled forKey:@"e_on"]; [ud setBool:g_ESP.showName forKey:@"e_nm"];
    [ud setBool:g_ESP.showBox forKey:@"e_bx"]; [ud setBool:g_ESP.showLine forKey:@"e_ln"];
    [ud setBool:g_ESP.showHP forKey:@"e_hp"]; [ud setBool:g_SP forKey:@"s_sp"];
    [ud synchronize];
}
static void Load(){
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
    if(![ud objectForKey:@"a_on"])return;
    g_Aimbot.enabled=(bool)[ud boolForKey:@"a_on"]; g_Aimbot.silent=(bool)[ud boolForKey:@"a_si"];
    g_Aimbot.showFov=(bool)[ud boolForKey:@"a_fv"]; g_Aimbot.fov=[ud floatForKey:@"a_fr"];
    g_Aimbot.targetBone=(int)[ud integerForKey:@"a_bn"];
    g_ESP.enabled=(bool)[ud boolForKey:@"e_on"]; g_ESP.showName=(bool)[ud boolForKey:@"e_nm"];
    g_ESP.showBox=(bool)[ud boolForKey:@"e_bx"]; g_ESP.showLine=(bool)[ud boolForKey:@"e_ln"];
    g_ESP.showHP=(bool)[ud boolForKey:@"e_hp"]; g_SP=(bool)[ud boolForKey:@"s_sp"];
}

// ─── Draw view ────────────────────────────────────────────
@interface FFDraw:UIView @end
@implementation FFDraw
-(void)drawRect:(CGRect)r{
    CGContextRef c=UIGraphicsGetCurrentContext();if(!c)return;
    ESPRender(c);
    if(g_Aimbot.showFov){
        float w=(float)self.bounds.size.width,h=(float)self.bounds.size.height,rad=g_Aimbot.fov;
        CGContextSetRGBStrokeColor(c,1,1,1,.5f);CGContextSetLineWidth(c,1.2f);
        CGContextAddEllipseInRect(c,CGRectMake(w*.5f-rad,h*.5f-rad,rad*2,rad*2));
        CGContextStrokePath(c);
    }
}
@end

// ─── Draggable button ─────────────────────────────────────
@interface FFBtn:UIButton
@property CGPoint lp;@property BOOL drag;
@end
@implementation FFBtn
-(void)touchesBegan:(NSSet*)t withEvent:(UIEvent*)e{
    self.lp=[t.anyObject locationInView:self.superview];self.drag=NO;
    [super touchesBegan:t withEvent:e];
}
-(void)touchesMoved:(NSSet*)t withEvent:(UIEvent*)e{
    CGPoint p=[t.anyObject locationInView:self.superview];
    float dx=p.x-self.lp.x,dy=p.y-self.lp.y;
    if(!self.drag&&(fabsf(dx)+fabsf(dy))>6)self.drag=YES;
    if(self.drag){self.center=CGPointMake(self.center.x+dx,self.center.y+dy);self.lp=p;}
}
-(void)touchesEnded:(NSSet*)t withEvent:(UIEvent*)e{
    if(!self.drag)[super touchesEnded:t withEvent:e];
    CGFloat bw=self.bounds.size.width*.5f,sw=self.superview.bounds.size.width;
    CGFloat cx=self.center.x<sw*.5f?bw+8:sw-bw-8;
    [UIView animateWithDuration:.18 animations:^{self.center=CGPointMake(cx,self.center.y);}];
}
@end

// ─── Handler ──────────────────────────────────────────────
@interface FFH:NSObject
+(instancetype)sh;
-(void)tap;-(void)close;
-(void)swAimbot:(UISwitch*)s;-(void)swSilent:(UISwitch*)s;
-(void)swFov:(UISwitch*)s;-(void)slFov:(UISlider*)s;
-(void)segBone:(UISegmentedControl*)s;-(void)segPage:(UISegmentedControl*)s;
-(void)swESP:(UISwitch*)s;-(void)swName:(UISwitch*)s;
-(void)swBox:(UISwitch*)s;-(void)swLine:(UISwitch*)s;-(void)swHP:(UISwitch*)s;
-(void)swSP:(UISwitch*)s;-(void)swSC:(UISwitch*)s;
@end

static void RefreshPage(int pg);

@implementation FFH
+(instancetype)sh{
    static FFH *h;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ h = [FFH new]; });
    return h;
}
-(void)tap{ToggleMenu();}-(void)close{ToggleMenu();}
-(void)swAimbot:(UISwitch*)s{g_Aimbot.enabled=s.on;Save();}
-(void)swSilent:(UISwitch*)s{g_Aimbot.silent=s.on;Save();}
-(void)swFov:(UISwitch*)s{g_Aimbot.showFov=s.on;Save();}
-(void)slFov:(UISlider*)s{g_Aimbot.fov=s.value;}
-(void)segBone:(UISegmentedControl*)s{
    int m[]={0,1,6,19};int i=(int)s.selectedSegmentIndex;
    g_Aimbot.targetBone=(i>=0&&i<4)?m[i]:0;Save();
}
-(void)segPage:(UISegmentedControl*)s{g_Page=(int)s.selectedSegmentIndex;RefreshPage(g_Page);}
-(void)swESP:(UISwitch*)s{g_ESP.enabled=s.on;Save();}
-(void)swName:(UISwitch*)s{g_ESP.showName=s.on;Save();}
-(void)swBox:(UISwitch*)s{g_ESP.showBox=s.on;Save();}
-(void)swLine:(UISwitch*)s{g_ESP.showLine=s.on;Save();}
-(void)swHP:(UISwitch*)s{g_ESP.showHP=s.on;Save();}
-(void)swSP:(UISwitch*)s{g_SP=s.on;Save();}
-(void)swSC:(UISwitch*)s{g_SC=s.on;if(g_SC)Save();}
@end

// ─── Pages ────────────────────────────────────────────────
#define T [UIColor colorWithRed:.5f green:.5f blue:1 alpha:1]
#define W UIColor.whiteColor
#define RH 46.f

static UISwitch *SW(BOOL on,SEL sel){
    UISwitch *s=[UISwitch new];s.on=on;s.onTintColor=T;
    [s addTarget:[FFH sh] action:sel forControlEvents:UIControlEventValueChanged];return s;
}
static void Row(UIView *v,NSString *lbl,UIControl *c,float *y,float mw){
    UILabel *l=[[UILabel alloc]initWithFrame:CGRectMake(14,*y+8,mw-80,22)];
    l.text=lbl;l.textColor=W;l.font=[UIFont systemFontOfSize:13];[v addSubview:l];
    CGSize cs=c.frame.size;
    c.frame=CGRectMake(mw-cs.width-12,*y+(RH-cs.height)*.5f,cs.width,cs.height);
    [v addSubview:c];*y+=RH;
}
static UIView *PageAimbot(CGFloat mw,CGFloat ch){
    UIView *v=[[UIView alloc]initWithFrame:CGRectMake(0,0,mw,ch)];float y=8;
    Row(v,@"Aimbot",SW((BOOL)g_Aimbot.enabled,@selector(swAimbot:)),&y,mw);
    UILabel *bl=[[UILabel alloc]initWithFrame:CGRectMake(14,y,mw-28,16)];
    bl.text=@"Target Bone";bl.textColor=[UIColor colorWithWhite:1 alpha:.6];
    bl.font=[UIFont systemFontOfSize:11];[v addSubview:bl];y+=18;
    UISegmentedControl *bn=[[UISegmentedControl alloc]initWithItems:@[@"Head",@"Neck",@"Body",@"Leg"]];
    bn.frame=CGRectMake(10,y,mw-20,30);
    int bm[]={0,1,6,19};for(int i=0;i<4;i++)if(bm[i]==g_Aimbot.targetBone){bn.selectedSegmentIndex=i;break;}
    bn.selectedSegmentTintColor=T;bn.backgroundColor=[UIColor colorWithWhite:.2 alpha:.4];
    [bn setTitleTextAttributes:@{NSForegroundColorAttributeName:W} forState:UIControlStateNormal];
    [bn addTarget:[FFH sh] action:@selector(segBone:) forControlEvents:UIControlEventValueChanged];
    [v addSubview:bn];y+=38;
    UILabel *fl=[[UILabel alloc]initWithFrame:CGRectMake(14,y,mw-28,18)];
    fl.text=[NSString stringWithFormat:@"FOV  %.0f",g_Aimbot.fov];
    fl.textColor=W;fl.font=[UIFont systemFontOfSize:13];[v addSubview:fl];y+=20;
    UISlider *sl=[[UISlider alloc]initWithFrame:CGRectMake(12,y,mw-24,28)];
    sl.minimumValue=0;sl.maximumValue=200;sl.value=g_Aimbot.fov;sl.minimumTrackTintColor=T;
    [sl addTarget:[FFH sh] action:@selector(slFov:) forControlEvents:UIControlEventValueChanged];
    [v addSubview:sl];y+=36;
    Row(v,@"Show FOV",SW((BOOL)g_Aimbot.showFov,@selector(swFov:)),&y,mw);
    Row(v,@"Aim Silent",SW((BOOL)g_Aimbot.silent,@selector(swSilent:)),&y,mw);
    return v;
}
static UIView *PageESP(CGFloat mw,CGFloat ch){
    UIView *v=[[UIView alloc]initWithFrame:CGRectMake(0,0,mw,ch)];float y=8;
    struct{NSString *l;SEL s;BOOL b;}r[]={
        {@"ESP",@selector(swESP:),(BOOL)g_ESP.enabled},
        {@"Name",@selector(swName:),(BOOL)g_ESP.showName},
        {@"Box",@selector(swBox:),(BOOL)g_ESP.showBox},
        {@"Line",@selector(swLine:),(BOOL)g_ESP.showLine},
        {@"Health",@selector(swHP:),(BOOL)g_ESP.showHP},
    };
    for(auto &x:r)Row(v,x.l,SW(x.b,x.s),&y,mw);
    return v;
}
static UIView *PageSettings(CGFloat mw,CGFloat ch){
    UIView *v=[[UIView alloc]initWithFrame:CGRectMake(0,0,mw,ch)];float y=8;
    Row(v,@"Streamproof",SW((BOOL)g_SP,@selector(swSP:)),&y,mw);
    Row(v,@"Save Config",SW((BOOL)g_SC,@selector(swSC:)),&y,mw);
    UILabel *ver=[[UILabel alloc]initWithFrame:CGRectMake(14,ch-22,mw-28,16)];
    ver.text=@"FFNET iOS V1.0.0 Beta";
    ver.textColor=[UIColor colorWithWhite:1 alpha:.3];ver.font=[UIFont systemFontOfSize:10];
    [v addSubview:ver];return v;
}
static void RefreshPage(int pg){
    UIScrollView *sc=(UIScrollView*)[g_Panel viewWithTag:9900];if(!sc)return;
    for(UIView *s in sc.subviews.copy)[s removeFromSuperview];
    CGFloat mw=g_Panel.bounds.size.width,ch=sc.bounds.size.height;
    UIView *p=(pg==0)?PageAimbot(mw,ch):(pg==1)?PageESP(mw,ch):PageSettings(mw,ch);
    [sc addSubview:p];sc.contentSize=p.bounds.size;
}

// ─── Build panel ──────────────────────────────────────────
static void BuildPanel(UIView *root){
    CGSize ss=UIScreen.mainScreen.bounds.size;
    CGFloat mw=296,mh=380,mx=(ss.width-mw)*.5f,my=(ss.height-mh)*.5f;
    g_Panel=[[UIView alloc]initWithFrame:CGRectMake(mx,my,mw,mh)];
    g_Panel.layer.cornerRadius=16;g_Panel.clipsToBounds=YES;
    g_Panel.layer.borderColor=[UIColor colorWithWhite:1 alpha:.12].CGColor;g_Panel.layer.borderWidth=1;
    UIBlurEffect *be=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *bv=[[UIVisualEffectView alloc]initWithEffect:be];
    bv.frame=CGRectMake(0,0,mw,mh);[g_Panel addSubview:bv];
    UIView *ti=[[UIView alloc]initWithFrame:CGRectMake(0,0,mw,mh)];
    ti.backgroundColor=[UIColor colorWithWhite:.15 alpha:.38];[g_Panel addSubview:ti];
    // Title bar
    UIView *bar=[[UIView alloc]initWithFrame:CGRectMake(0,0,mw,42)];
    bar.backgroundColor=[UIColor colorWithWhite:.1 alpha:.55];
    UILabel *tl=[[UILabel alloc]initWithFrame:CGRectMake(12,11,mw-50,20)];
    tl.text=@"FFNET  ·  iOS V1.0.0";tl.textColor=W;tl.font=[UIFont boldSystemFontOfSize:13];[bar addSubview:tl];
    UIButton *xb=[UIButton buttonWithType:UIButtonTypeSystem];
    xb.frame=CGRectMake(mw-36,7,28,28);
    [xb setTitle:@"✕" forState:UIControlStateNormal];
    [xb setTitleColor:W forState:UIControlStateNormal];
    xb.titleLabel.font=[UIFont systemFontOfSize:15];
    [xb addTarget:[FFH sh] action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:xb];[g_Panel addSubview:bar];
    // Tabs
    UISegmentedControl *tabs=[[UISegmentedControl alloc]initWithItems:@[@"Aimbot",@"ESP",@"Settings"]];
    tabs.frame=CGRectMake(8,48,mw-16,28);tabs.selectedSegmentIndex=0;
    tabs.backgroundColor=[UIColor colorWithWhite:.2 alpha:.4];tabs.selectedSegmentTintColor=T;
    [tabs setTitleTextAttributes:@{NSForegroundColorAttributeName:W} forState:UIControlStateNormal];
    [tabs addTarget:[FFH sh] action:@selector(segPage:) forControlEvents:UIControlEventValueChanged];
    [g_Panel addSubview:tabs];
    // Scroll
    UIScrollView *sc=[[UIScrollView alloc]initWithFrame:CGRectMake(0,82,mw,mh-82)];
    sc.tag=9900;sc.bounces=YES;[g_Panel addSubview:sc];
    g_Panel.hidden=YES;[root addSubview:g_Panel];
    RefreshPage(0);
}

// ─── Float button ─────────────────────────────────────────
static void BuildFloatButton(UIView *root){
    CGSize ss=UIScreen.mainScreen.bounds.size;
    CGFloat bsz=52;
    FFBtn *btn=[[FFBtn alloc]initWithFrame:CGRectMake(ss.width-bsz-12,ss.height*.30f,bsz,bsz)];
    btn.layer.cornerRadius=bsz*.5f;btn.clipsToBounds=YES;
    btn.layer.borderColor=[UIColor colorWithWhite:1 alpha:.3].CGColor;btn.layer.borderWidth=1.5f;
    // Blur
    UIBlurEffect *be=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *bv=[[UIVisualEffectView alloc]initWithEffect:be];
    bv.frame=CGRectMake(0,0,bsz,bsz);bv.userInteractionEnabled=NO;[btn addSubview:bv];
    // Purple tint
    UIView *tint=[[UIView alloc]initWithFrame:CGRectMake(0,0,bsz,bsz)];
    tint.backgroundColor=[UIColor colorWithRed:.3 green:.3 blue:.9 alpha:.4];
    tint.userInteractionEnabled=NO;[btn addSubview:tint];
    // Label
    UILabel *lbl=[[UILabel alloc]initWithFrame:CGRectMake(0,0,bsz,bsz)];
    lbl.text=@"FF";lbl.textAlignment=NSTextAlignmentCenter;
    lbl.textColor=W;lbl.font=[UIFont boldSystemFontOfSize:18];lbl.userInteractionEnabled=NO;
    [btn addSubview:lbl];
    [btn addTarget:[FFH sh] action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
    g_FloatBtn=btn;[root addSubview:btn];
}

// ─── Public ───────────────────────────────────────────────
void ToggleMenu(){
    if(![NSThread isMainThread]){dispatch_async(dispatch_get_main_queue(),^{ToggleMenu();});return;}
    g_Visible=!g_Visible;g_Panel.hidden=!g_Visible;
    [UIView animateWithDuration:.15 animations:^{g_FloatBtn.alpha=g_Visible?.35f:1.f;}];
    if(g_Visible&&g_SP){
        UITextField *sf=[[UITextField alloc]initWithFrame:CGRectZero];sf.secureTextEntry=YES;
        [g_Panel addSubview:sf];[sf becomeFirstResponder];[sf resignFirstResponder];[sf removeFromSuperview];
    }
}

void InitMenu(){
    if(![NSThread isMainThread]){dispatch_async(dispatch_get_main_queue(),^{InitMenu();});return;}
    Load();
    // Create overlay window — try scene-based first (iOS 13+)
    if(@available(iOS 13.0,*)){
        for(UIScene *s in UIApplication.sharedApplication.connectedScenes){
            if(![s isKindOfClass:[UIWindowScene class]])continue;
            if(s.activationState==UISceneActivationStateForegroundActive){
                g_Win=[[UIWindow alloc]initWithWindowScene:(UIWindowScene*)s];break;
            }
        }
    }
    if(!g_Win) g_Win=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];
    // High window level — above FF's own windows
    g_Win.windowLevel = UIWindowLevelStatusBar * 2 + 1000;
    g_Win.backgroundColor=UIColor.clearColor;
    g_Win.rootViewController=[UIViewController new];
    g_Win.rootViewController.view.backgroundColor=UIColor.clearColor;
    [g_Win makeKeyAndVisible];
    g_Win.hidden=NO;
    UIView *root=g_Win.rootViewController.view;
    root.userInteractionEnabled=YES;
    // ESP draw
    drawView=[[FFDraw alloc]initWithFrame:UIScreen.mainScreen.bounds];
    drawView.backgroundColor=UIColor.clearColor;drawView.userInteractionEnabled=NO;
    [root addSubview:drawView];
    BuildPanel(root);
    BuildFloatButton(root);
    // Force layout
    [g_Win layoutIfNeeded];
    NSLog(@"[FFNET] menu init done — FF button visible");
}
