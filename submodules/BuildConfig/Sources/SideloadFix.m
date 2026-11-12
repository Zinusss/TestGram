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
            NSLog(@"[SideloadFix] Successfully hooked containerURLForSecurityApplicationGroupIdentifier:");
        }
    });
}

- (NSURL *)fixed_containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    NSURL *origURL = [self fixed_containerURLForSecurityApplicationGroupIdentifier:groupIdentifier];
    if (origURL != nil) {
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
    OSStatus (*func)(CFDictionaryRef, CFTypeRef *) = orig_SecItemAdd ? orig_SecItemAdd : (OSStatus (*)(CFDictionaryRef, CFTypeRef *))dlsym(RTLD_DEFAULT, "SecItemAdd");
    OSStatus status = func(toUse, result);
    if ((status == errSecMissingEntitlement || status == -34018) && !clean) {
        NSMutableDictionary *fallback = [(__bridge NSDictionary *)attributes mutableCopy];
        [fallback removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        [fallback removeObjectForKey:(__bridge id)kSecAttrAccessControl];
        status = func((__bridge CFDictionaryRef)fallback, result);
    }
    if (clean) CFRelease(clean);
    return status;
}

OSStatus fixed_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    CFDictionaryRef clean = stripAccessGroup(query);
    CFDictionaryRef toUse = clean ? clean : query;
    OSStatus (*func)(CFDictionaryRef, CFTypeRef *) = orig_SecItemCopyMatching ? orig_SecItemCopyMatching : (OSStatus (*)(CFDictionaryRef, CFTypeRef *))dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
    OSStatus status = func(toUse, result);
    if ((status == errSecMissingEntitlement || status == -34018) && !clean) {
        NSMutableDictionary *fallback = [(__bridge NSDictionary *)query mutableCopy];
        [fallback removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        [fallback removeObjectForKey:(__bridge id)kSecAttrAccessControl];
        status = func((__bridge CFDictionaryRef)fallback, result);
    }
    if (clean) CFRelease(clean);
    return status;
}

OSStatus fixed_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    CFDictionaryRef cleanQuery = stripAccessGroup(query);
    CFDictionaryRef cleanAttrs = stripAccessGroup(attributesToUpdate);
    CFDictionaryRef queryToUse = cleanQuery ? cleanQuery : query;
    CFDictionaryRef attrsToUse = cleanAttrs ? cleanAttrs : attributesToUpdate;
    OSStatus (*func)(CFDictionaryRef, CFDictionaryRef) = orig_SecItemUpdate ? orig_SecItemUpdate : (OSStatus (*)(CFDictionaryRef, CFDictionaryRef))dlsym(RTLD_DEFAULT, "SecItemUpdate");
    OSStatus status = func(queryToUse, attrsToUse);
    if (status == errSecMissingEntitlement || status == -34018) {
        NSMutableDictionary *fallbackQuery = [(__bridge NSDictionary *)query mutableCopy];
        [fallbackQuery removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        NSMutableDictionary *fallbackAttrs = [(__bridge NSDictionary *)attributesToUpdate mutableCopy];
        [fallbackAttrs removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        [fallbackAttrs removeObjectForKey:(__bridge id)kSecAttrAccessControl];
        status = func((__bridge CFDictionaryRef)fallbackQuery, (__bridge CFDictionaryRef)fallbackAttrs);
    }
    if (cleanQuery) CFRelease(cleanQuery);
    if (cleanAttrs) CFRelease(cleanAttrs);
    return status;
}

OSStatus fixed_SecItemDelete(CFDictionaryRef query) {
    CFDictionaryRef clean = stripAccessGroup(query);
    CFDictionaryRef toUse = clean ? clean : query;
    OSStatus (*func)(CFDictionaryRef) = orig_SecItemDelete ? orig_SecItemDelete : (OSStatus (*)(CFDictionaryRef))dlsym(RTLD_DEFAULT, "SecItemDelete");
    OSStatus status = func(toUse);
    if ((status == errSecMissingEntitlement || status == -34018) && !clean) {
        NSMutableDictionary *fallback = [(__bridge NSDictionary *)query mutableCopy];
        [fallback removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        status = func((__bridge CFDictionaryRef)fallback);
    }
    if (clean) CFRelease(clean);
    return status;
}

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
