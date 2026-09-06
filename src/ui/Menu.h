#pragma once
#import <UIKit/UIKit.h>

void InitMenu();
void ToggleMenu();
void HandleTap();

// Exposed draw view so main.mm can call setNeedsDisplay
extern UIView *drawView;
