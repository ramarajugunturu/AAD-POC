// Copyright © Microsoft Open Technologies, Inc.
//
// All Rights Reserved
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
// OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
// ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A
// PARTICULAR PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
//
// See the Apache License, Version 2.0 for the specific language
// governing permissions and limitations under the License.

#import "ADAuthenticationContext+Internal.h"
#import "ADOAuth2Constants.h"
#import "ADHelpers.h"
#import "ADUserIdentifier.h"
#import "ADTokenCacheStoreItem+Internal.h"

@implementation ADAuthenticationContext (TokenCaching)

//Gets an item from the cache, where userId may be nil. Raises error, if items for multiple users
//are present and user id is not specified.
- (ADTokenCacheStoreItem*)extractCacheItemWithKey:(ADTokenCacheStoreKey*)key
                                           userId:(ADUserIdentifier*)userId
                                            error:(ADAuthenticationError* __autoreleasing*)error
{
    if (!key || !self.tokenCacheStore)
    {
        return nil;//Nothing to return
    }
    
    ADAuthenticationError* localError = nil;
    ADTokenCacheStoreItem* item = [self.tokenCacheStore getItemWithKey:key error:&localError];
    
    if (error && localError)
    {
        *error = localError;
    }
    return item;
}

//Checks the cache for item that can be used to get directly or indirectly an access token.
//Checks the multi-resource refresh tokens too.
- (ADTokenCacheStoreItem*)findCacheItemWithKey:(ADTokenCacheStoreKey*) key
                                        userId:(ADUserIdentifier*)userId
                                useToken:(BOOL*) useToken
                                         error:(ADAuthenticationError* __autoreleasing*) error
{
    if (!key || !self.tokenCacheStore)
    {
        return nil;//Nothing to return
    }
    ADAuthenticationError* localError;
    ADTokenCacheStoreItem* item = [self extractCacheItemWithKey:key userId:userId error:&localError];
    if (localError)
    {
        if (error)
        {
            *error = localError;
        }
        return nil;//Quick return if an error was detected.
    }
    
    if (item)
    {
        *useToken = item.token && !item.isExpired;
        if (*useToken)
        {
            return item;
        }
        else if (![NSString adIsStringNilOrBlank:item.refreshToken])
        {
            return item;//Suitable direct refresh token found.
        }
        else
        {
            //We have a cache item that cannot be used anymore, remove it from the cache:
            [self.tokenCacheStore removeItemWithKey:key error:nil];
        }
    }
    
    *useToken = false;//No item with suitable access token exists
    
    return nil;//Nothing suitable
}

//Understands and processes the access token response:
- (ADAuthenticationResult *)processTokenResponse:(NSDictionary *)response
                                         forItem:(ADTokenCacheStoreItem*)item
                                     fromRefresh:(BOOL)fromRefreshTokenWorkflow
                            requestCorrelationId:(NSUUID*)requestCorrelationId
{
    if (!response)
    {
        ADAuthenticationError* error = [ADAuthenticationError errorFromAuthenticationError:AD_ERROR_CONNECTION_MISSING_RESPONSE
                                                      protocolCode:nil
                                                      errorDetails:@"No valid response to parse for token."];
        return [ADAuthenticationResult resultFromError:error];
    }
    
    if (!item)
    {
        ADAuthenticationError* error = [ADAuthenticationError errorFromAuthenticationError:AD_ERROR_UNEXPECTED
                                                      protocolCode:nil
                                                      errorDetails:@"No cache item to process token into. An errort must have occurred somewhere."];
        return [ADAuthenticationResult resultFromError:error];
    }
    
    AD_LOG_VERBOSE(@"Token extraction", @"Attempt to extract the data from the server response.");
    
    NSString* responseId = [response objectForKey:OAUTH2_CORRELATION_ID_RESPONSE];
    NSUUID* responseUUID;
    if (![NSString adIsStringNilOrBlank:responseId])
    {
        responseUUID = [[NSUUID alloc] initWithUUIDString:responseId];
        if (!responseUUID)
        {
            AD_LOG_INFO_F(@"Bad correlation id", @"The received correlation id is not a valid UUID. Sent: %@; Received: %@", requestCorrelationId, responseId);
        }
        else if (![requestCorrelationId isEqual:responseUUID])
        {
            AD_LOG_INFO_F(@"Correlation id mismatch", @"Mismatch between the sent correlation id and the received one. Sent: %@; Received: %@", requestCorrelationId, responseId);
        }
    }
    else
    {
        AD_LOG_INFO_F(@"Missing correlation id", @"No correlation id received for request with correlation id: %@", [requestCorrelationId UUIDString]);
    }
    
    ADAuthenticationError* error = [ADAuthenticationContext errorFromDictionary:response errorCode:(fromRefreshTokenWorkflow) ? AD_ERROR_INVALID_REFRESH_TOKEN : AD_ERROR_AUTHENTICATION];
    if (error)
    {
        return [ADAuthenticationResult resultFromError:error];
    }
    
    if (![NSString adIsStringNilOrBlank:[response objectForKey:OAUTH2_ACCESS_TOKEN]]
        || ![NSString adIsStringNilOrBlank:[response objectForKey:OAUTH2_ID_TOKEN]])
    {
        [item setAuthority:self.authority];
        [item fillItemWithResponse:response];
        return [ADAuthenticationResult resultFromTokenCacheStoreItem:item];
    }
    
    //No access/id token and no error, we assume that there was another kind of error (connection, server down, etc.).
    //Note that for security reasons we log only the keys, not the values returned by the user:
    NSString* errorMessage = [NSString stringWithFormat:@"The server returned without providing an error. Keys returned: %@", [response allKeys]];
    error = [ADAuthenticationError errorFromAuthenticationError:AD_ERROR_AUTHENTICATION
                                                   protocolCode:nil
                                                   errorDetails:errorMessage];
    return [ADAuthenticationResult resultFromError:error];
}

