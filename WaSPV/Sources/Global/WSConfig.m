//
//  WSConfig.m
//  WaSPV
//
//  Created by Davide De Rosa on 05/07/14.
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

#import "WSConfig.h"

#pragma mark - Library

NSString *const         WSClientName                                = @"WaSPV";
NSString *const         WSClientVersion                             = @"0.4";

NSBundle *WSClientBundle(Class clazz)
{
    NSBundle *parentBundle = [NSBundle bundleForClass:clazz];
    NSString *bundlePath = [parentBundle pathForResource:WSClientName ofType:@"bundle"];
    return [NSBundle bundleWithPath:bundlePath];
}

#pragma mark - Local parameters

const uint32_t          WSSeedGeneratorDefaultEntropyBits           = 128;

const uint32_t          WSBlockUnknownHeight                        = UINT32_MAX;
const uint32_t          WSBlockUnknownTimestamp                     = UINT32_MAX;

const NSTimeInterval    WSPeerConnectTimeout                        = 3.0;
const uint32_t          WSPeerProtocol                              = 70002;
const uint32_t          WSPeerMinProtocol                           = 70001;    // SPV mode required
const NSUInteger        WSPeerEnabledServices                       = 0;        // we don't provide full blocks to remote nodes
const NSUInteger        WSPeerMaxFilteredBlockCount                 = 2000;

const NSUInteger        WSPeerGroupDefaultMaxConnections            = 3;
const NSUInteger        WSPeerGroupDefaultMaxConnectionFailures     = 15;
const NSTimeInterval    WSPeerGroupDefaultReconnectionDelay         = 10.0;
//const NSTimeInterval    WSPeerGroupDefaultPingInterval              = 5.0;
const NSTimeInterval    WSPeerGroupDefaultRequestTimeout            = 5.0;
//const NSUInteger        WSPeerGroupMaxPeerHours                     = 4;
const NSUInteger        WSPeerGroupMaxInactivePeers                 = 1000;

const double            WSPeerGroupDefaultBFRateMin                 = 0.0001;
const double            WSPeerGroupDefaultBFRateDelta               = 0.0004;
const double            WSPeerGroupDefaultBFObservedRateMax         = 10.0 * (WSPeerGroupDefaultBFRateMin + WSPeerGroupDefaultBFRateDelta);
const double            WSPeerGroupDefaultBFLowPassRatio            = 0.01;     // 1%
const NSUInteger        WSPeerGroupDefaultBFTxsPerBlock             = 600;

const uint32_t          WSMessageVersionLocalhost                   = 0x0100007f;

const NSUInteger        WSHDWalletDefaultGapLimit                   = 10;

const NSTimeInterval    WSJSONClientDefaultTimeout                  = 10.0;
