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

static NSCache<NSString *, id> * _Nonnull ggGetLookupCache(void) {
    static NSCache<NSString *, id> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 1500;
    });
    return cache;
}

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
    [ggGetLookupCache() removeAllObjects];
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
        NSString *ext = [bundle.bundleURL pathExtension];
        if ([ext isEqualToString:@"appex"]) {
            bundle = [NSBundle bundleWithURL:[[bundle.bundleURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent]];
        } else if ([ext isEqualToString:@"framework"]) {
            bundle = [NSBundle bundleWithURL:[[bundle.bundleURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent]];
        } else if ([ext isEqualToString:@"Frameworks"]) {
            bundle = [NSBundle bundleWithURL:[bundle.bundleURL URLByDeletingLastPathComponent]];
        }
        if (bundle == nil) {
            bundle = [NSBundle mainBundle];
        }
        appBundle = bundle;
    });
    
    return appBundle;
}

static UIImage * _Nullable ggFallbackSystemImage(NSString * _Nonnull bundleImageName) {
    if ([bundleImageName containsString:@"AddMember"] || [bundleImageName containsString:@"addcontact"] || [bundleImageName containsString:@"NewContact"] || [bundleImageName containsString:@"AddPerson"]) {
        return [UIImage systemImageNamed:@"person.badge.plus"];
    }
    if ([bundleImageName containsString:@"InviteActionIcon"] || [bundleImageName containsString:@"Invite"]) {
        return [UIImage systemImageNamed:@"square.and.arrow.up"];
    }
    if ([bundleImageName containsString:@"CreateGroup"]) {
        return [UIImage systemImageNamed:@"person.2"];
    }
    if ([bundleImageName containsString:@"CreateChannel"]) {
        return [UIImage systemImageNamed:@"megaphone"];
    }
    if ([bundleImageName containsString:@"LinkActionIcon"] || [bundleImageName containsString:@"linkIcon"] || [bundleImageName containsString:@"ShareLink"]) {
        return [UIImage systemImageNamed:@"link"];
    }
    if ([bundleImageName containsString:@"AddBirthday"]) {
        return [UIImage systemImageNamed:@"gift"];
    }
    if ([bundleImageName containsString:@"SubtitleArrow"] || [bundleImageName containsString:@"InlineTextRightArrow"] || [bundleImageName containsString:@"TextArrowRight"]) {
        return [UIImage systemImageNamed:@"chevron.right"];
    }
    if ([bundleImageName containsString:@"ToastImprovingVideo"]) {
        return [UIImage systemImageNamed:@"video"];
    }
    if ([bundleImageName containsString:@"Translate"]) {
        return [UIImage systemImageNamed:@"character.book.closed"];
    }
    if ([bundleImageName containsString:@"Lock"]) {
        return [UIImage systemImageNamed:@"lock"];
    }
    if ([bundleImageName containsString:@"CameraGalleryIcon"]) {
        return [UIImage systemImageNamed:@"photo"];
    }
    if ([bundleImageName containsString:@"CameraFlashIcon"]) {
        return [UIImage systemImageNamed:@"bolt"];
    }
    if ([bundleImageName containsString:@"ReplyQuoteIcon"] || [bundleImageName containsString:@"Quote"]) {
        return [UIImage systemImageNamed:@"quote.opening"];
    }
    if ([bundleImageName containsString:@"TextCodeIcon"] || [bundleImageName containsString:@"Code"]) {
        return [UIImage systemImageNamed:@"chevron.left.forwardslash.chevron.right"];
    }
    if ([bundleImageName containsString:@"Delete"] || [bundleImageName containsString:@"trash"] || [bundleImageName containsString:@"RemoveItem"]) {
        return [UIImage systemImageNamed:@"trash"];
    }
    if ([bundleImageName containsString:@"Time"] || [bundleImageName containsString:@"Timer"]) {
        return [UIImage systemImageNamed:@"clock"];
    }
    if ([bundleImageName containsString:@"Ban"]) {
        return [UIImage systemImageNamed:@"nosign"];
    }
    if ([bundleImageName containsString:@"Tag"]) {
        return [UIImage systemImageNamed:@"tag"];
    }
    if ([bundleImageName containsString:@"ReadingList"]) {
        return [UIImage systemImageNamed:@"bookmark"];
    }
    if ([bundleImageName containsString:@"AddItem"] || [bundleImageName containsString:@"AddIcon"]) {
        return [UIImage systemImageNamed:@"plus"];
    }
    if ([bundleImageName containsString:@"PremiumIcon"]) {
        return [UIImage systemImageNamed:@"star.fill"];
    }
    if ([bundleImageName containsString:@"QrIcon"]) {
        return [UIImage systemImageNamed:@"qrcode"];
    }
    if ([bundleImageName containsString:@"NavigationMore"]) {
        return [UIImage systemImageNamed:@"ellipsis"];
    }
    if ([bundleImageName containsString:@"Back"]) {
        return [UIImage systemImageNamed:@"chevron.backward"];
    }
    if ([bundleImageName containsString:@"Close"]) {
        return [UIImage systemImageNamed:@"xmark"];
    }
    if ([bundleImageName containsString:@"Done"]) {
        return [UIImage systemImageNamed:@"checkmark"];
    }
    if ([bundleImageName containsString:@"Undo"]) {
        return [UIImage systemImageNamed:@"arrow.uturn.backward"];
    }
    if ([bundleImageName containsString:@"Fill"]) {
        return [UIImage systemImageNamed:@"paintbrush"];
    }
    if ([bundleImageName containsString:@"Stroke"]) {
        return [UIImage systemImageNamed:@"pencil.tip"];
    }
    return nil;
}

