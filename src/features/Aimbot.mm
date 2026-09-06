#import "Aimbot.h"
#import "../utils/Memory.h"
#import <UIKit/UIKit.h>
#include <float.h>

AimbotConfig g_Aimbot;

// Fix: explicit (float) casts to avoid CGFloat (double) narrowing error
Vector2 WorldToScreen(Vector3 world, float *m) {
    float tx = m[0]*world.x + m[4]*world.y + m[8]*world.z  + m[12];
    float ty = m[1]*world.x + m[5]*world.y + m[9]*world.z  + m[13];
    float tw = m[3]*world.x + m[7]*world.y + m[11]*world.z + m[15];
    if (tw < 0.01f) return Vector2(-9999.f, -9999.f);
    CGSize sz = UIScreen.mainScreen.bounds.size;
    float w = (float)sz.width;
    float h = (float)sz.height;
    return Vector2(
        (tx / tw + 1.0f) * w * 0.5f,
        (1.0f - ty / tw) * h * 0.5f
    );
}

bool IsInFov(Vector2 screen, float radius) {
    CGSize sz = UIScreen.mainScreen.bounds.size;
    float cx = (float)sz.width  * 0.5f;
    float cy = (float)sz.height * 0.5f;
    float dx = screen.x - cx;
    float dy = screen.y - cy;
    return sqrtf(dx*dx + dy*dy) <= radius;
}

void AimbotTick() {
    if (!g_Aimbot.enabled) return;

    uintptr_t entityList = Read<uintptr_t>(GetOffset(Offsets::EntityList));
    if (!entityList) return;
    int count = Read<int>(GetOffset(Offsets::EntityListSize));
    float *camMatrix = reinterpret_cast<float*>(GetOffset(Offsets::CameraMatrix));
    uintptr_t local = Read<uintptr_t>(GetOffset(Offsets::LocalPlayer));
    if (!local) return;
    int localTeam = Read<int>(local + Offsets::PlayerTeamID);

    uintptr_t bestEnt  = 0;
    float     bestDist = FLT_MAX;

    for (int i = 0; i < count; i++) {
        uintptr_t ent = Read<uintptr_t>(entityList + (uintptr_t)i * 0x8);
        if (!ent || ent == local) continue;
        if (Read<int>(ent + Offsets::PlayerTeamID) == localTeam) continue;
        if (Read<float>(ent + Offsets::PlayerHealth) <= 0.f) continue;

        uintptr_t transform = Read<uintptr_t>(ent + Offsets::PlayerTransform);
        if (!transform) continue;
        Vector3 bonePos = Read<Vector3>(transform + (uintptr_t)g_Aimbot.targetBone * 0xC);
        Vector2 screen  = WorldToScreen(bonePos, camMatrix);

        if (!IsInFov(screen, g_Aimbot.fov)) continue;

        CGSize sz = UIScreen.mainScreen.bounds.size;
        float cx = (float)sz.width * 0.5f;
        float cy = (float)sz.height * 0.5f;
        float dx = screen.x - cx;
        float dy = screen.y - cy;
        float dist = sqrtf(dx*dx + dy*dy);

        if (dist < bestDist) {
            bestDist = dist;
            bestEnt  = ent;
        }
    }

    if (!bestEnt) return;

    if (g_Aimbot.silent) {
        uintptr_t transform = Read<uintptr_t>(bestEnt + Offsets::PlayerTransform);
        if (!transform) return;
        Vector3 targetPos = Read<Vector3>(transform + (uintptr_t)g_Aimbot.targetBone * 0xC);
        uintptr_t localTransform = Read<uintptr_t>(local + Offsets::PlayerTransform);
        if (localTransform)
            Write<Vector3>(localTransform + 0x50, targetPos);
    }
}
