//
//  SFHFKeychainUtils.m
//
//  Created by Buzz Andersen on 10/20/08.
//  Based partly on code by Jonathan Wight, Jon Crosby, and Mike Malone.
//  Copyright 2008 Sci-Fi Hi-Fi. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

#if ! __has_feature(objc_arc)
#error This file must be compiled with ARC.
#endif

#import "SFHFKeychainUtils.h"
#import <Security/Security.h>

static NSString *SFHFKeychainUtilsErrorDomain = @"SFHFKeychainUtilsErrorDomain";

@implementation SFHFKeychainUtils

+ (NSString *) getPasswordForUsername: (NSString *) username andServiceName: (NSString *) serviceName inAccessGroup:(NSString *) accessGroup  isSynchronizable:(BOOL *) isSynchronizable error: (NSError **) error {
	if (!username || !serviceName) {
		if (error != nil) {
			*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: -2000 userInfo: nil];
		}
		return nil;
	}
	
	if (error != nil) {
		*error = nil;
	}
    
	// Set up a query dictionary with the base query attributes: item type (generic), username, and service
    NSMutableDictionary *query = [@{(__bridge_transfer NSString *) kSecClass : (__bridge_transfer NSString *) kSecClassGenericPassword,
                                    (__bridge_transfer NSString *) kSecAttrAccount : username,
                                    (__bridge_transfer NSString *) kSecAttrService : serviceName,
                                    (__bridge_transfer NSString *) kSecAttrSynchronizable : (__bridge_transfer NSString *) kSecAttrSynchronizableAny} mutableCopy];
    if (accessGroup) {
#if TARGET_IPHONE_SIMULATOR
        // Ignore the access group if running on the iPhone simulator.
        //
        // Apps that are built for the simulator aren't signed, so there's no keychain access group
        // for the simulator to check. This means that all apps can see all keychain items when run
        // on the simulator.
        //
        // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
        // simulator will return -25243 (errSecNoAccessForItem).
#else
        query[(__bridge_transfer NSString *) kSecAttrAccessGroup] = accessGroup;
#endif
    }
	
	// First do a query for attributes, in case we already have a Keychain item with no password data set.
	// One likely way such an incorrect item could have come about is due to the previous (incorrect)
	// version of this code (which set the password as a generic attribute instead of password data).
	
	NSMutableDictionary *attributeQuery = [query mutableCopy];
	attributeQuery[(__bridge_transfer id) kSecReturnAttributes] = (id) kCFBooleanTrue;
    CFTypeRef attrResult = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef) attributeQuery, &attrResult);
    
	if (status != noErr) {
		// No existing item found--simply return nil for the password
		if (error != nil && status != errSecItemNotFound) {
			//Only return an error if a real exception happened--not simply for "not found."
			*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: status userInfo: nil];
		}
		
		return nil;
	}
	
	// We have an existing item, now extract whether it's synchronizable or not
    if (attrResult != NULL) {
        NSDictionary *attributeResult = (__bridge_transfer NSDictionary *)attrResult;
        if (isSynchronizable != NULL) {
            NSNumber *syncValue = attributeResult[(__bridge_transfer NSString *)kSecAttrSynchronizable];
            *isSynchronizable = [syncValue isEqualToNumber:@YES];
        }
    }


    // then query for the password data associated with it.
	
	NSMutableDictionary *passwordQuery = [query mutableCopy];
    passwordQuery[(__bridge_transfer id) kSecReturnData] = (id) kCFBooleanTrue;
    CFTypeRef resData = NULL;
	status = SecItemCopyMatching((__bridge CFDictionaryRef) passwordQuery, (CFTypeRef *) &resData);
	NSData *resultData = (__bridge_transfer NSData *)resData;
	
	if (status != noErr) {
		if (status == errSecItemNotFound) {
			// We found attributes for the item previously, but no password now, so return a special error.
			// Users of this API will probably want to detect this error and prompt the user to
			// re-enter their credentials.  When you attempt to store the re-entered credentials
			// using storeUsername:andPassword:forServiceName:updateExisting:error
			// the old, incorrect entry will be deleted and a new one with a properly encrypted
			// password will be added.
			if (error != nil) {
				*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: -1999 userInfo: nil];
			}
		}
		else {
			// Something else went wrong. Simply return the normal Keychain API error code.
			if (error != nil) {
				*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: status userInfo: nil];
			}
		}
		
		return nil;
	}
    
	NSString *password = nil;	
    
	if (resultData) {
		password = [[NSString alloc] initWithData: resultData encoding: NSUTF8StringEncoding];
	}
	else {
		// There is an existing item, but we weren't able to get password data for it for some reason,
		// Possibly as a result of an item being incorrectly entered by the previous code.
		// Set the -1999 error so the code above us can prompt the user again.
		if (error != nil) {
			*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: -1999 userInfo: nil];
		}
	}
    
	return password;
}

