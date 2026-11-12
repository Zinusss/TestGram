#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include "fishhook.h"
#include "SideloadFix.h"

// ============================================================================
// 1. App Group Directory Redirection
// Always redirects to stable Documents/AppGroup under free Apple ID sideloading,
// avoiding ephemeral /tmp paths from Sideloadly's spoofer or launch failures.
// ============================================================================

@implementation NSFileManager (SideloadFix)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method orig = class_getInstanceMethod(self, @selector(containerURLForSecurityApplicationGroupIdentifier:));
        Method swiz = class_getInstanceMethod(self, @selector(fixed_containerURLForSecurityApplicationGroupIdentifier:));
        if (orig && swiz) {
            method_exchangeImplementations(orig, swiz);
            NSLog(@"[SideloadFix] Successfully hooked containerURLForSecurityApplicationGroupIdentifier:");
        }
    });
}

- (NSURL *)fixed_containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    NSURL *origURL = [self fixed_containerURLForSecurityApplicationGroupIdentifier:groupIdentifier];
    if (origURL != nil && [origURL.path containsString:@"Shared/AppGroup"]) {
        return origURL;
    }
    
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
// 2. Keychain Access Group & Entitlement Bypass
// Prevents errSecMissingEntitlement (-34018) crash when saving login/email/session keys
// ============================================================================

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result) = NULL;
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result) = NULL;
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) = NULL;
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef query) = NULL;

static CFDictionaryRef cleanKeychainDictionary(CFDictionaryRef dict, BOOL stripAccessible) {
    if (!dict) return NULL;
    NSMutableDictionary *mutable = [(__bridge NSDictionary *)dict mutableCopy];
    [mutable removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
    [mutable removeObjectForKey:(__bridge id)kSecAttrAccessControl];
    [mutable removeObjectForKey:(__bridge id)kSecAttrSynchronizable];
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wunguarded-availability"
    if (&kSecUseDataProtectionKeychain != NULL) {
        [mutable removeObjectForKey:(__bridge id)kSecUseDataProtectionKeychain];
    }
    #pragma clang diagnostic pop
    if (stripAccessible) {
        [mutable removeObjectForKey:(__bridge id)kSecAttrAccessible];
    }
    return CFBridgingRetain(mutable);
}

OSStatus fixed_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    CFDictionaryRef clean = cleanKeychainDictionary(attributes, NO);
    CFDictionaryRef toUse = clean ? clean : attributes;
    OSStatus (*func)(CFDictionaryRef, CFTypeRef *) = orig_SecItemAdd ? orig_SecItemAdd : (OSStatus (*)(CFDictionaryRef, CFTypeRef *))dlsym(RTLD_DEFAULT, "SecItemAdd");
    OSStatus status = func(toUse, result);
    if (status == errSecMissingEntitlement || status == -34018 || status == errSecParam) {
        CFDictionaryRef fallback = cleanKeychainDictionary(attributes, YES);
        status = func(fallback ? fallback : toUse, result);
        if (fallback) CFRelease(fallback);
    }
    if (clean) CFRelease(clean);
    return status;
}

OSStatus fixed_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    CFDictionaryRef clean = cleanKeychainDictionary(query, NO);
    CFDictionaryRef toUse = clean ? clean : query;
    OSStatus (*func)(CFDictionaryRef, CFTypeRef *) = orig_SecItemCopyMatching ? orig_SecItemCopyMatching : (OSStatus (*)(CFDictionaryRef, CFTypeRef *))dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
    OSStatus status = func(toUse, result);
    if (status == errSecMissingEntitlement || status == -34018 || status == errSecParam) {
        CFDictionaryRef fallback = cleanKeychainDictionary(query, YES);
        status = func(fallback ? fallback : toUse, result);
        if (fallback) CFRelease(fallback);
    }
    if (clean) CFRelease(clean);
    return status;
}