//Stores the result in the cache. cacheItem parameter may be nil, if the result is successfull and contains
//the item to be stored.
- (void)updateCacheToResult:(ADAuthenticationResult*)result
                  cacheItem:(ADTokenCacheStoreItem*)cacheItem
           withRefreshToken:(NSString*)refreshToken
{
    [self updateCacheToResult:result
                cacheInstance:self.tokenCacheStore
                    cacheItem:cacheItem
             withRefreshToken:refreshToken];
}

- (void)updateCacheToResult:(ADAuthenticationResult*)result
              cacheInstance:(id<ADTokenCacheStoring>)tokenCacheStoreInstance
                  cacheItem:(ADTokenCacheStoreItem*)cacheItem
           withRefreshToken:(NSString*)refreshToken
{
    if(![ADAuthenticationContext handleNilOrEmptyAsResult:result argumentName:@"result" authenticationResult:&result]){
        return;
    }
    
    if (!tokenCacheStoreInstance)
        return;//No cache to update
    
    if (AD_SUCCEEDED == result.status)
    {
        if(![ADAuthenticationContext handleNilOrEmptyAsResult:result.tokenCacheStoreItem argumentName:@"tokenCacheStoreItem" authenticationResult:&result]
           || ![ADAuthenticationContext handleNilOrEmptyAsResult:result.tokenCacheStoreItem.scopes argumentName:@"scopes" authenticationResult:&result]
           || ![ADAuthenticationContext handleNilOrEmptyAsResult:result.tokenCacheStoreItem.token argumentName:@"token" authenticationResult:&result])
        {
            return;
        }
        
        //In case of success we use explicitly the item that comes back in the result:
        cacheItem = result.tokenCacheStoreItem;
        
        AD_LOG_VERBOSE_F(@"Token cache store", @"Storing access token for scopes: %@", cacheItem.scopes);
        [tokenCacheStoreInstance addOrUpdateItem:cacheItem error:nil];    }
    else
    {
        if (AD_ERROR_INVALID_REFRESH_TOKEN == result.error.code)
        {//Bad refresh token. Remove it from the cache:
            if(![ADAuthenticationContext handleNilOrEmptyAsResult:cacheItem argumentName:@"cacheItem" authenticationResult:&result]
               || ![ADAuthenticationContext handleNilOrEmptyAsResult:cacheItem.scopes argumentName:@"cacheItem.scopes" authenticationResult:&result]
               || ![ADAuthenticationContext handleNilOrEmptyAsResult:refreshToken argumentName:@"refreshToken" authenticationResult:&result])
            {
                return;
            }
            
            //BOOL removed = NO;
            //The refresh token didn't work. We need to clear this refresh item from the cache.
            ADTokenCacheStoreKey* exactKey = [cacheItem extractKeyWithError:nil];
            if (exactKey)
            {
                ADTokenCacheStoreItem* existing = [tokenCacheStoreInstance getItemWithKey:exactKey error:nil];
                if ([refreshToken isEqualToString:existing.refreshToken])//If still there, attempt to remove
                {
                    AD_LOG_VERBOSE_F(@"Token cache store", @"Removing cache for scopes: %@", cacheItem.scopes);
                    [tokenCacheStoreInstance removeItemWithKey:exactKey error:nil];
                    //removed = YES;
                }
            }
        }
    }
}

@end
