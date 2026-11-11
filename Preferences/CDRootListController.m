#import <Preferences/PSListController.h>
#import <UIKit/UIKit.h>

@interface CDPreviewController : UIViewController
@end

@interface CDRootListController : PSListController
@end

@implementation CDRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)openDepthPreview {
    CDPreviewController *preview = [[CDPreviewController alloc] init];
    [self.navigationController pushViewController:preview animated:YES];
}

@end