+ (BOOL) storeUsername: (NSString *) username andPassword: (NSString *) password forServiceName: (NSString *) serviceName inAccessGroup:(NSString *) accessGroup label: (NSString *) label updateExisting: (BOOL) updateExisting context:(NSString *) context synchronizable:(BOOL) synchronizable error: (NSError **) error
{		
	if (!username || !password || !serviceName) 
    {
		if (error != nil) 
        {
			*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: -2000 userInfo: nil];
		}
		return NO;
	}
	
	// See if we already have a password entered for these credentials.
	NSError *getError = nil;
    BOOL existingIsSynchronizable = NO;
    NSString *existingPassword = [SFHFKeychainUtils getPasswordForUsername: username andServiceName: serviceName inAccessGroup: accessGroup isSynchronizable:&existingIsSynchronizable error:&getError];
    
	if ([getError code] == -1999) 
    {
		// There is an existing entry without a password properly stored (possibly as a result of the previous incorrect version of this code.
		// Delete the existing item before moving on entering a correct one.
        
		getError = nil;
		
		[self deleteItemForUsername: username andServiceName: serviceName inAccessGroup: accessGroup error: &getError];
        
		if ([getError code] != noErr) 
        {
			if (error != nil) 
            {
				*error = getError;
			}
			return NO;
		}
	}
	else if ([getError code] != noErr) 
    {
		if (error != nil) 
        {
			*error = getError;
		}
		return NO;
	}
	
	if (error != nil) 
    {
		*error = nil;
	}
	
	OSStatus status = noErr;
    
	if (existingPassword) 
    {
		// We have an existing, properly entered item with a password.
		// Update the existing item.
		
		if ((![existingPassword isEqualToString:password] || existingIsSynchronizable != synchronizable) && updateExisting)
        {
			//Only update if we're allowed to update existing.  If not, simply do nothing.
            NSMutableDictionary *query = [@{(__bridge_transfer NSString *) kSecClass : (__bridge_transfer NSString *) kSecClassGenericPassword,
                                            (__bridge_transfer NSString *) kSecAttrService : serviceName,
                                            (__bridge_transfer NSString *) kSecAttrLabel : label ? label : serviceName,
                                            (__bridge_transfer NSString *) kSecAttrAccount : username,
                                            (__bridge_transfer NSString *) kSecAttrSynchronizable : (__bridge_transfer NSString *) kSecAttrSynchronizableAny} mutableCopy];
            if (accessGroup) {
#if TARGET_IPHONE_SIMULATOR
				// Ignore the access group if running on the iPhone simulator.
				//
				// Apps that are built for the simulator aren't signed, so there's no keychain access group
				// for the simulator to check. This means that all apps can see all keychain items when run
				// on the simulator.
				//
				// If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
				// simulator will return -25243 (errSecNoAccessForItem).
#else
                query[(__bridge_transfer NSString *) kSecAttrAccessGroup] = accessGroup;
#endif
            }

            if (context) {
                query[(__bridge_transfer NSString *) kSecAttrGeneric] = [context copy];
            }

            NSDictionary *attributesToUpdate = @{(__bridge_transfer NSString *) kSecValueData : [password dataUsingEncoding: NSUTF8StringEncoding],
                                                 (__bridge_transfer NSString *) kSecAttrAccessible : (__bridge_transfer NSString *) kSecAttrAccessibleAlways,
                                                 (__bridge_transfer NSString *) kSecAttrSynchronizable : (synchronizable ? (id)kCFBooleanTrue : (id)kCFBooleanFalse)};
			
			status = SecItemUpdate((__bridge_retained CFDictionaryRef) query, (__bridge_retained CFDictionaryRef) attributesToUpdate);
		}
	}
	else 
    {
		// No existing entry (or an existing, improperly entered, and therefore now
		// deleted, entry).  Create a new entry.

		NSMutableDictionary *query = [@{(__bridge_transfer NSString *) kSecClass : (__bridge_transfer NSString *) kSecClassGenericPassword,
                                        (__bridge_transfer NSString *) kSecAttrService : serviceName,
                                        (__bridge_transfer NSString *) kSecAttrLabel : label ? label : serviceName,
                                        (__bridge_transfer NSString *) kSecAttrAccount : username,
                                        (__bridge_transfer NSString *) kSecValueData : [password dataUsingEncoding: NSUTF8StringEncoding],
                                        (__bridge_transfer NSString *) kSecAttrAccessible : (__bridge_transfer NSString *) kSecAttrAccessibleAlways,
                                        (__bridge_transfer NSString *) kSecAttrSynchronizable : (synchronizable ? (id)kCFBooleanTrue : (id)kCFBooleanFalse)} mutableCopy];
        if (accessGroup) {
#if TARGET_IPHONE_SIMULATOR
            // Ignore the access group if running on the iPhone simulator.
            //
            // Apps that are built for the simulator aren't signed, so there's no keychain access group
            // for the simulator to check. This means that all apps can see all keychain items when run
            // on the simulator.
            //
            // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
            // simulator will return -25243 (errSecNoAccessForItem).
#else
            query[(__bridge_transfer NSString *) kSecAttrAccessGroup] = accessGroup;
#endif
        }

        if (context) {
            query[(__bridge_transfer NSString *) kSecAttrGeneric] = [context copy];
        }

		status = SecItemAdd((__bridge_retained CFDictionaryRef) query, NULL);
	}
	
	if (error != nil && status != noErr) 
    {
		// Something went wrong with adding the new item. Return the Keychain error code.
		*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: status userInfo: nil];
        
        return NO;
	}
    
    return YES;
}

