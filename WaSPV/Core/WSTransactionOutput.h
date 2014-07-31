//
//  WSTransactionOutput.h
//  WaSPV
//
//  Created by Davide De Rosa on 26/07/14.
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

#import <Foundation/Foundation.h>

#import "WSSized.h"

@interface WSTransactionOutput : NSObject <WSBufferEncoder, WSBufferDecoder, WSSized>

- (instancetype)initWithValue:(uint64_t)value script:(WSScript *)script;
- (instancetype)initWithValue:(uint64_t)value address:(WSAddress *)address;
- (uint64_t)value;
- (WSScript *)script;
- (WSAddress *)address;

@end
