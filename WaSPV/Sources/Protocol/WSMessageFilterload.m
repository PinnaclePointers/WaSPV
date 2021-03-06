//
//  WSMessageFilterload.m
//  WaSPV
//
//  Created by Davide De Rosa on 28/06/14.
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

#import "WSMessageFilterload.h"
#import "WSErrors.h"

@interface WSMessageFilterload ()

@property (nonatomic, strong) WSBloomFilter *filter;

- (instancetype)initWithParameters:(id<WSParameters>)parameters filter:(WSBloomFilter *)filter;

@end

@implementation WSMessageFilterload

+ (instancetype)messageWithParameters:(id<WSParameters>)parameters filter:(WSBloomFilter *)filter
{
    return [[self alloc] initWithParameters:parameters filter:filter];
}

- (instancetype)initWithParameters:(id<WSParameters>)parameters filter:(WSBloomFilter *)filter
{
    WSExceptionCheckIllegal(filter != nil, @"Nil filter");

    if ((self = [super initWithParameters:parameters])) {
        self.filter = filter;
    }
    return self;
}

#pragma mark WSMessage

- (NSString *)messageType
{
    return WSMessageType_FILTERLOAD;
}

- (NSString *)payloadDescriptionWithIndent:(NSUInteger)indent
{
    return [self.filter description];
}

#pragma mark WSBufferEncoder

- (void)appendToMutableBuffer:(WSMutableBuffer *)buffer
{
    [self.filter appendToMutableBuffer:buffer];
}

- (WSBuffer *)toBuffer
{
    return [self.filter toBuffer];
}

@end
