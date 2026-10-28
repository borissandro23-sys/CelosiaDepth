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
    NSString *path = @"/var/jb/Library/Application Support/CelosiaDepth/Masks";
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
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
    [img drawInRect:r];
    CGContextSetBlendMode(ctx, kCGBlendModeDestinationIn);
    [m drawInRect:r];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

/// Strict edge-based soft-matte. No regional bias that forces lower screen opaque.
/// Abstract gradient wallpapers (Celosia / iOS 27 Light style) usually reject — use bundled masks.
- (UIImage *)heuristicForegroundFromImage:(UIImage *)image size:(CGSize)size {
    UIImage *scaled = [self scaleImage:image toSize:size];
    CGImageRef cg = scaled.CGImage;
    if (!cg) return nil;

    size_t w = CGImageGetWidth(cg);
    size_t h = CGImageGetHeight(cg);
    if (w < 8 || h < 8) return nil;

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

    float *lum = (float *)malloc(sizeof(float) * w * h);
    if (!lum) { CGContextRelease(ctx); free(buf); return nil; }
    for (size_t y = 0; y < h; y++) {
        for (size_t x = 0; x < w; x++) {
            size_t i = y * bytesPerRow + x * 4;
            lum[y * w + x] = (0.299f * buf[i] + 0.587f * buf[i + 1] + 0.114f * buf[i + 2]) / 255.f;
        }
    }

    size_t opaque = 0;
    float edgeSum = 0.f;
    size_t edgeSamples = 0;
    for (size_t y = 1; y + 1 < h; y++) {
        for (size_t x = 1; x + 1 < w; x++) {
            float tl = lum[(y - 1) * w + (x - 1)];
            float tc = lum[(y - 1) * w + x];
            float tr = lum[(y - 1) * w + (x + 1)];
            float ml = lum[y * w + (x - 1)];
            float mr = lum[y * w + (x + 1)];
            float bl = lum[(y + 1) * w + (x - 1)];
            float bc = lum[(y + 1) * w + x];
            float br = lum[(y + 1) * w + (x + 1)];
            float gx = -tl + tr - 2.f * ml + 2.f * mr - bl + br;
            float gy = -tl - 2.f * tc - tr + bl + 2.f * bc + br;
            float mag = sqrtf(gx * gx + gy * gy);
            edgeSum += mag;
            edgeSamples++;

            uint8_t a = 0;
            if (mag > 0.55f) {
                a = (uint8_t)MIN(255, (int)((mag - 0.55f) * 400.f));
                if (a < 48) a = 0;
            }
            size_t i = y * bytesPerRow + x * 4;
            buf[i + 3] = a;
            if (a > 0) opaque++;
        }
    }
    free(lum);

    float coverage = (float)opaque / (float)(w * h);
    float meanEdge = edgeSamples ? (edgeSum / (float)edgeSamples) : 0.f;

    if ([CDPreferences shared].debugLogging) {
        NSLog(@"[CelosiaDepth] heuristic v2: %zux%zu opaque=%zu coverage=%.4f meanEdge=%.4f",
              w, h, opaque, coverage, meanEdge);
    }

    // Abstract gradients: weak structure or near-full soft edges — reject (no fake matte)
    BOOL reject = (coverage < 0.008f || coverage > 0.22f || meanEdge < 0.08f);
    if (reject) {
        CGContextRelease(ctx);
        free(buf);
        if ([CDPreferences shared].debugLogging) {
            NSLog(@"[CelosiaDepth] heuristic rejected (not depth-capable). "
                  "Abstract Celosia-style wallpapers need a bundled mask PNG.");
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
    if (cached) {
        if ([CDPreferences shared].debugLogging) {
            NSLog(@"[CelosiaDepth] foreground cache hit key=%@", cacheKey);
        }
        return cached;
    }

    UIImage *result = nil;
    NSString *via = nil;
    CDPreferences *prefs = [CDPreferences shared];

    if (prefs.preferBundledMasks && info.matchedMaskName.length) {
        UIImage *mask = [self loadBundledMaskNamed:info.matchedMaskName];
        if (mask) {
            result = [self applyMask:mask toImage:info.image size:targetSize];
            via = info.matchedMaskName;
        } else if (prefs.debugLogging) {
            NSLog(@"[CelosiaDepth] mask file missing for name=%@", info.matchedMaskName);
        }
    }

    if (!result) {
        result = [self heuristicForegroundFromImage:info.image size:targetSize];
        if (result) via = @"heuristic";
    }

    if (result) {
        [[CDCacheManager shared] storeForeground:result forKey:cacheKey];
        if (prefs.debugLogging) {
            NSLog(@"[CelosiaDepth] foreground ready size=%.0fx%.0f via=%@",
                  result.size.width, result.size.height, via ?: @"?");
        }
    } else if (prefs.debugLogging) {
        NSLog(@"[CelosiaDepth] no foreground (matchedMask=%@)", info.matchedMaskName ?: @"(none)");
    }
    return result;
}

@end
