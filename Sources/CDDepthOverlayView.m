#import "CDDepthOverlayView.h"

@interface CDDepthOverlayView ()
@property (nonatomic, strong) UIImageView *imageView;
@end

@implementation CDDepthOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.backgroundColor = UIColor.clearColor;
        [self addSubview:_imageView];
    }
    return self;
}

- (void)setForegroundImage:(UIImage *)image intensity:(CGFloat)intensity {
    self.imageView.image = image;
    self.imageView.alpha = MAX(0.0, MIN(1.0, intensity));
    self.hidden = (image == nil);
}

- (void)clearContent {
    self.imageView.image = nil;
    self.hidden = YES;
}

@end
