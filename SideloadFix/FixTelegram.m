#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#include "fishhook.h"

// ============================================================================
// 1. App Group Directory Redirection
// Prevents black screen / crash on launch when running without App Group entitlement
// ============================================================================

@implementation NSFileManager (SideloadFix)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method orig = class_getInstanceMethod(self, @selector(containerURLForSecurityApplicationGroupIdentifier:));
        Method swiz = class_getInstanceMethod(self, @selector(fixed_containerURLForSecurityApplicationGroupIdentifier:));
        if (orig && swiz) {
            method_exchangeImplementations(orig, swiz);
            NSLog(@"[FixTelegram] Successfully hooked containerURLForSecurityApplicationGroupIdentifier:");
        }
    });
}

- (NSURL *)fixed_containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docsDir = [paths firstObject];
    NSString *groupPath = [docsDir stringByAppendingPathComponent:@"AppGroup"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:groupPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:groupPath 
                                  withIntermediateDirectories:YES 
                                                   attributes:nil 
                                                        error:nil];
    }
    return [NSURL fileURLWithPath:groupPath];
}

@end

// ============================================================================
// 2. Keychain Access Group Removal
// Prevents errSecMissingEntitlement crash when saving SMS code / 2FA session keys
// ============================================================================

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result) = NULL;
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result) = NULL;
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) = NULL;
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef query) = NULL;

static CFDictionaryRef stripAccessGroup(CFDictionaryRef query) {
    if (!query) return NULL;
    if (!CFDictionaryContainsKey(query, kSecAttrAccessGroup)) {
        return NULL;
    }
    NSMutableDictionary *dict = [(__bridge NSDictionary *)query mutableCopy];
    [dict removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
    return CFBridgingRetain(dict);
}

OSStatus fixed_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    CFDictionaryRef clean = stripAccessGroup(attributes);
    CFDictionaryRef toUse = clean ? clean : attributes;
    OSStatus status = orig_SecItemAdd ? orig_SecItemAdd(toUse, result) : SecItemAdd(toUse, result);
    if (clean) CFRelease(clean);
    return status;
}

OSStatus fixed_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    CFDictionaryRef clean = stripAccessGroup(query);
    CFDictionaryRef toUse = clean ? clean : query;
    OSStatus status = orig_SecItemCopyMatching ? orig_SecItemCopyMatching(toUse, result) : SecItemCopyMatching(toUse, result);
    if (clean) CFRelease(clean);
    return status;
}

OSStatus fixed_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    CFDictionaryRef cleanQuery = stripAccessGroup(query);
    CFDictionaryRef cleanAttrs = stripAccessGroup(attributesToUpdate);
    CFDictionaryRef queryToUse = cleanQuery ? cleanQuery : query;
    CFDictionaryRef attrsToUse = cleanAttrs ? cleanAttrs : attributesToUpdate;
    OSStatus status = orig_SecItemUpdate ? orig_SecItemUpdate(queryToUse, attrsToUse) : SecItemUpdate(queryToUse, attrsToUse);
    if (cleanQuery) CFRelease(cleanQuery);
    if (cleanAttrs) CFRelease(cleanAttrs);
    return status;
}

OSStatus fixed_SecItemDelete(CFDictionaryRef query) {
    CFDictionaryRef clean = stripAccessGroup(query);
    CFDictionaryRef toUse = clean ? clean : query;
    OSStatus status = orig_SecItemDelete ? orig_SecItemDelete(toUse) : SecItemDelete(toUse);
    if (clean) CFRelease(clean);
    return status;
}

// ----------------------------------------------------------------------------
// 3. System Table Interposition (dyld __DATA,__interpose for DYLD_INSERT_LIBRARIES)
// ----------------------------------------------------------------------------
__attribute__((used)) static struct { const void *replacement; const void *replacee; } _interpose[]
__attribute__((section("__DATA,__interpose"))) = {
    { (const void *)fixed_SecItemAdd, (const void *)SecItemAdd },
    { (const void *)fixed_SecItemCopyMatching, (const void *)SecItemCopyMatching },
    { (const void *)fixed_SecItemUpdate, (const void *)SecItemUpdate },
    { (const void *)fixed_SecItemDelete, (const void *)SecItemDelete }
};

// ----------------------------------------------------------------------------
// 4. Fishhook Dynamic Rebinding (for sideloaded non-jailbroken iOS via LC_LOAD_DYLIB)
// ----------------------------------------------------------------------------
__attribute__((constructor))
static void init_sideload_fix(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[FixTelegram] Initializing Sideload Fixes...");
        
        struct rebinding rebindings[] = {
            { "SecItemAdd", (void *)fixed_SecItemAdd, (void **)&orig_SecItemAdd },
            { "SecItemCopyMatching", (void *)fixed_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching },
            { "SecItemUpdate", (void *)fixed_SecItemUpdate, (void **)&orig_SecItemUpdate },
            { "SecItemDelete", (void *)fixed_SecItemDelete, (void **)&orig_SecItemDelete }
        };
        rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
        NSLog(@"[FixTelegram] SecItem* symbols rebound via fishhook successfully.");
    });
}
