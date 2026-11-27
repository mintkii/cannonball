//
//  settings.mm
//  CannonBall
//
//  Created by Kii on 2026-10-24.
//
#import "settings.h"
#include "frontend/config.hpp"

static const int FOLDERS = 3;

struct FolderSetting
{
    NSString* title;
    std::string* dir;          // As stored in config.xml
    const std::string* base;   // What a relative dir is relative to
    const char* default_dir;
};

static NSString* folder_path(const FolderSetting& setting)
{
    return @(resolve_data_path(*setting.dir, *setting.base).c_str());
}

NSOpenPanel* folder_panel(NSString* path)
{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = YES;
    panel.prompt = @"Select";
    panel.directoryURL = [NSURL fileURLWithPath:path isDirectory:YES];
    return panel;
}

@implementation SettingsController
{
    FolderSetting settings[FOLDERS];
    NSPopUpButton* popups[FOLDERS];
}

+ (SettingsController*)shared
{
    static SettingsController* shared = [SettingsController new];
    return shared;
}

- (instancetype)init
{
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSZeroRect
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.title = @"Settings";

    if (!(self = [super initWithWindow:window])) return nil;

    settings[0] = { @"ROMs:",      &config.data.rom_dir,  &applicationSupportPath, data_settings_t::DEFAULT_ROM_DIR  };
    settings[1] = { @"Save Data:", &config.data.save_dir, &applicationSupportPath, data_settings_t::DEFAULT_SAVE_DIR };
    settings[2] = { @"Resources:", &config.data.res_dir,  &resourcePath,           data_settings_t::DEFAULT_RES_DIR  };

    NSMutableArray<NSArray<NSView*>*>* rows = [NSMutableArray array];
    for (int i = 0; i < FOLDERS; i++)
    {
        popups[i] = [NSPopUpButton new];
        [popups[i].widthAnchor constraintEqualToConstant:260].active = YES;
        [self refresh:i];

        [rows addObject:@[[NSTextField labelWithString:settings[i].title], popups[i]]];
    }

    NSTextField* note = [NSTextField wrappingLabelWithString:@"Changes take effect the next time CannonBall starts."];
    note.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    note.textColor = NSColor.secondaryLabelColor;
    [rows addObject:@[NSGridCell.emptyContentView, note]];

    NSButton* reveal = [NSButton buttonWithTitle:@"Show config.xml in Finder" target:self action:@selector(revealConfig:)];
    [rows addObject:@[NSGridCell.emptyContentView, reveal]];

    NSGridView* grid = [NSGridView gridViewWithViews:rows];
    grid.rowSpacing = 8;
    grid.columnSpacing = 8;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid rowAtIndex:FOLDERS].topPadding = 4;
    [grid rowAtIndex:FOLDERS + 1].topPadding = 8;

    NSView* content = [NSView new];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [grid.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
        [grid.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [grid.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
    ]];

    window.contentView = content;
    [window setContentSize:content.fittingSize];
    [window center];
    return self;
}

- (void)refresh:(int)i
{
    NSString* path = folder_path(settings[i]);
    NSMenu* menu = [NSMenu new];

    NSMenuItem* folder = [[NSMenuItem alloc] initWithTitle:[NSFileManager.defaultManager displayNameAtPath:path] action:nil keyEquivalent:@""];
    folder.image = [[NSWorkspace.sharedWorkspace iconForFile:path] copy];
    folder.image.size = NSMakeSize(16, 16);
    [menu addItem:folder];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMutableArray<NSMenuItem*>* actions = [NSMutableArray array];
    [actions addObject:[[NSMenuItem alloc] initWithTitle:@"Show in Finder" action:@selector(reveal:) keyEquivalent:@""]];
    if (*settings[i].dir != settings[i].default_dir)
        [actions addObject:[[NSMenuItem alloc] initWithTitle:@"Use Default" action:@selector(reset:) keyEquivalent:@""]];
    [actions addObject:[[NSMenuItem alloc] initWithTitle:@"Other..." action:@selector(choose:) keyEquivalent:@""]];

    for (NSMenuItem* item in actions)
    {
        item.target = self;
        item.tag = i;
        [menu addItem:item];
    }

    popups[i].menu = menu;
    popups[i].toolTip = path.stringByAbbreviatingWithTildeInPath;
    [popups[i] selectItemAtIndex:0];
}

- (void)apply:(int)i dir:(std::string)dir
{
    *settings[i].dir = dir;
    config.save();
    [self refresh:i];
}

- (void)choose:(NSMenuItem*)sender
{
    const int i = (int)sender.tag;
    [popups[i] selectItemAtIndex:0];

    NSOpenPanel* panel = folder_panel(folder_path(settings[i]));
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK)
            [self apply:i dir:panel.URL.path.UTF8String];
    }];
}

- (void)reset:(NSMenuItem*)sender
{
    const int i = (int)sender.tag;
    [self apply:i dir:settings[i].default_dir];
}

- (void)reveal:(NSMenuItem*)sender
{
    const int i = (int)sender.tag;
    [popups[i] selectItemAtIndex:0];
    [NSWorkspace.sharedWorkspace selectFile:nil inFileViewerRootedAtPath:folder_path(settings[i])];
}

- (void)revealConfig:(id)sender
{
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:@(config.data.cfg_file.c_str())]]];
}

@end
