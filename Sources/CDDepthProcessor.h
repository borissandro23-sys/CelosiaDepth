#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CDWallpaperDetector.h"

NS_ASSUME_NONNULL_BEGIN

@interface CDDepthProcessor : NSObject

+ (instancetype)shared;

/// Builds a foreground UIImage (transparent background) suitable for overlay above clock.
/// Uses Core ML segmentation first, then bundled masks and a conservative fallback.
- (nullable UIImage *)foregroundImageForWallpaper:(CDWallpaperInfo *)info
                                       targetSize:(CGSize)targetSize;

/// Runs image processing away from the SpringBoard main thread.
- (void)requestForegroundImageForWallpaper:(CDWallpaperInfo *)info
                                targetSize:(CGSize)targetSize
                                completion:(void (^)(UIImage * _Nullable image))completion;

@end

NS_ASSUME_NONNULL_END
