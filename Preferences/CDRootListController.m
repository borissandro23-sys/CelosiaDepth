#import <Preferences/PSListController.h>

@interface CDRootListController : PSListController
@end

@implementation CDRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

@end
