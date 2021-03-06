//
//  WSMessagePing.m
//  WaSPV
//
//  Created by Davide De Rosa on 27/06/14.
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

#import "WSMessagePing.h"
#import "WSErrors.h"

@interface WSMessagePing ()

@property (nonatomic, assign) uint64_t nonce;

@end

@implementation WSMessagePing

- (instancetype)initWithParameters:(id<WSParameters>)parameters
{
    if ((self = [super initWithParameters:parameters])) {
        self.nonce = mrand48();
    }
    return self;
}

#pragma mark WSMessage

- (NSString *)messageType
{
    return WSMessageType_PING;
}

- (NSString *)payloadDescriptionWithIndent:(NSUInteger)indent
{
    return [NSString stringWithFormat:@"{nonce=%0llx}", self.nonce];
}

#pragma mark WSBufferEncoder

- (void)appendToMutableBuffer:(WSMutableBuffer *)buffer
{
    [buffer appendUint64:self.nonce];
}

- (WSBuffer *)toBuffer
{
    // nonce
    WSMutableBuffer *buffer = [[WSMutableBuffer alloc] initWithCapacity:8];
    [self appendToMutableBuffer:buffer];
    return buffer;
}

#pragma mark WSBufferDecoder

- (instancetype)initWithParameters:(id<WSParameters>)parameters buffer:(WSBuffer *)buffer from:(NSUInteger)from available:(NSUInteger)available error:(NSError *__autoreleasing *)error
{
    if (available < sizeof(uint64_t)) {
        WSErrorSetNotEnoughMessageBytes(error, self.messageType, available, sizeof(uint64_t));
        return nil;
    }
    
    if ((self = [super initWithParameters:parameters originalLength:buffer.length])) {
        self.nonce = [buffer uint64AtOffset:from];
    }
    return self;
}

@end
