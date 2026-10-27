#import "CDDepthProcessor.h"
#import "CDCacheManager.h"
#import "CDPreferences.h"

@implementation CDDepthProcessor

+ (instancetype)shared {
    static CDDepthProcessor *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (NSString *)bundleMasksPath {
    // Prefer rootless tweak resources path when installed via Theos layout
    NSString *path = @"/var/jb/Library/Application Support/CelosiaDepth/Masks";
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    // Fallback relative to dylib bundle
    NSString *bundle = [[NSBundle mainBundle] bundlePath];
    return [bundle stringByAppendingPathComponent:@"Masks"];
}

- (UIImage *)loadBundledMaskNamed:(NSString *)name {
    if (name.length == 0) return nil;
    NSString *path = [[self bundleMasksPath] stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
    return [UIImage imageWithContentsOfFile:path];
}

- (UIImage *)scaleImage:(UIImage *)image toSize:(CGSize)size {
    if (size.width <= 0 || size.height <= 0) return image;
    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out ?: image;
}

- (UIImage *)applyMask:(UIImage *)mask toImage:(UIImage *)image size:(CGSize)size {
    UIImage *img = [self scaleImage:image toSize:size];
    UIImage *m = [self scaleImage:mask toSize:size];
    CGRect r = CGRectMake(0, 0, size.width, size.height);
    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    // Draw wallpaper
    [img drawInRect:r];
    // Keep only mask luminance as alpha
    CGContextSetBlendMode(ctx, kCGBlendModeDestinationIn);
    [m drawInRect:r];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

/// Conservative soft-matte: keep brighter / higher-contrast upper-mid regions only if
/// enough opaque pixels exist. Abstract wallpapers often fail the coverage test → nil.
- (UIImage *)heuristicForegroundFromImage:(UIImage *)image size:(CGSize)size {
    UIImage *scaled = [self scaleImage:image toSize:size];
    CGImageRef cg = scaled.CGImage;
    if (!cg) return nil;

    size_t w = CGImageGetWidth(cg);
    size_t h = CGImageGetHeight(cg);
    if (w == 0 || h == 0) return nil;

    size_t bytesPerRow = w * 4;
    size_t bufSize = bytesPerRow * h;
    uint8_t *buf = calloc(1, bufSize);
    if (!buf) return nil;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, w, h, 8, bytesPerRow, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(buf); return nil; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);

    // Build alpha from local contrast; bias toward lower third (typical subject placement
    // for depth-capable wallpapers). Abstract patterns stay noisy → reject by coverage.
    size_t opaque = 0;
    size_t total = w * h;
    for (size_t y = 0; y < h; y++) {
        for (size_t x = 0; x < w; x++) {
            size_t i = y * bytesPerRow + x * 4;
            uint8_t r = buf[i], g = buf[i+1], b = buf[i+2];
            float lum = (0.299f * r + 0.587f * g + 0.114f * b) / 255.f;
            // neighbor contrast
            size_t x2 = x + 1 < w ? x + 1 : x;
            size_t i2 = y * bytesPerRow + x2 * 4;
            float lum2 = (0.299f * buf[i2] + 0.587f * buf[i2+1] + 0.114f * buf[i2+2]) / 255.f;
            float edge = fabsf(lum - lum2);
            float score = edge * 1.4f + (y > h * 0.35f ? 0.15f : 0.0f);
            uint8_t a = score > 0.12f ? (uint8_t)MIN(255, (int)(score * 255.f * 2.f)) : 0;
            if (a < 40) a = 0;
            buf[i+3] = a;
            if (a > 0) opaque++;
        }
    }

    float coverage = (float)opaque / (float)total;
    // Too little or too much → unreliable abstract wallpaper
    if (coverage < 0.02f || coverage > 0.45f) {
        CGContextRelease(ctx);
        free(buf);
        if ([CDPreferences shared].debugLogging) {
            NSLog(@"[CelosiaDepth] heuristic rejected coverage=%.3f", coverage);
        }
        return nil;
    }

    CGImageRef outCG = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    free(buf);
    if (!outCG) return nil;
    UIImage *out = [UIImage imageWithCGImage:outCG scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(outCG);
    return out;
}

- (UIImage *)foregroundImageForWallpaper:(CDWallpaperInfo *)info targetSize:(CGSize)targetSize {
    if (!info.image || targetSize.width < 1 || targetSize.height < 1) return nil;

    NSString *cacheKey = [NSString stringWithFormat:@"%@|%.0fx%.0f", info.identityKey, targetSize.width, targetSize.height];
    UIImage *cached = [[CDCacheManager shared] cachedForegroundForKey:cacheKey];
    if (cached) return cached;

    UIImage *result = nil;
    CDPreferences *prefs = [CDPreferences shared];

    if (prefs.preferBundledMasks && info.matchedMaskName.length) {
        UIImage *mask = [self loadBundledMaskNamed:info.matchedMaskName];
        if (mask) {
            result = [self applyMask:mask toImage:info.image size:targetSize];
        }
    }

    if (!result) {
        result = [self heuristicForegroundFromImage:info.image size:targetSize];
    }

    if (result) {
        [[CDCacheManager shared] storeForeground:result forKey:cacheKey];
    }
    return result;
}

@end
