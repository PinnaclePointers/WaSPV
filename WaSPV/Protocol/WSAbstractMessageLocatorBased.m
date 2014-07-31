//
//  WSAbstractMessageLocatorBased.m
//  WaSPV
//
//  Created by Davide De Rosa on 08/07/14.
//  Copyright (c) 2014 Davide De Rosa. All rights reserved.
//
//  http://github.com/keeshux
//  http://twitter.com/keeshux
//  http://davidederosa.com
//
//  This file is part of WaSPV.
//
//  WaSPV is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  WaSPV is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with WaSPV.  If not, see <http://www.gnu.org/licenses/>.
//

#import "WSAbstractMessageLocatorBased.h"
#import "WSBlockLocator.h"

@interface WSAbstractMessageLocatorBased ()

@property (nonatomic, assign) uint32_t version;
@property (nonatomic, strong) WSBlockLocator *locator;
@property (nonatomic, strong) WSHash256 *hashStop;

- (instancetype)initWithVersion:(uint32_t)version locator:(WSBlockLocator *)locator hashStop:(WSHash256 *)hashStop;

@end

@implementation WSAbstractMessageLocatorBased

+ (instancetype)messageWithVersion:(uint32_t)version locator:(WSBlockLocator *)locator hashStop:(WSHash256 *)hashStop
{
    return [[self alloc] initWithVersion:version locator:locator hashStop:hashStop];
}

- (instancetype)initWithVersion:(uint32_t)version locator:(WSBlockLocator *)locator hashStop:(WSHash256 *)hashStop
{
    WSExceptionCheckIllegal(locator != nil, @"Nil locator");
    
    if ((self = [super init])) {
        self.version = version;
        self.locator = locator;
        self.hashStop = (hashStop ? hashStop : WSHash256Zero());
    }
    return self;
}

#pragma mark WSMessage

- (NSString *)payloadDescriptionWithIndent:(NSUInteger)indent
{
    NSMutableArray *tokens = [[NSMutableArray alloc] init];
    [tokens addObject:[NSString stringWithFormat:@"version = %u", self.version]];
    [tokens addObject:[NSString stringWithFormat:@"hashStop = %@", self.hashStop]];
    [tokens addObject:[NSString stringWithFormat:@"locator = %@", [self.locator descriptionWithIndent:(indent + 1)]]];
    return [NSString stringWithFormat:@"{%@}", WSStringDescriptionFromTokens(tokens, indent)];
}

#pragma mark WSBufferEncoder

- (void)appendToMutableBuffer:(WSMutableBuffer *)buffer
{
    [buffer appendUint32:self.version];
    [self.locator appendToMutableBuffer:buffer];
    [buffer appendHash256:self.hashStop];
}

- (WSBuffer *)toBuffer
{
    // version + var_int + (inventories.count + hash_stop) * hash256
    const NSUInteger capacity = 4 + 8 + (self.locator.hashes.count + 1) * WSHash256Length;
    
    WSMutableBuffer *buffer = [[WSMutableBuffer alloc] initWithCapacity:capacity];
    [self appendToMutableBuffer:buffer];
    return buffer;
}

@end
