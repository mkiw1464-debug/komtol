#import "ESP.h"
#import "Aimbot.h"   // fix: WorldToScreen declared here
#import "../utils/Memory.h"
#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>

ESPConfig g_ESP;

static ESPEntry entries[100];
static int      entryCount = 0;

void ESPCollect() {
    if (!g_ESP.enabled) { entryCount = 0; return; }

    uintptr_t entityList = Read<uintptr_t>(GetOffset(Offsets::EntityList));
    if (!entityList) { entryCount = 0; return; }
    int count = Read<int>(GetOffset(Offsets::EntityListSize));
    float *cam = reinterpret_cast<float*>(GetOffset(Offsets::CameraMatrix));
    uintptr_t local = Read<uintptr_t>(GetOffset(Offsets::LocalPlayer));
    if (!local) { entryCount = 0; return; }
    int localTeam = Read<int>(local + Offsets::PlayerTeamID);
    entryCount = 0;

    for (int i = 0; i < count && entryCount < 100; i++) {
        uintptr_t ent = Read<uintptr_t>(entityList + (uintptr_t)i * 0x8);
        if (!ent || ent == local) continue;
        if (Read<int>(ent + Offsets::PlayerTeamID) == localTeam) continue;
        float hp = Read<float>(ent + Offsets::PlayerHealth);
        if (hp <= 0.f) continue;

        uintptr_t transform = Read<uintptr_t>(ent + Offsets::PlayerTransform);
        if (!transform) continue;

        Vector3 headPos = Read<Vector3>(transform + Offsets::PlayerBoneHead * 0xC);
        Vector3 footPos = headPos;
        footPos.y -= 1.75f;

        ESPEntry &e     = entries[entryCount];
        e.screenPos     = WorldToScreen(headPos, cam);
        e.screenFoot    = WorldToScreen(footPos, cam);
        e.health        = hp;

        uintptr_t namePtr = Read<uintptr_t>(ent + Offsets::PlayerName);
        if (namePtr) {
            const char *rawName = reinterpret_cast<const char*>(namePtr + 0x10);
            strncpy(e.name, rawName, 63);
            e.name[63] = '\0';
        } else {
            strncpy(e.name, "Player", 63);
        }

        e.valid = (e.screenPos.x > 0.f && e.screenPos.x < 9000.f);
        if (e.valid) entryCount++;
    }
}

void ESPRender(CGContextRef ctx) {
    if (!g_ESP.enabled || entryCount == 0) return;
    CGContextSaveGState(ctx);

    // Enemy counter top-left
    CGContextSetRGBFillColor(ctx, 1.f, 0.2f, 0.2f, 1.f);
    NSString *counter = [NSString stringWithFormat:@"Enemies: %d", entryCount];
    NSDictionary *counterAttr = @{
        NSFontAttributeName:            [UIFont boldSystemFontOfSize:14.f],
        NSForegroundColorAttributeName: [UIColor redColor]
    };
    [counter drawAtPoint:CGPointMake(20.f, 40.f) withAttributes:counterAttr];

    NSDictionary *nameAttr = @{
        NSFontAttributeName:            [UIFont systemFontOfSize:11.f],
        NSForegroundColorAttributeName: [UIColor whiteColor]
    };

    for (int i = 0; i < entryCount; i++) {
        ESPEntry &e = entries[i];
        if (!e.valid) continue;

        float x = e.screenPos.x,  y = e.screenPos.y;
        float fx = e.screenFoot.x, fy = e.screenFoot.y;
        float h = fy - y;
        if (h < 5.f) continue;
        float w = h * 0.4f;

        // Box
        if (g_ESP.showBox) {
            CGContextSetRGBStrokeColor(ctx, 1.f, 0.f, 0.f, 0.9f);
            CGContextSetLineWidth(ctx, 1.5f);
            CGContextStrokeRect(ctx, CGRectMake(x - w * 0.5f, y, w, h));
        }

        // Name
        if (g_ESP.showName) {
            NSString *nm = [NSString stringWithUTF8String:e.name];
            if (nm) [nm drawAtPoint:CGPointMake(x, y - 16.f) withAttributes:nameAttr];
        }

        // HP bar — left side of box
        if (g_ESP.showHP) {
            float pct = (e.health > 200.f ? 200.f : e.health) / 200.f;
            float barX = x - w * 0.5f - 6.f;
            CGContextSetRGBFillColor(ctx, 0.15f, 0.15f, 0.15f, 0.7f);
            CGContextFillRect(ctx, CGRectMake(barX, y, 4.f, h));
            CGContextSetRGBFillColor(ctx, 0.2f, 0.85f, 0.2f, 0.9f);
            CGContextFillRect(ctx, CGRectMake(barX, y + h * (1.f - pct), 4.f, h * pct));
        }

        // Line from bottom-center to enemy foot
        if (g_ESP.showLine) {
            CGSize sz = UIScreen.mainScreen.bounds.size;
            CGContextSetRGBStrokeColor(ctx, 1.f, 1.f, 0.f, 0.65f);
            CGContextSetLineWidth(ctx, 1.f);
            CGContextMoveToPoint(ctx, (float)sz.width * 0.5f, (float)sz.height);
            CGContextAddLineToPoint(ctx, fx, fy);
            CGContextStrokePath(ctx);
        }
    }
    CGContextRestoreGState(ctx);
}
