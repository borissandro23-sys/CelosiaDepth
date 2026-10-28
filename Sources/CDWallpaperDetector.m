#import "CDWallpaperDetector.h"
#import "CDPreferences.h"

/*
 iOS 15 SpringBoard wallpaper surfaces (verify on device):
 - SBWallpaperController (private)
 - SBFWallpaperView / SBWallpaperEffectView
 Paths under /var/mobile/Library/SpringBoard/ for still images.

 Rootless Dopamine: filesystem paths are not prefixed for user data under
 /var/mobile — only jb paths use /var/jb.
*/

@implementation CDWallpaperInfo
@end

@implementation CDWallpaperDetector

+ (instancetype)shared {
    static CDWallpaperDetector *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (NSArray<NSString *> *)candidateStillPaths {
    // Common iOS 15 still-wallpaper locations. Existence checked at runtime.
    return @[
        @"/var/mobile/Library/SpringBoard/LockBackground.cpbitmap",
        @"/var/mobile/Library/SpringBoard/LockBackgroundThumbnail.jpg",
        @"/var/mobile/Library/SpringBoard/HomeBackground.cpbitmap",
        @"/var/mobile/Media/DCIM", // not used directly; placeholder for future Photo-based wallpapers
    ];
}

/// Minimal cpbitmap reader for device RGB images used by SpringBoard.
/// Returns nil if format is unsupported.
- (UIImage *)imageFromCPBitmapAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length < 16) return nil;

    // cpbitmap layout varies by iOS generation. On many iOS 14–15 builds:
    // trailing footer contains width/height. This is best-effort.
    const uint8_t *bytes = data.bytes;
    NSUInteger len = data.length;

    // Try to read width/height from last 16 bytes (common pattern)
    if (len < 32) return nil;
    uint32_t width = 0, height = 0;
    memcpy(&width, bytes + len - 8, 4);
    memcpy(&height, bytes + len - 4, 4);
    // Sanity for iPhone 6s logical/native ranges
    if (width < 320 || width > 4096 || height < 480 || height > 4096) {
        // Fallback: search for plausible dimensions in footer region
        width = height = 0;
        for (NSInteger i = (NSInteger)len - 64; i >= 0 && i < (NSInteger)len - 8; i--) {
            uint32_t w = 0, h = 0;
            memcpy(&w, bytes + i, 4);
            memcpy(&h, bytes + i + 4, 4);
            if (w >= 640 && w <= 2048 && h >= 960 && h <= 4096) {
                width = w; height = h;
                break;
            }
        }
    }
    if (width == 0 || height == 0) return nil;

    size_t pixelBytes = (size_t)width * (size_t)height * 4;
    if (pixelBytes + 16 > len) return nil;

    // Pixels usually start at 0 for still cpbitmap on device
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate((void *)bytes, width, height, 8, width * 4, cs,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!ctx) {
        // Try alternative byte order
        ctx = CGBitmapContextCreate((void *)bytes, width, height, 8, width * 4, CGColorSpaceCreateDeviceRGB(),
                                    kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    }
    if (!ctx) return nil;
    CGImageRef cg = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (!cg) return nil;
    UIImage *img = [UIImage imageWithCGImage:cg scale:2.0 orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return img;
}

- (UIImage *)imageFromJPEGAtPath:(NSString *)path {
    return [UIImage imageWithContentsOfFile:path];
}

- (NSString *)fileFingerprint:(NSString *)path {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attrs) return nil;
    unsigned long long sz = attrs.fileSize;
    NSDate *mod = attrs.fileModificationDate;
    return [NSString stringWithFormat:@"%@|%llu|%.0f", path.lastPathComponent, sz, mod.timeIntervalSince1970];
}

- (CDWallpaperInfo *)currentLockScreenWallpaper {
    CDWallpaperInfo *info = [[CDWallpaperInfo alloc] init];
    info.isLockScreen = YES;

    NSString *cp = @"/var/mobile/Library/SpringBoard/LockBackground.cpbitmap";
    NSString *thumb = @"/var/mobile/Library/SpringBoard/LockBackgroundThumbnail.jpg";

    UIImage *img = nil;
    NSString *key = nil;

    if ([[NSFileManager defaultManager] fileExistsAtPath:cp]) {
        img = [self imageFromCPBitmapAtPath:cp];
        key = [self fileFingerprint:cp];
    }
    if (!img && [[NSFileManager defaultManager] fileExistsAtPath:thumb]) {
        img = [self imageFromJPEGAtPath:thumb];
        key = [self fileFingerprint:thumb];
    }

    // Optional: try private SBWallpaperController if class exists (device verification required)
    if (!img) {
        Class cls = NSClassFromString(@"SBWallpaperController");
        if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id ctrl = [cls performSelector:@selector(sharedInstance)];
#pragma clang diagnostic pop
            // Do not call unconfirmed selectors; only log presence when debugging.
            if ([CDPreferences shared].debugLogging && ctrl) {
                NSLog(@"[CelosiaDepth] SBWallpaperController present; extend snapshot path after device probe.");
            }
        }
    }

    info.image = img;
    info.identityKey = key ?: @"unknown";
    info.matchedMaskName = [self guessCelosiaMaskNameForImage:img];
    return img ? info : nil;
}

- (NSString *)currentWallpaperFingerprint {
    NSString *cp = @"/var/mobile/Library/SpringBoard/LockBackground.cpbitmap";
    if ([[NSFileManager defaultManager] fileExistsAtPath:cp]) {
        return [self fileFingerprint:cp];
    }
    NSString *thumb = @"/var/mobile/Library/SpringBoard/LockBackgroundThumbnail.jpg";
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumb]) {
        return [self fileFingerprint:thumb];
    }
    return nil;
}

/// Placeholder matcher: compare average color / aspect heuristics.
/// Replace with perceptual hash once real Celosia assets are bundled.
- (NSString *)guessCelosiaMaskNameForImage:(UIImage *)image {
    if (!image) return nil;
    // Bundled mask names (add PNGs under Resources/Masks/)
    // e.g. celosia_variant_a.png mask with same canvas size as processed wallpaper
    CGSize s = image.size;
    if (s.width <= 0 || s.height <= 0) return nil;

    // Explicit opt-in: if the user manually installs this exact mask file, use it
    // for the iOS 27 Light wallpaper. Presence of the file is the opt-in signal;
    // it is NOT image recognition, so remove/rename the file for other wallpapers.
    NSString *maskPath = [@"/var/jb/Library/Application Support/CelosiaDepth/Masks"
        stringByAppendingPathComponent:@"ios27_light.png"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:maskPath]) {
        if ([CDPreferences shared].debugLogging) {
            NSLog(@"[CelosiaDepth] manual mask selected: ios27_light (file exists; no perceptual match performed)");
        }
        return @"ios27_light";
    }

    (void)s;
    return nil;
}

@end