+ (BOOL) deleteItemForUsername: (NSString *) username andServiceName: (NSString *) serviceName inAccessGroup:(NSString *) accessGroup error: (NSError **) error
{
	if (!username || !serviceName) 
    {
		if (error != nil) 
        {
			*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: -2000 userInfo: nil];
		}
		return NO;
	}
	
	if (error != nil) 
    {
		*error = nil;
	}

	NSMutableDictionary *query = [@{(__bridge_transfer NSString *) kSecClass : (__bridge_transfer NSString *) kSecClassGenericPassword,
                                    (__bridge_transfer NSString *) kSecAttrAccount : username,
                                    (__bridge_transfer NSString *) kSecAttrService : serviceName,
                                    (__bridge_transfer NSString *) kSecReturnAttributes : (id) kCFBooleanTrue,
                                    (__bridge_transfer NSString *) kSecAttrSynchronizable : (__bridge_transfer NSString *) kSecAttrSynchronizableAny} mutableCopy];
    if (accessGroup) {
#if TARGET_IPHONE_SIMULATOR
        // Ignore the access group if running on the iPhone simulator.
        //
        // Apps that are built for the simulator aren't signed, so there's no keychain access group
        // for the simulator to check. This means that all apps can see all keychain items when run
        // on the simulator.
        //
        // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
        // simulator will return -25243 (errSecNoAccessForItem).
#else
        query[(__bridge_transfer NSString *) kSecAttrAccessGroup] = accessGroup;
#endif
    }

	OSStatus status = SecItemDelete((__bridge CFDictionaryRef) query);
	
	if (error != nil && status != noErr) 
    {
		*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: status userInfo: nil];		
        
        return NO;
	}
    
    return YES;
}

+ (BOOL) purgeItemsForServiceName:(NSString *) serviceName inAccessGroup:(NSString *) accessGroup error: (NSError **) error {
    if (!serviceName) 
    {
		if (error != nil) 
        {
			*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: -2000 userInfo: nil];
		}
		return NO;
	}
	
	if (error != nil) 
    {
		*error = nil;
	}
    
    NSMutableDictionary *searchData = [NSMutableDictionary new];
    searchData[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    searchData[(__bridge id)kSecAttrService] = serviceName;
    searchData[(__bridge id)kSecAttrSynchronizable] = (__bridge id)kSecAttrSynchronizableAny;
    if (accessGroup) {
#if TARGET_IPHONE_SIMULATOR
        // Ignore the access group if running on the iPhone simulator.
        //
        // Apps that are built for the simulator aren't signed, so there's no keychain access group
        // for the simulator to check. This means that all apps can see all keychain items when run
        // on the simulator.
        //
        // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
        // simulator will return -25243 (errSecNoAccessForItem).
#else
        searchData[(__bridge id)kSecAttrAccessGroup] = accessGroup;
#endif
    }

    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)searchData);

	if (error != nil && status != noErr) 
    {
		*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: status userInfo: nil];		
        
        return NO;
	}
    
    return YES;
}


+ (NSArray *) itemsForServiceName:(NSString *) serviceName inAccessGroup:(NSString *) accessGroup error: (NSError **) error {
    if (!serviceName)
    {
		if (error != nil)
        {
			*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: -2000 userInfo: nil];
		}
		return nil;
	}

	if (error != nil)
    {
		*error = nil;
	}

    NSMutableDictionary *searchData = [NSMutableDictionary new];
    searchData[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    searchData[(__bridge id)kSecAttrService] = serviceName;
    searchData[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;
    searchData[(__bridge id)kSecReturnAttributes] = (id) kCFBooleanTrue;
    searchData[(__bridge id)kSecAttrSynchronizable] = (__bridge id)kSecAttrSynchronizableAny;
    if (accessGroup) {
#if TARGET_IPHONE_SIMULATOR
        // Ignore the access group if running on the iPhone simulator.
        //
        // Apps that are built for the simulator aren't signed, so there's no keychain access group
        // for the simulator to check. This means that all apps can see all keychain items when run
        // on the simulator.
        //
        // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
        // simulator will return -25243 (errSecNoAccessForItem).
#else
        searchData[(__bridge id)kSecAttrAccessGroup] = accessGroup;
#endif
    }

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)searchData, &result);

	if (error != nil && status != noErr)
    {
		*error = [NSError errorWithDomain: SFHFKeychainUtilsErrorDomain code: status userInfo: nil];

        return nil;
	}

    return (__bridge NSArray *)result;
}

@end