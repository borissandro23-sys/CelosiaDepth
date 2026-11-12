/*
 * CelosiaDepth — diagnostic probe for Photos' "Use as Wallpaper" activity.
 * This intentionally records runtime types first; private Photos activity
 * payloads differ between iOS releases, so image extraction must be based
 * on what iOS 15.8.x actually supplies.
 */
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL CDIsWallpaperActivity(UIActivity *activity) {
    NSString *name = NSStringFromClass(activity.class);
    NSString *type = activity.activityType ?: @"";
    return [name localizedCaseInsensitiveContainsString:@"wallpaper"] ||
           [type localizedCaseInsensitiveContainsString:@"wallpaper"];
}

%hook UIActivity

- (void)prepareWithActivityItems:(NSArray *)activityItems {
    if (CDIsWallpaperActivity(self)) {
        NSLog(@"[CelosiaDepth][ShareProbe] prepare activity=%@ type=%@ count=%lu",
              NSStringFromClass(self.class), self.activityType ?: @"(nil)",
              (unsigned long)activityItems.count);
        [activityItems enumerateObjectsUsingBlock:^(id item, NSUInteger idx, BOOL *stop) {
            (void)stop;
            NSLog(@"[CelosiaDepth][ShareProbe] item[%lu]=%@",
                  (unsigned long)idx,
                  item ? NSStringFromClass([item class]) : @"(nil)");
            if ([item isKindOfClass:[UIImage class]]) {
                UIImage *image = (UIImage *)item;
                NSLog(@"[CelosiaDepth][ShareProbe] image[%lu] size=%.0fx%.0f scale=%.2f",
                      (unsigned long)idx, image.size.width, image.size.height, image.scale);
            }
            if ([item isKindOfClass:[NSURL class]]) {
                NSLog(@"[CelosiaDepth][ShareProbe] url[%lu]=%@",
                      (unsigned long)idx, [(NSURL *)item isFileURL] ? @"file-url" : @"non-file-url");
            }
        }];
    }
    %orig;
}

- (UIViewController *)activityViewController {
    if (CDIsWallpaperActivity(self)) {
        NSLog(@"[CelosiaDepth][ShareProbe] activityViewController activity=%@",
              NSStringFromClass(self.class));
    }
    return %orig;
}

- (void)performActivity {
    if (CDIsWallpaperActivity(self)) {
        NSLog(@"[CelosiaDepth][ShareProbe] performActivity activity=%@",
              NSStringFromClass(self.class));
    }
    %orig;
}

%end
