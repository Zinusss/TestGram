#import <AppBundle/AppBundle.h>
#import <stdatomic.h>
#import <os/lock.h> // GHOST: icon packs (the table's lock)

// GHOST: icon packs — see GGAppBundleSetImageOverrides in AppBundle.h. While no pack is enabled a
// lookup is one atomic load of a flag. Otherwise a reader takes a strong reference to the current
// immutable table under an unfair lock (held for a retain only) and looks it up outside the lock;
// the writer swaps the table under the same lock. A replaced table is freed once its last reader is
// done — the old code kept every table it had ever published (up to ~400 images each) alive forever.
static atomic_bool ggHasImageOverrides = false;
static os_unfair_lock ggImageOverridesLock = OS_UNFAIR_LOCK_INIT;
static NSDictionary<NSString *, UIImage *> *ggImageOverrides = nil;

// GHOST: icon packs — swaps the published table, returns the replaced one.
static NSDictionary<NSString *, UIImage *> * _Nullable ggSwapImageOverrides(NSDictionary<NSString *, UIImage *> * _Nullable table) {
    os_unfair_lock_lock(&ggImageOverridesLock);
    NSDictionary *previous = ggImageOverrides;
    ggImageOverrides = table;
    atomic_store_explicit(&ggHasImageOverrides, table != nil, memory_order_release);
    os_unfair_lock_unlock(&ggImageOverridesLock);
    return previous;
}

void GGAppBundleSetImageOverrides(NSDictionary<NSString *, UIImage *> * _Nullable overrides) {
    NSDictionary *table = overrides.count != 0 ? [overrides copy] : nil;
    // GHOST: the replaced table is released here, outside the lock (or later, by the last reader holding it).
    (void)ggSwapImageOverrides(table);
}

// GHOST: icon packs — the current table, retained for the caller; nil while no pack is enabled.
static NSDictionary<NSString *, UIImage *> * _Nullable ggCurrentImageOverrides(void) {
    if (!atomic_load_explicit(&ggHasImageOverrides, memory_order_acquire)) {
        return nil;
    }
    NSDictionary *table = nil;
    os_unfair_lock_lock(&ggImageOverridesLock); // GHOST: held for a retain only
    table = ggImageOverrides;
    os_unfair_lock_unlock(&ggImageOverridesLock);
    return table;
}

NSBundle * _Nonnull getAppBundle() {
    static NSBundle *appBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle mainBundle];
        NSURL *bundleURL = [bundle.bundleURL URLByStandardizingPath];
        NSString *ext = [bundleURL pathExtension];
        if ([ext isEqualToString:@"appex"]) {
            bundle = [NSBundle bundleWithURL:[[bundleURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent]];
        } else if ([ext isEqualToString:@"framework"]) {
            bundle = [NSBundle bundleWithURL:[[bundleURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent]];
        } else if ([ext isEqualToString:@"Frameworks"]) {
            bundle = [NSBundle bundleWithURL:[bundleURL URLByDeletingLastPathComponent]];
        }
        
        // If the resolved bundle does not contain Assets.car, find the one that does
        if (bundle == nil || [bundle pathForResource:@"Assets" ofType:@"car"] == nil) {
            if ([[NSBundle mainBundle] pathForResource:@"Assets" ofType:@"car"] != nil) {
                bundle = [NSBundle mainBundle];
            } else {
                for (NSBundle *b in [NSBundle allBundles]) {
                    if ([b pathForResource:@"Assets" ofType:@"car"] != nil) {
                        bundle = b;
                        break;
                    }
                }
            }
        }
        if (bundle == nil) {
            bundle = [NSBundle mainBundle];
        }
        appBundle = bundle;
    });
    
    return appBundle;
}

@implementation UIImage (AppBundle)

- (instancetype _Nullable)initWithBundleImageName:(NSString * _Nonnull)bundleImageName {
    NSDictionary<NSString *, UIImage *> *overrides = ggCurrentImageOverrides(); // GHOST: icon packs
    if (overrides != nil) {
        UIImage *image = overrides[bundleImageName];
        if (image != nil) {
            return image;
        }
    }
    
    NSBundle *bundle = getAppBundle();
    UIImage *image = nil;
    if (bundle != nil) {
        image = [UIImage imageNamed:bundleImageName inBundle:bundle compatibleWithTraitCollection:nil];
    }
    if (image == nil && [NSBundle mainBundle] != bundle) {
        image = [UIImage imageNamed:bundleImageName inBundle:[NSBundle mainBundle] compatibleWithTraitCollection:nil];
    }
    if (image == nil) {
        image = [UIImage imageNamed:bundleImageName];
    }
    if (image == nil) {
        NSString *lastComponent = [bundleImageName lastPathComponent];
        if (![lastComponent isEqualToString:bundleImageName]) {
            if (bundle != nil) {
                image = [UIImage imageNamed:lastComponent inBundle:bundle compatibleWithTraitCollection:nil];
            }
            if (image == nil && [NSBundle mainBundle] != bundle) {
                image = [UIImage imageNamed:lastComponent inBundle:[NSBundle mainBundle] compatibleWithTraitCollection:nil];
            }
            if (image == nil) {
                image = [UIImage imageNamed:lastComponent];
            }
        }
    }
    if (image == nil && bundle != nil) {
        NSString *filePath = [bundle pathForResource:bundleImageName ofType:@"png"];
        if (filePath == nil) {
            filePath = [[NSBundle mainBundle] pathForResource:bundleImageName ofType:@"png"];
        }
        if (filePath != nil) {
            image = [UIImage imageWithContentsOfFile:filePath];
        }
    }
    
    if (image == nil) {
        // Return a safe 1x1 clear template image so forced unwraps (!) across Telegram never crash
        static UIImage *fallbackImage = nil;
        static dispatch_once_t fallbackOnce;
        dispatch_once(&fallbackOnce, ^{
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(1.0, 1.0), NO, 1.0);
            fallbackImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        });
        return fallbackImage;
    }
    
    return image;
}

@end
