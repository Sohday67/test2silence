//
//  Tweak.x
//  YTLiteSkipSilence
//
//  Logos hooks into YouTube (com.google.ios.youtube).
//
//  Responsibilities:
//    1. Bootstrap OCSkipSilenceEngine when YouTube loads.
//    2. Detect when YouTube creates / replaces its AVPlayer and attach the
//       engine's MTAudioProcessingTap.
//    3. Hook YTLite's settings panel (YTLiteRootSettingsController) to add a
//       "Skip Silence" cell that pushes OCSkipSilenceSettingsController.
//    4. Inject a "Smart Speed saved you Xs" HUD pill into YTInlinePlayerBarView
//       when the user has the HUD toggle on.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AVFAudio/AVFAudio.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "OCHeaders.h"

// ----------------------------------------------------------------------------
//  YouTube class forward declarations. These resolve at runtime via the Logos
//  %hook mechanism; if the class doesn't exist (older YouTube), the hook is
//  silently skipped.
// ----------------------------------------------------------------------------
@class YTPlayerView, YTInlinePlayerBarView, MLPlaybackController,
       YTSettingsViewController, YTSettingsCell, YTLiteRootSettingsController;

// ============================================================================
//  1. Bootstrap — ctor runs at dylib load time.
// ============================================================================
static void OCBootstrap(void) __attribute__((constructor));
static void OCBootstrap(void) {
    @autoreleasepool {
        // Force settings to register defaults.
        [[OCSettings shared] synchronize];
        [[OCSkipSilenceEngine shared] reloadSettings];
        OCLogI(General, @"YTLiteSkipSilence %s loaded", YTLITE_SKIP_SILENCE_VERSION);
    }
}

// ============================================================================
//  2. Hook MLPlaybackController (YouTube's main player controller).
//     Every time YouTube loads a new video, it calls
//       -[MLPlaybackController setPlayerView:]
//     We use this as the "new player" signal.
// ============================================================================
%hook MLPlaybackController

- (void)setPlayerView:(id)playerView {
    %orig;
    @autoreleasepool {
        // Try to extract the underlying AVPlayer.
        AVPlayer *avPlayer = nil;
        SEL playerSel = NSSelectorFromString(@"player");
        if ([playerView respondsToSelector:playerSel]) {
            id p = ((id(*)(id, SEL))objc_msgSend)(playerView, playerSel);
            if ([p isKindOfClass:[AVPlayer class]]) avPlayer = p;
        }
        if (avPlayer) {
            OCLogI(Audio, @"detected AVPlayer at %@ — attaching engine", avPlayer);
            [[OCSkipSilenceEngine shared] attachToPlayer:avPlayer];
        }
    }
}

%end

// ============================================================================
//  3. Hook YTPlayerView lifecycle so we detach when the player is torn down.
// ============================================================================
%hook YTPlayerView

- (void)dealloc {
    [[OCSkipSilenceEngine shared] detach];
    %orig;
}

%end

// ============================================================================
//  4. Hook YTInlinePlayerBarView to render a Smart Speed savings HUD.
// ============================================================================
%hook YTInlinePlayerBarView

static char kOCHUDLabelKey;

- (void)layoutSubviews {
    %orig;

    if (![[OCSettings shared] showTimeSavedHUD]) return;
    if (![[OCSettings shared] useSmartSpeed] && ![[OCSettings shared] skipSilences]) return;

    UILabel *hud = objc_getAssociatedObject(self, &kOCHUDLabelKey);
    if (!hud) {
        hud = [[UILabel alloc] initWithFrame:CGRectMake(8, 2, 200, 14)];
        hud.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        hud.textColor = [UIColor whiteColor];
        hud.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        hud.layer.cornerRadius = 4;
        hud.layer.masksToBounds = YES;
        hud.textAlignment = NSTextAlignmentCenter;
        hud.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        objc_setAssociatedObject(self, &kOCHUDLabelKey, hud, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self addSubview:hud];
    }

    NSTimeInterval saved = [OCSkipSilenceEngine shared].smartSpeedTotalSavings;
    if (saved > 0) {
        int m = (int)(saved / 60.0);
        int s = (int)fmod(saved, 60.0);
        hud.text = [NSString stringWithFormat:@"Smart Speed saved %dm %ds", m, s];
        hud.hidden = NO;
    } else {
        hud.hidden = YES;
    }
}

%end

// ============================================================================
//  5. Hook YTLite's settings controller to add a "Skip Silence" cell.
//     When tapped, push OCSkipSilenceSettingsController (defined in
//     Preferences/YTLiteSkipSilenceSettings.x).
// ============================================================================
%hook YTLiteRootSettingsController

- (NSMutableArray<NSDictionary *> *)settings {
    NSMutableArray *arr = %orig;
    if (!arr) arr = [NSMutableArray array];

    NSDictionary *section = @{
        @"title": @"Skip Silence",
        @"items": @[
            @{
                @"title": @"Skip Silence",
                @"type": @"link",
                @"vcClass": @"OCSkipSilenceSettingsController",
                @"icon": @"forward.fill",
                @"iconColor": @"#FF3B30",
            },
        ],
    };

    BOOL already = NO;
    for (NSDictionary *d in arr) {
        if ([d[@"title"] isEqualToString:section[@"title"]]) { already = YES; break; }
    }
    if (!already) [arr addObject:section];
    return arr;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *section = [self settings][ip.section];
    NSDictionary *item = section[@"items"][ip.row];
    if ([item[@"vcClass"] isEqualToString:@"OCSkipSilenceSettingsController"]) {
        Class cls = NSClassFromString(@"OCSkipSilenceSettingsController");
        if (cls) {
            UIViewController *vc = [[cls alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
            [tv deselectRowAtIndexPath:ip animated:YES];
            return;
        }
    }
    %orig;
}

%end

// ============================================================================
//  6. Also hook the YTSettingsViewController's standard settings table so
//     non-YTLite users get the cell too.
// ============================================================================
%hook YTSettingsViewController

- (void)viewDidLoad {
    %orig;
    // Schedule a reload on next tick so any settings model mutation is
    // picked up.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    NSInteger n = %orig;
    // Inject one extra row at the very end of the last section if we have
    // any rows at all.
    if (section == [self numberOfSectionsInTableView:tv] - 1 && n > 0) {
        return n + 1;
    }
    return n;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSInteger nSections = [self numberOfSectionsInTableView:tv];
    NSInteger nRows = [self tableView:tv numberOfRowsInSection:ip.section];
    if (ip.section == nSections - 1 && ip.row == nRows - 1) {
        // Our injected row.
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"YTLiteSkipSilenceCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:@"YTLiteSkipSilenceCell"];
        }
        cell.textLabel.text = @"Skip Silence";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.imageView.image = [UIImage systemImageNamed:@"forward.fill"];
        cell.imageView.tintColor = [UIColor systemRedColor];
        return cell;
    }
    return %orig;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSInteger nSections = [self numberOfSectionsInTableView:tv];
    NSInteger nRows = [self tableView:tv numberOfRowsInSection:ip.section];
    if (ip.section == nSections - 1 && ip.row == nRows - 1) {
        Class cls = NSClassFromString(@"OCSkipSilenceSettingsController");
        if (cls) {
            UIViewController *vc = [[cls alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        }
        [tv deselectRowAtIndexPath:ip animated:YES];
        return;
    }
    %orig;
}

%end
