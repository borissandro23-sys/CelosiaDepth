#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CDWallpaperDetector.h"

NS_ASSUME_NONNULL_BEGIN

@interface CDDepthProcessor : NSObject

+ (instancetype)shared;

/// Builds a foreground UIImage (transparent background) suitable for overlay above clock.
/// Uses bundled mask when matched; otherwise a lightweight luminance/edge heuristic.
/// Returns nil when result would be unreliable (avoids covering clock with noise).
- (nullable UIImage *)foregroundImageForWallpaper:(CDWallpaperInfo *)info
                                       targetSize:(CGSize)targetSize;

@end

NS_ASSUME_NONNULL_END
