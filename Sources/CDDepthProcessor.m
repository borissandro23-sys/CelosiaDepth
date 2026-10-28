#import "CDDepthProcessor.h"
#import "CDCacheManager.h"
#import "CDPreferences.h"
#import <math.h>

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
    return [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Masks"];
}

- (UIImage *)loadBundledMaskNamed:(NSString *)name {
    if (name.length == 0) return nil;
    NSString *path = [[self bundleMasksPath] stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
    UIImage *mask = [UIImage imageWithContentsOfFile:path];
    if ([CDPreferences shared].debugLogging) {
        NSLog(@"[CelosiaDepth] mask lookup name=%@ path=%@ exists=%d loaded=%d",
              name, path, [[NSFileManager defaultManager] fileExistsAtPath:path], mask != nil);
    }
    return mask;
}

- (UIImage *)scaleImage:(UIImage *)image toSize:(CGSize)size {
    if (!image || size.width <= 0 || size.height <= 0) return image;
    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out ?: image;
}

/// White mask pixels are foreground; black pixels are transparent. Uses luminance,
/// not merely the source PNG alpha channel.
- (UIImage *)applyMask:(UIImage *)mask toImage:(UIImage *)image size:(CGSize)size {
    if (!mask || !image || size.width < 1 || size.height < 1) return nil;
    UIImage *wallpaper = [self scaleImage:image toSize:size];
    UIImage *scaledMask = [self scaleImage:mask toSize:size];
    CGImageRef wallCG = wallpaper.CGImage, maskCG = scaledMask.CGImage;
    if (!wallCG || !maskCG) return nil;

    size_t w = (size_t)size.width, h = (size_t)size.height;
    if (w == 0 || h == 0 || w > SIZE_MAX / 4 / h) return nil;
    size_t row = w * 4, bytes = row * h;
    uint8_t *wall = calloc(1, bytes), *matte = calloc(1, bytes), *out = calloc(1, bytes);
    if (!wall || !matte || !out) { free(wall); free(matte); free(out); return nil; }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    if (!cs) { free(wall); free(matte); free(out); return nil; }
    CGContextRef wc = CGBitmapContextCreate(wall, w, h, 8, row, cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextRef mc = CGBitmapContextCreate(matte, w, h, 8, row, cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (!wc || !mc) {
        if (wc) CGContextRelease(wc);
        if (mc) CGContextRelease(mc);
        CGColorSpaceRelease(cs);
        free(wall); free(matte); free(out);
        return nil;
    }
    CGContextDrawImage(wc, CGRectMake(0, 0, w, h), wallCG);
    CGContextDrawImage(mc, CGRectMake(0, 0, w, h), maskCG);
    CGContextRelease(wc);
    CGContextRelease(mc);

    size_t nonzero = 0;
    for (size_t i = 0; i < w * h; i++) {
        size_t p = i * 4;
        // Bitmap RGB values are premultiplied, so transparent mask pixels have zero luminance.
        unsigned int lum = (77u * matte[p] + 150u * matte[p + 1] + 29u * matte[p + 2]) >> 8;
        uint8_t a = (uint8_t)MIN(255u, lum);
        out[p] = (uint8_t)((wall[p] * a) / 255u);
        out[p + 1] = (uint8_t)((wall[p + 1] * a) / 255u);
        out[p + 2] = (uint8_t)((wall[p + 2] * a) / 255u);
        out[p + 3] = a;
        if (a > 0) nonzero++;
    }
    free(wall);
    free(matte);

    CGContextRef oc = CGBitmapContextCreate(out, w, h, 8, row, cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!oc) { free(out); return nil; }
    CGImageRef resultCG = CGBitmapContextCreateImage(oc);
    CGContextRelease(oc);
    free(out);
    if (!resultCG) return nil;
    UIImage *result = [UIImage imageWithCGImage:resultCG scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(resultCG);
    if ([CDPreferences shared].debugLogging) {
        NSLog(@"[CelosiaDepth] mask applied size=%zux%zu coverage=%.4f",
              w, h, (double)nonzero / (double)(w * h));
    }
    return result;
}

/// Experimental edge-only fallback. It detects boundaries, not semantic objects.
/// A manual mask is needed for predictable foreground-over-clock behavior.
- (UIImage *)heuristicForegroundFromImage:(UIImage *)image size:(CGSize)size {
    UIImage *scaled = [self scaleImage:image toSize:size];
    CGImageRef cg = scaled.CGImage;
    if (!cg) return nil;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    if (w < 8 || h < 8 || w > SIZE_MAX / 4 / h) return nil;

    size_t row = w * 4, bytes = row * h;
    uint8_t *buf = calloc(1, bytes);
    float *lum = malloc(sizeof(float) * w * h);
    if (!buf || !lum) { free(buf); free(lum); return nil; }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, w, h, 8, row, cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(buf); free(lum); return nil; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);

    for (size_t y = 0; y < h; y++) {
        for (size_t x = 0; x < w; x++) {
            size_t p = y * row + x * 4;
            lum[y * w + x] = (0.299f * buf[p] + 0.587f * buf[p + 1] + 0.114f * buf[p + 2]) / 255.f;
        }
    }

    size_t nonzero = 0;
    double edgeSum = 0.0;
    for (size_t y = 1; y + 1 < h; y++) {
        for (size_t x = 1; x + 1 < w; x++) {
            float tl=lum[(y-1)*w+x-1], tc=lum[(y-1)*w+x], tr=lum[(y-1)*w+x+1];
            float ml=lum[y*w+x-1], mr=lum[y*w+x+1];
            float bl=lum[(y+1)*w+x-1], bc=lum[(y+1)*w+x], br=lum[(y+1)*w+x+1];
            float gx = -tl + tr - 2.f*ml + 2.f*mr - bl + br;
            float gy = -tl - 2.f*tc - tr + bl + 2.f*bc + br;
            float mag = sqrtf(gx*gx + gy*gy);
            edgeSum += mag;
            uint8_t a = 0;
            if (mag > 0.55f) {
                a = (uint8_t)MIN(255, (int)((mag - 0.55f) * 400.f));
                if (a < 48) a = 0;
            }
            size_t p = y * row + x * 4;
            buf[p] = (uint8_t)((buf[p] * a) / 255u);
            buf[p+1] = (uint8_t)((buf[p+1] * a) / 255u);
            buf[p+2] = (uint8_t)((buf[p+2] * a) / 255u);
            buf[p+3] = a;
            if (a > 0) nonzero++;
        }
    }
    free(lum);

    float coverage = (float)nonzero / (float)(w * h);
    float meanEdge = (float)(edgeSum / (double)((w - 2) * (h - 2)));
    if ([CDPreferences shared].debugLogging) {
        NSLog(@"[CelosiaDepth] heuristic v2: image=%zux%zu nonzero=%zu coverage=%.4f meanEdge=%.4f",
              w, h, nonzero, coverage, meanEdge);
    }
    if (coverage < 0.008f || coverage > 0.22f || meanEdge < 0.08f) {
        CGContextRelease(ctx);
        free(buf);
        if ([CDPreferences shared].debugLogging) NSLog(@"[CelosiaDepth] heuristic rejected; edge map is not a foreground mask");
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
        if ([CDPreferences shared].debugLogging) NSLog(@"[CelosiaDepth] foreground cache hit key=%@", cacheKey);
        return cached;
    }

    UIImage *result = nil;
    CDPreferences *prefs = [CDPreferences shared];
    NSString *source = @"none";
    if (prefs.preferBundledMasks && info.matchedMaskName.length) {
        UIImage *mask = [self loadBundledMaskNamed:info.matchedMaskName];
        if (mask) {
            result = [self applyMask:mask toImage:info.image size:targetSize];
            if (result) source = info.matchedMaskName;
        }
    }
    if (!result) {
        result = [self heuristicForegroundFromImage:info.image size:targetSize];
        if (result) source = @"heuristic-edge-map";
    }
    if (result) {
        [[CDCacheManager shared] storeForeground:result forKey:cacheKey];
        if (prefs.debugLogging) NSLog(@"[CelosiaDepth] foreground ready size=%.0fx%.0f via=%@",
            result.size.width, result.size.height, source);
    } else if (prefs.debugLogging) {
        NSLog(@"[CelosiaDepth] no foreground (mask=%@); no overlay is expected",
              info.matchedMaskName ?: @"(none)");
    }
    return result;
}

@end
