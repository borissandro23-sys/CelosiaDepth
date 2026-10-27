#import "CDCacheManager.h"

@interface CDCacheManager ()
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *memoryCache;
@property (nonatomic, copy) NSString *diskRoot;
@end

@implementation CDCacheManager

+ (instancetype)shared {
    static CDCacheManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = 4; // A9 / 2GB: keep tiny
        _memoryCache.totalCostLimit = 8 * 1024 * 1024;
        _diskRoot = @"/var/jb/var/mobile/Library/Caches/com.celosiadepth.tweak";
        [[NSFileManager defaultManager] createDirectoryAtPath:_diskRoot
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    return self;
}

- (NSString *)diskPathForKey:(NSString *)key {
    NSString *safe = [[key dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    safe = [safe stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [_diskRoot stringByAppendingPathComponent:[safe stringByAppendingString:@".png"]];
}

- (UIImage *)cachedForegroundForKey:(NSString *)key {
    if (key.length == 0) return nil;
    UIImage *mem = [self.memoryCache objectForKey:key];
    if (mem) return mem;
    NSString *path = [self diskPathForKey:key];
    UIImage *disk = [UIImage imageWithContentsOfFile:path];
    if (disk) {
        [self.memoryCache setObject:disk forKey:key cost:(NSUInteger)(disk.size.width * disk.size.height * 4)];
    }
    return disk;
}

- (void)storeForeground:(UIImage *)image forKey:(NSString *)key {
    if (!image || key.length == 0) return;
    [self.memoryCache setObject:image forKey:key cost:(NSUInteger)(image.size.width * image.size.height * 4)];
    NSString *path = [self diskPathForKey:key];
    NSData *png = UIImagePNGRepresentation(image);
    [png writeToFile:path atomically:YES];
}

- (void)invalidateKey:(NSString *)key {
    if (key.length == 0) return;
    [self.memoryCache removeObjectForKey:key];
    [[NSFileManager defaultManager] removeItemAtPath:[self diskPathForKey:key] error:nil];
}

- (void)invalidateAll {
    [self.memoryCache removeAllObjects];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.diskRoot error:nil];
    for (NSString *f in files) {
        [[NSFileManager defaultManager] removeItemAtPath:[self.diskRoot stringByAppendingPathComponent:f] error:nil];
    }
}

@end
