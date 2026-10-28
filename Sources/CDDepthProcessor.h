#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CDWallpaperDetector.h"

NS_ASSUME_NONNULL_BEGIN

@interface CDDepthProcessor : NSObject

+ (instancetype)shared;

/// Builds a transparent foreground image for the overlay above the lock-screen clock.
/// A manually authored mask is preferred. The fallback is only an experimental edge map,
/// not semantic segmentation and not a guarantee of a native-style depth effect.
/// Returns nil when the result would be unreliable.
- (nullable UIImage *)foregroundImageForWallpaper:(CDWallpaperInfo *)info
                                       targetSize:(CGSize)targetSize;

@end

NS_ASSUME_NONNULL_END
