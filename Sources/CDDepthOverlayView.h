#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CDDepthOverlayView : UIView

- (void)setForegroundImage:(nullable UIImage *)image intensity:(CGFloat)intensity;
- (void)clearContent;

@end

NS_ASSUME_NONNULL_END
