#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>

@interface CDPreviewController : UIViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

@implementation CDPreviewController {
    UIView *_preview;
    UIImageView *_wallpaperView;
    UIImageView *_foregroundView;
    UILabel *_clockLabel;
    UILabel *_statusLabel;
    UIActivityIndicatorView *_spinner;
    UIImage *_sourceImage;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Depth Preview";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIBarButtonItem *choose = [[UIBarButtonItem alloc] initWithTitle:@"Choose Photo"
        style:UIBarButtonItemStyleDone target:self action:@selector(choosePhoto)];
    self.navigationItem.rightBarButtonItem = choose;

    _preview = [[UIView alloc] init];
    _preview.translatesAutoresizingMaskIntoConstraints = NO;
    _preview.backgroundColor = UIColor.blackColor;
    _preview.layer.cornerRadius = 24;
    _preview.clipsToBounds = YES;
    [self.view addSubview:_preview];

    _wallpaperView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _wallpaperView.translatesAutoresizingMaskIntoConstraints = NO;
    _wallpaperView.contentMode = UIViewContentModeScaleAspectFill;
    [_preview addSubview:_wallpaperView];

    _foregroundView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _foregroundView.translatesAutoresizingMaskIntoConstraints = NO;
    _foregroundView.contentMode = UIViewContentModeScaleAspectFit;
    _foregroundView.userInteractionEnabled = YES;
    [_preview addSubview:_foregroundView];

    _clockLabel = [[UILabel alloc] init];
    _clockLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _clockLabel.text = @"9:41";
    _clockLabel.textColor = UIColor.whiteColor;
    _clockLabel.font = [UIFont systemFontOfSize:58 weight:UIFontWeightLight];
    _clockLabel.textAlignment = NSTextAlignmentCenter;
    _clockLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.45];
    _clockLabel.shadowOffset = CGSizeMake(0, 1);
    _clockLabel.userInteractionEnabled = YES;
    [_preview addSubview:_clockLabel];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.text = @"Choose a photo to analyze";
    _statusLabel.textColor = UIColor.secondaryLabelColor;
    _statusLabel.font = [UIFont systemFontOfSize:14];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 0;
    [self.view addSubview:_statusLabel];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_preview addSubview:_spinner];

    [NSLayoutConstraint activateConstraints:@[
        [_preview.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_preview.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-25],
        [_preview.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.78],
        [_preview.heightAnchor constraintEqualToAnchor:_preview.widthAnchor multiplier:1.78],
        [_wallpaperView.leadingAnchor constraintEqualToAnchor:_preview.leadingAnchor],
        [_wallpaperView.trailingAnchor constraintEqualToAnchor:_preview.trailingAnchor],
        [_wallpaperView.topAnchor constraintEqualToAnchor:_preview.topAnchor],
        [_wallpaperView.bottomAnchor constraintEqualToAnchor:_preview.bottomAnchor],
        [_foregroundView.leadingAnchor constraintEqualToAnchor:_preview.leadingAnchor],
        [_foregroundView.trailingAnchor constraintEqualToAnchor:_preview.trailingAnchor],
        [_foregroundView.topAnchor constraintEqualToAnchor:_preview.topAnchor],
        [_foregroundView.bottomAnchor constraintEqualToAnchor:_preview.bottomAnchor],
        [_clockLabel.topAnchor constraintEqualToAnchor:_preview.topAnchor constant:85],
        [_clockLabel.centerXAnchor constraintEqualToAnchor:_preview.centerXAnchor],
        [_clockLabel.widthAnchor constraintEqualToAnchor:_preview.widthAnchor multiplier:0.9],
        [_statusLabel.topAnchor constraintEqualToAnchor:_preview.bottomAnchor constant:18],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [_spinner.centerXAnchor constraintEqualToAnchor:_preview.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:_preview.centerYAnchor]
    ]];

    UIPanGestureRecognizer *moveClock = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveClock:)];
    [_clockLabel addGestureRecognizer:moveClock];
    UIPanGestureRecognizer *moveSubject = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveSubject:)];
    [_foregroundView addGestureRecognizer:moveSubject];
}

- (void)choosePhoto {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        _statusLabel.text = @"Photo Library is unavailable on this device.";
        return;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (image) [self analyzeImage:image];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (UIImage *)personForegroundFromImage:(UIImage *)image error:(NSError **)error {
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return nil;

    VNGeneratePersonSegmentationRequest *request = [[VNGeneratePersonSegmentationRequest alloc] init];
    request.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelAccurate;
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8;
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage
        orientation:(CGImagePropertyOrientation)image.imageOrientation options:@{}];
    if (![handler performRequests:@[request] error:error]) return nil;

    CVPixelBufferRef maskBuffer = request.results.firstObject.pixelBuffer;
    if (!maskBuffer) return nil;

    CIImage *input = [CIImage imageWithCGImage:cgImage];
    CIImage *mask = [CIImage imageWithCVPixelBuffer:maskBuffer];
    CGFloat sx = input.extent.size.width / mask.extent.size.width;
    CGFloat sy = input.extent.size.height / mask.extent.size.height;
    mask = [mask imageByApplyingTransform:CGAffineTransformMakeScale(sx, sy)];
    CIImage *clear = [CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0 alpha:0]];
    clear = [clear imageByCroppingToRect:input.extent];

    CIFilter *blend = [CIFilter filterWithName:@"CIBlendWithMask"];
    [blend setValue:input forKey:kCIInputImageKey];
    [blend setValue:clear forKey:kCIInputBackgroundImageKey];
    [blend setValue:mask forKey:kCIInputMaskImageKey];
    CIImage *output = blend.outputImage;
    if (!output) return nil;

    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef result = [context createCGImage:output fromRect:input.extent];
    if (!result) return nil;
    UIImage *foreground = [UIImage imageWithCGImage:result scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(result);
    return foreground;
}

- (void)analyzeImage:(UIImage *)image {
    _sourceImage = image;
    _wallpaperView.image = image;
    _foregroundView.image = nil;
    _foregroundView.transform = CGAffineTransformIdentity;
    _clockLabel.transform = CGAffineTransformIdentity;
    _statusLabel.text = @"Analyzing Image…";
    [_spinner startAnimating];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        UIImage *foreground = [self personForegroundFromImage:image error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_spinner stopAnimating];
            if (foreground) {
                self->_foregroundView.image = foreground;
                self->_statusLabel.text = @"Person detected. Drag the person and clock to preview the overlap.";
            } else {
                self->_statusLabel.text = error ? @"Analysis failed. Try another photo." :
                    @"No person was detected. On iOS 15 this preview currently segments people, not arbitrary objects.";
            }
        });
    });
}

- (void)moveClock:(UIPanGestureRecognizer *)gesture {
    CGPoint delta = [gesture translationInView:_preview];
    _clockLabel.transform = CGAffineTransformTranslate(_clockLabel.transform, delta.x, delta.y);
    [gesture setTranslation:CGPointZero inView:_preview];
}

- (void)moveSubject:(UIPanGestureRecognizer *)gesture {
    CGPoint delta = [gesture translationInView:_preview];
    _foregroundView.transform = CGAffineTransformTranslate(_foregroundView.transform, delta.x, delta.y);
    [gesture setTranslation:CGPointZero inView:_preview];
}

@end