OSStatus fixed_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    CFDictionaryRef cleanQuery = cleanKeychainDictionary(query, NO);
    CFDictionaryRef cleanAttrs = cleanKeychainDictionary(attributesToUpdate, NO);
    CFDictionaryRef queryToUse = cleanQuery ? cleanQuery : query;
    CFDictionaryRef attrsToUse = cleanAttrs ? cleanAttrs : attributesToUpdate;
    OSStatus (*func)(CFDictionaryRef, CFDictionaryRef) = orig_SecItemUpdate ? orig_SecItemUpdate : (OSStatus (*)(CFDictionaryRef, CFDictionaryRef))dlsym(RTLD_DEFAULT, "SecItemUpdate");
    OSStatus status = func(queryToUse, attrsToUse);
    if (status == errSecMissingEntitlement || status == -34018 || status == errSecParam) {
        CFDictionaryRef fallbackQuery = cleanKeychainDictionary(query, YES);
        CFDictionaryRef fallbackAttrs = cleanKeychainDictionary(attributesToUpdate, YES);
        status = func(fallbackQuery ? fallbackQuery : queryToUse, fallbackAttrs ? fallbackAttrs : attrsToUse);
        if (fallbackQuery) CFRelease(fallbackQuery);
        if (fallbackAttrs) CFRelease(fallbackAttrs);
    }
    if (cleanQuery) CFRelease(cleanQuery);
    if (cleanAttrs) CFRelease(cleanAttrs);
    return status;
}

OSStatus fixed_SecItemDelete(CFDictionaryRef query) {
    CFDictionaryRef clean = cleanKeychainDictionary(query, NO);
    CFDictionaryRef toUse = clean ? clean : query;
    OSStatus (*func)(CFDictionaryRef) = orig_SecItemDelete ? orig_SecItemDelete : (OSStatus (*)(CFDictionaryRef))dlsym(RTLD_DEFAULT, "SecItemDelete");
    OSStatus status = func(toUse);
    if (status == errSecMissingEntitlement || status == -34018 || status == errSecParam) {
        CFDictionaryRef fallback = cleanKeychainDictionary(query, YES);
        status = func(fallback ? fallback : toUse);
        if (fallback) CFRelease(fallback);
    }
    if (clean) CFRelease(clean);
    return status;
}

// Interpose table in case DYLD_INSERT_LIBRARIES / dynamic linker is active
__attribute__((used)) static struct { const void *replacement; const void *replacee; } _interpose[]
__attribute__((section("__DATA,__interpose"))) = {
    { (const void *)fixed_SecItemAdd, (const void *)SecItemAdd },
    { (const void *)fixed_SecItemCopyMatching, (const void *)SecItemCopyMatching },
    { (const void *)fixed_SecItemUpdate, (const void *)SecItemUpdate },
    { (const void *)fixed_SecItemDelete, (const void *)SecItemDelete }
};

// ----------------------------------------------------------------------------
// 3. Fishhook Dynamic Rebinding
// ----------------------------------------------------------------------------
void SideloadFixInitialize(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[SideloadFix] Initializing Sideload Fixes via fishhook...");
        
        orig_SecItemAdd = (OSStatus (*)(CFDictionaryRef, CFTypeRef *))dlsym(RTLD_DEFAULT, "SecItemAdd");
        orig_SecItemCopyMatching = (OSStatus (*)(CFDictionaryRef, CFTypeRef *))dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
        orig_SecItemUpdate = (OSStatus (*)(CFDictionaryRef, CFDictionaryRef))dlsym(RTLD_DEFAULT, "SecItemUpdate");
        orig_SecItemDelete = (OSStatus (*)(CFDictionaryRef))dlsym(RTLD_DEFAULT, "SecItemDelete");
        
        struct rebinding rebindings[] = {
            { "SecItemAdd", (void *)fixed_SecItemAdd, (void **)&orig_SecItemAdd },
            { "SecItemCopyMatching", (void *)fixed_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching },
            { "SecItemUpdate", (void *)fixed_SecItemUpdate, (void **)&orig_SecItemUpdate },
            { "SecItemDelete", (void *)fixed_SecItemDelete, (void **)&orig_SecItemDelete }
        };
        rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
        NSLog(@"[SideloadFix] SecItem* symbols rebound successfully.");
    });
}

__attribute__((constructor))
static void init_sideload_fix(void) {
    SideloadFixInitialize();
}

#pragma clang diagnostic pop
