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
    if ([bundleImageName containsString:@"ReplyQuoteIcon"]) {
        return [UIImage systemImageNamed:@"quote.opening"];
    }
    if ([bundleImageName containsString:@"TextCodeIcon"]) {
        return [UIImage systemImageNamed:@"chevron.left.forwardslash.chevron.right"];
    }
    if ([bundleImageName containsString:@"Delete"] || [bundleImageName containsString:@"trash"]) {
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
    return nil;
}

static NSArray<NSBundle *> * _Nonnull ggGetCandidateBundles(void) {
    static NSArray<NSBundle *> *candidateBundles = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSBundle *> *bundles = [NSMutableArray array];
        NSBundle *appBundle = getAppBundle();
        if (appBundle != nil) {
            [bundles addObject:appBundle];
        }
        NSBundle *mainBundle = [NSBundle mainBundle];
        if (mainBundle != nil && ![bundles containsObject:mainBundle]) {
            [bundles addObject:mainBundle];
        }
        
        NSString *rootPath = appBundle.bundlePath ?: mainBundle.bundlePath;
        NSString *resolvedRoot = [rootPath stringByResolvingSymlinksInPath];
        if (resolvedRoot != nil) {
            for (NSBundle *b in [NSBundle allBundles]) {
                NSString *bp = [b.bundlePath stringByResolvingSymlinksInPath];
                if (bp != nil && ([bp hasPrefix:resolvedRoot] || [bp containsString:@".app/"]) && ![bundles containsObject:b]) {
                    [bundles addObject:b];
                }
            }
            for (NSBundle *b in [NSBundle allFrameworks]) {
                NSString *bp = [b.bundlePath stringByResolvingSymlinksInPath];
                if (bp != nil && ([bp hasPrefix:resolvedRoot] || [bp containsString:@".app/"]) && ![bundles containsObject:b]) {
                    [bundles addObject:b];
                }
            }
            NSURL *frameworksURL = [appBundle privateFrameworksURL] ?: [mainBundle privateFrameworksURL];
            if (frameworksURL != nil) {
                NSArray<NSURL *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:frameworksURL
                                                                            includingPropertiesForKeys:nil
                                                                                               options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                                 error:nil];
                for (NSURL *url in contents) {
                    if ([url.pathExtension isEqualToString:@"framework"] || [url.pathExtension isEqualToString:@"bundle"]) {
                        NSBundle *b = [NSBundle bundleWithURL:url];
                        if (b != nil && ![bundles containsObject:b]) {
                            [bundles addObject:b];
                        }
                    }
                }
            }
            NSURL *appURL = appBundle.bundleURL ?: mainBundle.bundleURL;
            if (appURL != nil) {
                NSArray<NSURL *> *appContents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:appURL
                                                                               includingPropertiesForKeys:nil
                                                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                                    error:nil];
                for (NSURL *url in appContents) {
                    if ([url.pathExtension isEqualToString:@"bundle"]) {
                        NSBundle *b = [NSBundle bundleWithURL:url];
                        if (b != nil && ![bundles containsObject:b]) {
                            [bundles addObject:b];
                        }
                    }
                }
            }
        }
        candidateBundles = [bundles copy];
    });
    return candidateBundles;
}

@implementation UIImage (AppBundle)

- (instancetype _Nullable)initWithBundleImageName:(NSString * _Nonnull)bundleImageName {
    if (bundleImageName.length == 0) {
        return nil;
    }
    
    NSDictionary<NSString *, UIImage *> *overrides = ggCurrentImageOverrides(); // GHOST: icon packs
    if (overrides != nil) {
        UIImage *image = overrides[bundleImageName];
        if (image != nil) {
            return image;
        }
    }
    
    NSCache<NSString *, id> *cache = ggGetLookupCache();
    id cached = [cache objectForKey:bundleImageName];
    if (cached != nil) {
        if (cached == (id)[NSNull null]) {
            return nil;
        }
        return (UIImage *)cached;
    }
    
    NSArray<NSBundle *> *candidates = ggGetCandidateBundles();
    UIImage *image = nil;
    
    // 1. Check full bundleImageName in all candidate bundles
    for (NSBundle *b in candidates) {
        image = [UIImage imageNamed:bundleImageName inBundle:b compatibleWithTraitCollection:nil];
        if (image != nil) {
            break;
        }
    }
    if (image == nil) {
        image = [UIImage imageNamed:bundleImageName];
    }
    
    // 2. Check lastPathComponent if bundleImageName contains '/'
    NSString *lastComponent = [bundleImageName lastPathComponent];
    BOOL hasSubdir = lastComponent != nil && ![lastComponent isEqualToString:bundleImageName];
    if (image == nil && hasSubdir) {
        for (NSBundle *b in candidates) {
            image = [UIImage imageNamed:lastComponent inBundle:b compatibleWithTraitCollection:nil];
            if (image != nil) {
                break;
            }
        }
        if (image == nil) {
            image = [UIImage imageNamed:lastComponent];
        }
    }
    
    // 3. Check loose files in candidate bundles (.png, .pdf)
    if (image == nil) {
        for (NSBundle *b in candidates) {
            NSString *filePath = [b pathForResource:bundleImageName ofType:@"png"];
            if (filePath == nil) {
                filePath = [b pathForResource:bundleImageName ofType:@"pdf"];
            }
            if (filePath == nil && hasSubdir) {
                filePath = [b pathForResource:lastComponent ofType:@"png"];
                if (filePath == nil) {
                    filePath = [b pathForResource:lastComponent ofType:@"pdf"];
                }
            }
            if (filePath != nil) {
                image = [UIImage imageWithContentsOfFile:filePath];
                if (image != nil) {
                    break;
                }
            }
        }
    }
    
    // 4. Fallback to all loaded frameworks if not found in candidate list
    if (image == nil) {
        for (NSBundle *b in [NSBundle allFrameworks]) {
            image = [UIImage imageNamed:bundleImageName inBundle:b compatibleWithTraitCollection:nil];
            if (image != nil) {
                break;
            }
            if (hasSubdir) {
                image = [UIImage imageNamed:lastComponent inBundle:b compatibleWithTraitCollection:nil];
                if (image != nil) {
                    break;
                }
            }
        }
    }
    
    // 5. Fallback to SF Symbol for known Telegram/Ghostgram icons
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
