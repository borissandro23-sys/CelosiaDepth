#import "CDPreferences.h"

static NSString * const kPrefsPath =
    @"/var/jb/var/mobile/Library/Preferences/com.celosiadepth.tweak.plist";

static void CDPreferencesDidChange(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    [[CDPreferences shared] reload];
}

@implementation CDPreferences {
    BOOL _enabled;
    CGFloat _intensity;
    BOOL _preferBundledMasks;
    BOOL _debugLogging;
}

+ (instancetype)shared {
    static CDPreferences *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[self alloc] init];
    });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reload];
    }
    return self;
}

- (void)reload {
    NSDictionary *dict =
        [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];

    if (!dict) {
        _enabled = YES;
        _intensity = 1.0;
        _preferBundledMasks = YES;
        _debugLogging = NO;
        return;
    }

    _enabled = dict[@"Enabled"]
        ? [dict[@"Enabled"] boolValue] : YES;

    _intensity = dict[@"Intensity"]
        ? [dict[@"Intensity"] doubleValue] : 1.0;

    _preferBundledMasks = dict[@"PreferBundledMasks"]
        ? [dict[@"PreferBundledMasks"] boolValue] : YES;

    _debugLogging = dict[@"DebugLogging"]
        ? [dict[@"DebugLogging"] boolValue] : NO;

    if (_intensity < 0.0) _intensity = 0.0;
    if (_intensity > 1.0) _intensity = 1.0;
}

- (void)observeChanges {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        CDPreferencesDidChange,
        CFSTR("com.celosiadepth.tweak/ReloadPrefs"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );
}

- (BOOL)isEnabled {
    return _enabled;
}

- (CGFloat)intensity {
    return _intensity;
}

- (BOOL)preferBundledMasks {
    return _preferBundledMasks;
}

- (BOOL)debugLogging {
    return _debugLogging;
}

@end
