//
//  WSPeerGroupNotifier.h
//  WaSPV
//
//  Created by Davide De Rosa on 24/07/14.
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

@class WSPeerGroup;
@class WSPeer;
@class WSStorableBlock;
@protocol WSTransaction;
@class WSSignedTransaction;

extern NSString *const WSPeerGroupDidConnectNotification;
extern NSString *const WSPeerGroupDidDisconnectNotification;
extern NSString *const WSPeerGroupPeerDidConnectNotification;
extern NSString *const WSPeerGroupPeerDidDisconnectNotification;
extern NSString *const WSPeerGroupPeerHostKey;
extern NSString *const WSPeerGroupReachedMaxConnectionsKey;

extern NSString *const WSPeerGroupDidStartDownloadNotification;
extern NSString *const WSPeerGroupDidFinishDownloadNotification;
extern NSString *const WSPeerGroupDidFailDownloadNotification;
extern NSString *const WSPeerGroupDidDownloadBlockNotification;
extern NSString *const WSPeerGroupWillRescanNotification;
extern NSString *const WSPeerGroupDownloadFromHeightKey;
extern NSString *const WSPeerGroupDownloadToHeightKey;
extern NSString *const WSPeerGroupDownloadBlockKey;

extern NSString *const WSPeerGroupDidRelayTransactionNotification;
extern NSString *const WSPeerGroupRelayTransactionKey;
extern NSString *const WSPeerGroupRelayIsPublishedKey;

extern NSString *const WSPeerGroupErrorKey;

#pragma mark -

//
// thread-safe: no
//
@interface WSPeerGroupNotifier : NSObject

- (instancetype)initWithPeerGroup:(WSPeerGroup *)peerGroup;

- (void)notifyConnected;
- (void)notifyDisconnected;
- (void)notifyPeerConnected:(WSPeer *)peer reachedMaxConnections:(BOOL)reachedMaxConnections;
- (void)notifyPeerDisconnected:(WSPeer *)peer;
- (void)notifyDownloadStartedFromHeight:(NSUInteger)fromHeight toHeight:(NSUInteger)toHeight;
- (void)notifyDownloadFinished;
- (void)notifyDownloadFailedWithError:(NSError *)error;
- (void)notifyBlockAdded:(WSStorableBlock *)block;
- (void)notifyTransaction:(WSSignedTransaction *)transaction fromPeer:(WSPeer *)peer isPublished:(BOOL)isPublished;
- (void)notifyRescan;

- (BOOL)didNotifyDownloadStarted;
- (double)downloadProgressAtHeight:(NSUInteger)height;

@end
