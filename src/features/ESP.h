#pragma once
#include "../utils/IL2CPP.h"
#import <CoreGraphics/CoreGraphics.h>  // fix: CGContextRef definition

struct ESPConfig {
    bool enabled  = false;
    bool showName = true;
    bool showBox  = true;
    bool showLine = false;
    bool showHP   = true;
};

extern ESPConfig g_ESP;

struct ESPEntry {
    Vector2 screenPos;
    Vector2 screenFoot;
    float   health;
    char    name[64];
    bool    valid;
};

void ESPCollect();
void ESPRender(CGContextRef ctx);
