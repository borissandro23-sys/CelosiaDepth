#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CDPreferences : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly) CGFloat intensity;          // 0.0 – 1.0 overlay alpha scale
@property (nonatomic, readonly) BOOL preferBundledMasks;    // use Resources/Masks when matched
@property (nonatomic, readonly) BOOL debugLogging;

- (void)reload;
- (void)observeChanges;

@end

NS_ASSUME_NONNULL_END