@implementation UIImage (AppBundle)

- (instancetype _Nullable)initWithBundleImageName:(NSString * _Nonnull)bundleImageName {
    if (bundleImageName.length == 0) {
        return nil;
    }
    
    // GHOST: icon packs
    NSDictionary<NSString *, UIImage *> *overrides = ggCurrentImageOverrides();
    if (overrides != nil) {
        UIImage *image = overrides[bundleImageName];
        if (image != nil) {
            return image;
        }
    }
    
    // Fast O(1) in-memory cache lookup
    NSCache<NSString *, id> *cache = ggGetLookupCache();
    id cached = [cache objectForKey:bundleImageName];
    if (cached != nil) {
        if (cached == (id)[NSNull null]) {
            return nil;
        }
        return (UIImage *)cached;
    }
    
    NSBundle *appBundle = getAppBundle();
    NSBundle *mainBundle = [NSBundle mainBundle];
    UIImage *image = nil;
    
    // 1. Direct lookup in getAppBundle() (where Assets.car resides)
    if (appBundle != nil) {
        image = [UIImage imageNamed:bundleImageName inBundle:appBundle compatibleWithTraitCollection:nil];
    }
    
    // 2. Lookup in [NSBundle mainBundle] if distinct
    if (image == nil && mainBundle != nil && mainBundle != appBundle) {
        image = [UIImage imageNamed:bundleImageName inBundle:mainBundle compatibleWithTraitCollection:nil];
    }
    
    // 3. Fallback to imageNamed: directly
    if (image == nil) {
        image = [UIImage imageNamed:bundleImageName];
    }
    
    // 4. Try lastPathComponent if bundleImageName contains directories (e.g. "Contact List/AddMemberIcon")
    NSString *lastComponent = [bundleImageName lastPathComponent];
    if (image == nil && lastComponent.length > 0 && ![lastComponent isEqualToString:bundleImageName]) {
        if (appBundle != nil) {
            image = [UIImage imageNamed:lastComponent inBundle:appBundle compatibleWithTraitCollection:nil];
        }
        if (image == nil && mainBundle != nil && mainBundle != appBundle) {
            image = [UIImage imageNamed:lastComponent inBundle:mainBundle compatibleWithTraitCollection:nil];
        }
        if (image == nil) {
            image = [UIImage imageNamed:lastComponent];
        }
    }
    
    // 5. Try ChatController / TelegramUI framework bundle if dynamically linked
    if (image == nil) {
        static NSBundle *telegramUIBundle = nil;
        static dispatch_once_t tOnce;
        dispatch_once(&tOnce, ^{
            Class cls = NSClassFromString(@"ChatController") ?: NSClassFromString(@"TelegramUI_ChatController");
            if (cls != nil) {
                telegramUIBundle = [NSBundle bundleForClass:cls];
            }
        });
        if (telegramUIBundle != nil && telegramUIBundle != appBundle && telegramUIBundle != mainBundle) {
            image = [UIImage imageNamed:bundleImageName inBundle:telegramUIBundle compatibleWithTraitCollection:nil];
            if (image == nil && lastComponent.length > 0 && ![lastComponent isEqualToString:bundleImageName]) {
                image = [UIImage imageNamed:lastComponent inBundle:telegramUIBundle compatibleWithTraitCollection:nil];
            }
        }
    }
    
    // 6. Fast SF Symbol fallback for standard Telegram icons
    if (image == nil) {
        image = ggFallbackSystemImage(bundleImageName);
    }
    
    if (image != nil) {
        [cache setObject:image forKey:bundleImageName];
    } else {
        [cache setObject:(id)[NSNull null] forKey:bundleImageName];
    }
    
    return image;
}

@end
