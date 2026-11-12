#import "CDCoreMLSegmenter.h"
#import <CoreML/CoreML.h>
#import <Vision/Vision.h>

static NSString * const CDModelPath = @"/var/jb/Library/Application Support/CelosiaDepth/Models/DeepLabV3FP16.mlmodel";

@implementation CDCoreMLSegmenter

+ (VNCoreMLModel *)visionModel {
    static VNCoreMLModel *visionModel = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:CDModelPath]) {
            NSLog(@"[CelosiaDepth] Core ML model missing at %@", CDModelPath);
            return;
        }

        NSError *error = nil;
        NSURL *sourceURL = [NSURL fileURLWithPath:CDModelPath];
        NSURL *compiledURL = [MLModel compileModelAtURL:sourceURL error:&error];
        if (!compiledURL) {
            NSLog(@"[CelosiaDepth] Core ML compile failed: %@", error);
            return;
        }

        MLModelConfiguration *configuration = [[MLModelConfiguration alloc] init];
        configuration.computeUnits = MLComputeUnitsCPUAndGPU;
        MLModel *model = [MLModel modelWithContentsOfURL:compiledURL
                                           configuration:configuration
                                                   error:&error];
        if (!model) {
            NSLog(@"[CelosiaDepth] Core ML load failed: %@", error);
            return;
        }

        visionModel = [VNCoreMLModel modelForMLModel:model error:&error];
        if (!visionModel) {
            NSLog(@"[CelosiaDepth] Vision model wrapper failed: %@", error);
        }
    });
    return visionModel;
}

+ (BOOL)readLabelFromArray:(MLMultiArray *)array x:(NSUInteger)x y:(NSUInteger)y label:(int32_t *)label {
    NSArray<NSNumber *> *shape = array.shape;
    NSArray<NSNumber *> *strides = array.strides;
    if (shape.count < 2 || strides.count != shape.count) return NO;

    NSUInteger rank = shape.count;
    NSUInteger height = shape[rank - 2].unsignedIntegerValue;
    NSUInteger width = shape[rank - 1].unsignedIntegerValue;
    if (x >= width || y >= height) return NO;

    NSUInteger offset = y * strides[rank - 2].unsignedIntegerValue +
                        x * strides[rank - 1].unsignedIntegerValue;
    switch (array.dataType) {
        case MLMultiArrayDataTypeInt32:
            *label = ((int32_t *)array.dataPointer)[offset];
            return YES;
        case MLMultiArrayDataTypeFloat32:
            *label = (int32_t)lrintf(((float *)array.dataPointer)[offset]);
            return YES;
        case MLMultiArrayDataTypeDouble:
            *label = (int32_t)llround(((double *)array.dataPointer)[offset]);
            return YES;
        default:
            return NO;
    }
}

+ (UIImage *)alphaMaskFromLabels:(MLMultiArray *)labels {
    NSArray<NSNumber *> *shape = labels.shape;
    if (shape.count < 2) return nil;

    NSUInteger rank = shape.count;
    size_t height = shape[rank - 2].unsignedIntegerValue;
    size_t width = shape[rank - 1].unsignedIntegerValue;
    if (width < 2 || height < 2 || width > 2048 || height > 2048) return nil;

    size_t bytesPerRow = width * 4;
    uint8_t *pixels = calloc(height, bytesPerRow);
    if (!pixels) return nil;

    size_t foregroundPixels = 0;
    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            int32_t classID = 0;
            if (![self readLabelFromArray:labels x:x y:y label:&classID]) {
                free(pixels);
                return nil;
            }

            size_t offset = y * bytesPerRow + x * 4;
            pixels[offset] = 255;
            pixels[offset + 1] = 255;
            pixels[offset + 2] = 255;
            // DeepLabV3 uses class 0 for background; nonzero classes are foreground.
            pixels[offset + 3] = (classID > 0 && classID <= 20) ? 255 : 0;
            if (pixels[offset + 3]) foregroundPixels++;
        }
    }

    CGFloat coverage = (CGFloat)foregroundPixels / (CGFloat)(width * height);
    if (coverage < 0.003 || coverage > 0.80) {
        NSLog(@"[CelosiaDepth] segmentation rejected: coverage=%.4f", coverage);
        free(pixels);
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, bytesPerRow,
                                                  colorSpace,
                                                  kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        free(pixels);
        return nil;
    }

    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    free(pixels);
    if (!cgImage) return nil;

    UIImage *mask = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return mask;
}

+ (UIImage *)foregroundImageFromImage:(UIImage *)image targetSize:(CGSize)targetSize {
    if (!image.CGImage || targetSize.width < 1 || targetSize.height < 1) return nil;

    VNCoreMLModel *model = [self visionModel];
    if (!model) return nil;

    NSError *error = nil;
    VNCoreMLRequest *request = [[VNCoreMLRequest alloc] initWithModel:model];
    request.imageCropAndScaleOption = VNImageCropAndScaleOptionScaleFill;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage
                                                                            options:@{}];
    if (![handler performRequests:@[request] error:&error]) {
        NSLog(@"[CelosiaDepth] Vision segmentation failed: %@", error);
        return nil;
    }

    VNCoreMLFeatureValueObservation *observation = nil;
    for (id result in request.results) {
        if ([result isKindOfClass:[VNCoreMLFeatureValueObservation class]]) {
            observation = result;
            break;
        }
    }
    MLMultiArray *labels = observation.featureValue.multiArrayValue;
    if (!labels) {
        NSLog(@"[CelosiaDepth] segmentation output is not an MLMultiArray");
        return nil;
    }

    UIImage *mask = [self alphaMaskFromLabels:labels];
    if (!mask) return nil;

    UIGraphicsBeginImageContextWithOptions(targetSize, NO, 1.0);
    CGRect rect = CGRectMake(0, 0, targetSize.width, targetSize.height);
    [image drawInRect:rect];
    UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    UIGraphicsBeginImageContextWithOptions(targetSize, NO, 1.0);
    [mask drawInRect:rect];
    UIImage *scaledMask = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if (!scaledImage || !scaledMask) return nil;

    UIGraphicsBeginImageContextWithOptions(targetSize, NO, 1.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [scaledImage drawInRect:rect];
    CGContextSetBlendMode(context, kCGBlendModeDestinationIn);
    [scaledMask drawInRect:rect];
    UIImage *foreground = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return foreground;
}

@end
