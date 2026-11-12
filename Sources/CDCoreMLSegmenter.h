#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CDCoreMLSegmenter : NSObject
+ (nullable UIImage *)foregroundImageFromImage:(UIImage *)image targetSize:(CGSize)targetSize;
@end

NS_ASSUME_NONNULL_END
