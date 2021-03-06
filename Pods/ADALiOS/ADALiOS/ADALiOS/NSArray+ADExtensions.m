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

#import "NSArray+ADExtensions.h"
#import "NSString+ADExtentions.h"

@implementation NSArray (ADExtensions)

- (NSString*)adSpaceDeliminatedString
{
    NSMutableString* string = [NSMutableString new];
    
    __block BOOL first = YES;
    
    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if (![obj isKindOfClass:[NSString class]])
        {
            return;
        }
        
        if (!first)
        {
            [string appendString:@" "];
        }
        else
        {
            first = NO;
        }
        
        [string appendString:obj];
    }];
    
    return string;
}

- (NSString*)adUrlFormEncode
{
    return [[self adSpaceDeliminatedString] adUrlFormEncode];
}

@end
