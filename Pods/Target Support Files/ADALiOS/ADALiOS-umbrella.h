#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "ADAL.h"
#import "ADAuthenticationBroker.h"
#import "ADAuthenticationContext.h"
#import "ADAuthenticationError.h"
#import "ADAuthenticationParameters.h"
#import "ADAuthenticationResult.h"
#import "ADAuthenticationSettings.h"
#import "ADErrorCodes.h"
#import "ADInstanceDiscovery.h"
#import "ADLogger.h"
#import "ADProfileInfo.h"
#import "ADTokenCacheStoreItem.h"
#import "ADTokenCacheStoreKey.h"
#import "ADTokenCacheStoring.h"
#import "ADUserIdentifier.h"

FOUNDATION_EXPORT double ADALiOSVersionNumber;
FOUNDATION_EXPORT const unsigned char ADALiOSVersionString[];

