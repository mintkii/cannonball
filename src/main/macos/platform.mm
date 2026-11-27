//
//  platform.mm
//  CannonBall
//
//  Created by Kii on 2026-10-23.
//
#include "platform.hpp"
#include "settings.h"

#include <SDL2/SDL.h>
#import <Cocoa/Cocoa.h>

@interface MenuTarget : NSObject
@end

@implementation MenuTarget

- (void)showAbout:(id)sender
{
    NSMutableParagraphStyle* centred = [NSMutableParagraphStyle new];
    centred.alignment = NSTextAlignmentCenter;

    NSString* site = @"reassembler.blogspot.com";
    NSMutableAttributedString* credits = [[NSMutableAttributedString alloc]
        initWithString:[@"CannonBall engine by Chris White\n" stringByAppendingString:site]
            attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize],
                          NSForegroundColorAttributeName: NSColor.labelColor,
                          NSParagraphStyleAttributeName: centred }];
    [credits addAttribute:NSLinkAttributeName value:[NSURL URLWithString:[@"https://" stringByAppendingString:site]]
                    range:NSMakeRange(credits.length - site.length, site.length)];

    [NSApp orderFrontStandardAboutPanelWithOptions:@{ NSAboutPanelOptionCredits: credits }];
}

- (void)showSettings:(id)sender
{
    [SettingsController.shared showWindow:nil];
}

@end

void platform::init()
{
    // SDL creates the application and its default menu bar here
    SDL_InitSubSystem(SDL_INIT_VIDEO);

    static MenuTarget* target = [MenuTarget new];
    NSMenu* app_menu = NSApp.mainMenu.itemArray.firstObject.submenu;

    // Point SDL's About and Preferences items at our own panels
    for (NSMenuItem* item in app_menu.itemArray)
    {
        if (item.action == @selector(orderFrontStandardAboutPanel:))
        {
            item.action = @selector(showAbout:);
            item.target = target;
        }
        else if ([item.keyEquivalent isEqualToString:@","])
        {
            item.action = @selector(showSettings:);
            item.target = target;
        }
    }
}

std::string platform::ask_for_rom_folder(const std::string& path)
{
    @autoreleasepool
    {
        NSString* folder = @(path.c_str());

        [NSApp activateIgnoringOtherApps:YES];

        NSAlert* alert = [NSAlert new];
        alert.messageText = @"OutRun ROMs Not Found";
        alert.informativeText = [NSString stringWithFormat:@"Place the OutRun Revision B ROMs in this folder, then open CannonBall again:\n\n%@",
                                 folder.stringByAbbreviatingWithTildeInPath];
        [alert addButtonWithTitle:@"Quit"];
        [alert addButtonWithTitle:@"Change Folder..."];
        if ([alert runModal] != NSAlertSecondButtonReturn)
            return "";

        NSOpenPanel* panel = folder_panel(folder);
        if ([panel runModal] != NSModalResponseOK)
            return "";

        return panel.URL.path.UTF8String;
    }
}
