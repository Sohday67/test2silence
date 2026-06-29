//
//  YTLiteSkipSilenceSettings.x
//  YTLiteSkipSilence
//
//  Standalone settings view controller, used when the host app is not YTLite
//  (e.g. when the user opens the tweak via a YouTube settings entry instead
//  of the YTLite extension panel). Conforms to the YTLite extension settings
//  protocol so YTLite can instantiate it directly via the descriptor.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "OCSettings.h"
#import "OCSkipSilenceEngine.h"
#import "OCSmartSpeedTracker.h"
#import "OCLog.h"

@interface OCSkipSilenceSettingsController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;
@end

@implementation OCSkipSilenceSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Skip Silence";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];

    self.sections = [self buildSections];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSavingsChange:)
                                                 name:OCSmartSpeedSavingsDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleSavingsChange:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    });
}

- (NSArray<NSDictionary *> *)buildSections {
    OCSettings *s = [OCSettings shared];
    NSTimeInterval totalSaved = s.smartSpeedTotalSavings;
    int m = (int)(totalSaved / 60.0);
    int sec = (int)fmod(totalSaved, 60.0);

    return @[
        @{
            @"title": @"Smart Speed Savings",
            @"items": @[
                @{ @"title": @"Total time saved",
                   @"type": @"value",
                   @"value": [NSString stringWithFormat:@"%dm %ds", m, sec] },
                @{ @"title": @"Reset Savings",
                   @"type": @"button",
                   @"key":  @"reset" },
            ],
        },
        @{
            @"title": @"Skip Silence",
            @"items": @[
                @{ @"title": @"Skip Silence (jump past silence)",
                   @"type": @"switch",
                   @"key":  OCSettingsKeySkipSilences },
                @{ @"title": @"Smart Speed (play silence faster)",
                   @"type": @"switch",
                   @"key":  OCSettingsKeyUseSmartSpeed },
                @{ @"title": @"Music Detection (bypass Smart Speed)",
                   @"type": @"switch",
                   @"key":  OCSettingsKeyUseSmartSpeedMusicDetection },
            ],
        },
        @{
            @"title": @"Tuning",
            @"items": @[
                @{ @"title": @"Silence Threshold (dBFS)",
                   @"type": @"slider",
                   @"key":  OCSettingsKeySilenceThresholdDBFS,
                   @"min": @-60, @"max": @-20 },
                @{ @"title": @"Minimum Silence (s)",
                   @"type": @"slider",
                   @"key":  OCSettingsKeyMinimumSilenceDuration,
                   @"min": @0.1, @"max": @2.0 },
                @{ @"title": @"Silence Skipping Speed",
                   @"type": @"slider",
                   @"key":  OCSettingsKeySilenceSkippingSpeed,
                   @"min": @1.25, @"max": @3.0 },
            ],
        },
        @{
            @"title": @"Voice Boost (optional)",
            @"items": @[
                @{ @"title": @"Voice Boost",
                   @"type": @"switch",
                   @"key":  OCSettingsKeyUseVoiceBoost },
                @{ @"title": @"Standard Preset",
                   @"type": @"switch",
                   @"key":  OCSettingsKeyStandardVoiceBoostConfiguration },
            ],
        },
        @{
            @"title": @"UI & Debug",
            @"items": @[
                @{ @"title": @"Show Time-Saved HUD",
                   @"type": @"switch",
                   @"key":  OCSettingsKeyShowTimeSavedHUD },
                @{ @"title": @"Verbose Logging",
                   @"type": @"switch",
                   @"key":  OCSettingsKeyVerboseLogging },
            ],
        },
    ];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return [self.sections[section][@"items"] count];
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return self.sections[section][@"title"];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *item = self.sections[ip.section][@"items"][ip.row];
    NSString *type = item[@"type"];
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];

    if ([type isEqualToString:@"switch"]) {
        cell.textLabel.text = item[@"title"];
        UISwitch *sw = [UISwitch new];
        [sw addTarget:self action:@selector(switchChanged:event:) forControlEvents:UIControlEventValueChanged];
        sw.on = [[OCSettings shared].defaults boolForKey:item[@"key"]];
        sw.tag = ip.section * 1000 + ip.row;
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"slider"]) {
        cell.textLabel.text = item[@"title"];
        UISlider *sl = [UISlider new];
        sl.minimumValue = [item[@"min"] floatValue];
        sl.maximumValue = [item[@"max"] floatValue];
        sl.value = [[OCSettings shared].defaults floatForKey:item[@"key"]];
        [sl addTarget:self action:@selector(sliderChanged:event:) forControlEvents:UIControlEventValueChanged];
        sl.tag = ip.section * 1000 + ip.row;
        cell.accessoryView = sl;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"button"]) {
        cell.textLabel.text = item[@"title"];
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessoryView = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if ([type isEqualToString:@"value"]) {
        cell.textLabel.text = item[@"title"];
        cell.detailTextLabel.text = item[@"value"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *item = self.sections[ip.section][@"items"][ip.row];
    if ([item[@"type"] isEqualToString:@"button"] && [item[@"key"] isEqualToString:@"reset"]) {
        [[OCSmartSpeedTracker shared] resetSavings];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"YTLiteSkipSilence"
                                                                    message:@"Smart Speed savings have been reset."
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        [tv reloadSections:[NSIndexSet indexSetWithIndex:ip.section]
          withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)switchChanged:(UISwitch *)sw event:(UIEvent *)ev {
    NSIndexPath *ip = [self indexPathForView:sw inTableView:self.tableView];
    if (!ip) return;
    NSDictionary *item = self.sections[ip.section][@"items"][ip.row];
    NSString *key = item[@"key"];
    [[OCSettings shared].defaults setBool:sw.on forKey:key];
    [[OCSettings shared] synchronize];
    [[OCSkipSilenceEngine shared] reloadSettings];
    OCLogI(General, @"setting %@ = %@", key, sw.on ? @"YES" : @"NO");
}

- (void)sliderChanged:(UISlider *)sl event:(UIEvent *)ev {
    NSIndexPath *ip = [self indexPathForView:sl inTableView:self.tableView];
    if (!ip) return;
    NSDictionary *item = self.sections[ip.section][@"items"][ip.row];
    NSString *key = item[@"key"];
    [[OCSettings shared].defaults setFloat:sl.value forKey:key];
    [[OCSettings shared] synchronize];
    [[OCSkipSilenceEngine shared] reloadSettings];
}

- (nullable NSIndexPath *)indexPathForView:(UIView *)v inTableView:(UITableView *)tv {
    UIView *cur = v;
    while (cur && cur != tv) {
        if ([cur isKindOfClass:[UITableViewCell class]]) {
            return [tv indexPathForCell:(UITableViewCell *)cur];
        }
        cur = cur.superview;
    }
    return nil;
}

@end
