/*
 CelosiaDepth — lock-screen depth overlay for iOS 15 (rootless / Dopamine)

 Private class names used below are the common iOS 14/15 SpringBoard surfaces.
 They MUST be verified with FLEX / class-dump on the target 15.8.x build.
 Hooks fail soft when classes are missing.
*/

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Sources/CDPreferences.h"
#import "Sources/CDWallpaperDetector.h"
#import "Sources/CDDepthProcessor.h"
#import "Sources/CDDepthOverlayView.h"
#import "Sources/CDCacheManager.h"

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
@end

static CDDepthOverlayView *CDOverlay = nil;
static NSString *CDLastFingerprint = nil;
static BOOL CDRefreshScheduled = NO;

static void CDLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
static void CDLog(NSString *fmt, ...) {
    if (![CDPreferences shared].debugLogging) return;
    va_list args;
    va_start(args, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[CelosiaDepth] %@", s);
}

static UIView *CDFindClockHostInView(UIView *root) {
    if (!root) return nil;
    NSString *clsName = NSStringFromClass(root.class);
    if ([clsName containsString:@"LockScreenDate"] || [clsName containsString:@"SBFLockScreenDateView"]) {
        return root.superview ?: root;
    }
    for (UIView *sub in root.subviews) {
        UIView *found = CDFindClockHostInView(sub);
        if (found) return found;
    }
    return nil;
}

static UIView *CDLikelyLockContentView(void) {
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        UIView *found = CDFindClockHostInView(window);
        if (found) return found;
    }
    return nil;
}

static void CDRemoveOverlay(void) {
    if (CDOverlay) {
        [CDOverlay removeFromSuperview];
        CDOverlay = nil;
    }
}

static void CDEnsureOverlayAboveClock(UIView *clockRelated) {
    if (!clockRelated) return;
    UIView *parent = clockRelated.superview ?: clockRelated;
    if (!CDOverlay) {
        CDOverlay = [[CDDepthOverlayView alloc] initWithFrame:parent.bounds];
        CDOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        CDOverlay.tag = 0xCE10CA;
    }
    for (UIView *v in parent.subviews) {
        if (v != CDOverlay && v.tag == 0xCE10CA) {
            [v removeFromSuperview];
        }
    }
    if (CDOverlay.superview != parent) {
        [CDOverlay removeFromSuperview];
        NSUInteger idx = [parent.subviews indexOfObject:clockRelated];
        if (idx != NSNotFound) {
            [parent insertSubview:CDOverlay aboveSubview:clockRelated];
        } else {
            [parent addSubview:CDOverlay];
        }
    }
    CDOverlay.frame = parent.bounds;
}

static void CDRefreshDepthEffect(void) {
    CDRefreshScheduled = NO;
    if (![CDPreferences shared].isEnabled) {
        CDLog(@"disabled; removing overlay");
        CDRemoveOverlay();
        return;
    }

    NSString *fp = [[CDWallpaperDetector shared] currentWallpaperFingerprint];
    CDWallpaperInfo *info = [[CDWallpaperDetector shared] currentLockScreenWallpaper];
    if (!info.image) {
        CDLog(@"no wallpaper image");
        CDRemoveOverlay();
        return;
    }
    CDLog(@"wallpaper loaded source=%@ size=%.0fx%.0f maskHint=%@",
          info.identityKey,
          info.image.size.width, info.image.size.height,
          info.matchedMaskName ?: @"(none)");

    UIView *clockHost = CDLikelyLockContentView();
    if (!clockHost) {
        CDLog(@"clock host not found yet");
        return;
    }
    CDLog(@"clockHost=%@ frame=%@ parent=%@",
          NSStringFromClass(clockHost.class),
          NSStringFromCGRect(clockHost.frame),
          clockHost.superview ? NSStringFromClass(clockHost.superview.class) : @"(nil)");

    CDEnsureOverlayAboveClock(clockHost);
    CDLog(@"overlay superview=%@ frame=%@ hidden=%d alpha=%.2f",
          CDOverlay.superview ? NSStringFromClass(CDOverlay.superview.class) : @"(nil)",
          NSStringFromCGRect(CDOverlay.frame),
          CDOverlay.hidden, CDOverlay.alpha);

    CGSize target = clockHost.superview ? clockHost.superview.bounds.size : UIScreen.mainScreen.bounds.size;
    CGFloat maxSide = 750.0;
    if (target.width > maxSide || target.height > maxSide) {
        CGFloat scale = maxSide / MAX(target.width, target.height);
        target = CGSizeMake(floor(target.width * scale), floor(target.height * scale));
    }

    UIImage *fg = [[CDDepthProcessor shared] foregroundImageForWallpaper:info targetSize:target];
    if (!fg) {
        CDLog(@"no reliable foreground; clearing overlay");
        [CDOverlay clearContent];
        return;
    }

    [CDOverlay setForegroundImage:fg intensity:[CDPreferences shared].intensity];
    CDLastFingerprint = fp;
    CDLog(@"overlay updated key=%@ fgSize=%.0fx%.0f intensity=%.2f",
          info.identityKey, fg.size.width, fg.size.height, [CDPreferences shared].intensity);
}

static void CDScheduleRefresh(void) {
    if (CDRefreshScheduled) return;
    CDRefreshScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CDRefreshDepthEffect();
    });
}

%ctor {
    @autoreleasepool {
        [[CDPreferences shared] observeChanges];
        CDLog(@"loaded (iOS 15 / rootless build)");
    }
}

%hook SBLockScreenManager
- (void)lockUIFromSource:(int)source withOptions:(id)options {
    %orig;
    CDScheduleRefresh();
}
- (void)unlockUIFromSource:(int)source withOptions:(id)options {
    %orig;
}
%end

%hook CSCoverSheetViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    CDScheduleRefresh();
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
}
%end

%hook SBWallpaperController
- (void)setWallpaperImage:(id)image forVariant:(long long)variant {
    %orig;
    if (variant == 0 || variant == 1) {
        [[CDCacheManager shared] invalidateAll];
        CDLastFingerprint = nil;
        CDScheduleRefresh();
    }
}
%end

static void CDRegisterNotifications(void) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(__unused NSNotification *n) { CDScheduleRefresh(); }];
}

%ctor {
    CDRegisterNotifications();
}
