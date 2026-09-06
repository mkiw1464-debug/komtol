#pragma once
#include "../utils/IL2CPP.h"

struct AimbotConfig {
    bool  enabled   = false;
    bool  silent    = false;
    bool  showFov   = false;
    float fov       = 90.0f;
    int   targetBone = 0; // 0=head,1=neck,6=body,19=leg
};

extern AimbotConfig g_Aimbot;

// Declared here so ESP.mm can include Aimbot.h and use WorldToScreen
Vector2 WorldToScreen(Vector3 world, float *matrix);
bool    IsInFov(Vector2 screen, float fovRadius);
void    AimbotTick();
