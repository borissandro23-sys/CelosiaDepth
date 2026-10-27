#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CDWallpaperInfo : NSObject
@property (nonatomic, strong, nullable) UIImage *image;
@property (nonatomic, copy, nullable) NSString *identityKey; // for cache
@property (nonatomic, copy, nullable) NSString *matchedMaskName; // bundled mask id if known
@property (nonatomic, assign) BOOL isLockScreen;
@end

@interface CDWallpaperDetector : NSObject

+ (instancetype)shared;

/// Best-effort snapshot of current lock-screen wallpaper on iOS 15.
/// Returns nil if unavailable. Must be called on main thread for UIKit bits.
- (nullable CDWallpaperInfo *)currentLockScreenWallpaper;

/// Lightweight fingerprint of current wallpaper for change detection.
- (nullable NSString *)currentWallpaperFingerprint;

@end

NS_ASSUME_NONNULL_END
