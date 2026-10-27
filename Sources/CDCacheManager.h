#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CDCacheManager : NSObject

+ (instancetype)shared;

/// Cache key typically derived from wallpaper identity (path hash / asset id).
- (nullable UIImage *)cachedForegroundForKey:(NSString *)key;
- (void)storeForeground:(UIImage *)image forKey:(NSString *)key;
- (void)invalidateKey:(NSString *)key;
- (void)invalidateAll;

@end

NS_ASSUME_NONNULL_END
