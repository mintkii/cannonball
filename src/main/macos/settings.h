//
//  settings.h
//  CannonBall
//
//  Created by Kii on 2026-10-24.
//
#pragma once

#import <Cocoa/Cocoa.h>

@interface SettingsController : NSWindowController
@property (class, readonly) SettingsController* shared;
@end

// Open panel for picking a folder, starting in path
NSOpenPanel* folder_panel(NSString* path);
