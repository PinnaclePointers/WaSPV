//
//  WSPeer.h
//  WaSPV
//
//  Created by Davide De Rosa on 13/06/14.
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

#import "WSConnectionPool.h"
#import "WSConnection.h"
#import "WSMessageFactory.h"
#import "WSInventory.h"

@protocol WSParameters;
@class WSBloomFilter;
@class WSSignedTransaction;
@class WSBlockLocator;
@class WSBlockChain;
@class WSStorableBlock;

typedef enum {
    WSPeerStatusConnecting,
    WSPeerStatusDisconnected,
    WSPeerStatusConnected
} WSPeerStatus;

typedef enum {
    WSPeerServicesNodeNetwork = 0x1     // indicates a node offers full blocks, not just headers
} WSPeerServices;

#pragma mark -

@interface WSPeerParameters : NSObject

@property (nonatomic, assign) uint16_t port; // default network port

- (instancetype)initWithParameters:(id<WSParameters>)parameters;
- (instancetype)initWithParameters:(id<WSParameters>)parameters
              shouldDownloadBlocks:(BOOL)shouldDownloadBlocks
               needsBloomFiltering:(BOOL)needsBloomFiltering;

- (BOOL)shouldDownloadBlocks;
- (BOOL)needsBloomFiltering;

@end

#pragma mark -

//
// All is done on groupQueue except data that is sent/received on connectionQueue.
//

@protocol WSPeerDelegate;

@interface WSPeer : NSObject <WSConnectionProcessor>

@property (nonatomic, weak) id<WSPeerDelegate> delegate;
@property (nonatomic, weak) dispatch_queue_t delegateQueue;

- (instancetype)initWithHost:(NSString *)host parameters:(id<WSParameters>)parameters;
- (instancetype)initWithHost:(NSString *)host peerParameters:(WSPeerParameters *)peerParameters;

- (id<WSParameters>)parameters;

// connection
- (WSPeerStatus)peerStatus;
- (NSString *)remoteHost;
- (uint32_t)remoteAddress;
- (uint16_t)remotePort;
- (NSTimeInterval)connectionTime;
- (NSTimeInterval)lastSeenTimestamp;
- (uint32_t)version;
- (uint64_t)services;
- (uint64_t)timestamp;
- (uint32_t)lastBlockHeight;
- (void)cleanUpConnectionData;

// protocol
- (void)sendInvMessageWithInventory:(WSInventory *)inventory;
- (void)sendInvMessageWithInventories:(NSArray *)inventories; // WSInventory
- (void)sendGetdataMessageWithHashes:(NSArray *)hashes forInventoryType:(WSInventoryType)inventoryType;
- (void)sendGetdataMessageWithInventories:(NSArray *)inventories;
- (void)sendNotfoundMessageWithInventories:(NSArray *)inventories;
- (void)sendGetblocksMessageWithLocator:(WSBlockLocator *)locator hashStop:(WSHash256 *)hashStop;
- (void)sendGetheadersMessageWithLocator:(WSBlockLocator *)locator hashStop:(WSHash256 *)hashStop;
- (void)sendTxMessageWithTransaction:(WSSignedTransaction *)transaction;
- (void)sendGetaddr;
- (void)sendMempoolMessage;
- (void)sendPingMessage;
- (void)sendFilterloadMessageWithFilter:(WSBloomFilter *)filter;

// download
- (void)downloadBlockChain:(WSBlockChain *)blockChain
      fastCatchUpTimestamp:(uint32_t)fastCatchUpTimestamp
             prestartBlock:(void (^)(NSUInteger, NSUInteger))prestartBlock
               syncedBlock:(void (^)(NSUInteger))syncedBlock;

- (void)requestOutdatedBlocks;

// for testing, needs WASPV_TEST_MESSAGE_QUEUE to work
- (id<WSMessage>)dequeueMessageSynchronouslyWithTimeout:(NSUInteger)timeout;

@end

#pragma mark -

@protocol WSPeerDelegate <NSObject>

- (void)peerDidConnect:(WSPeer *)peer;
- (void)peer:(WSPeer *)peer didFailToConnectWithError:(NSError *)error;
- (void)peer:(WSPeer *)peer didDisconnectWithError:(NSError *)error;
- (void)peerDidKeepAlive:(WSPeer *)peer;
- (void)peer:(WSPeer *)peer didReceiveHeader:(WSBlockHeader *)header;
- (void)peer:(WSPeer *)peer didReceiveBlock:(WSBlock *)block;
- (void)peer:(WSPeer *)peer didReceiveFilteredBlock:(WSFilteredBlock *)filteredBlock withTransactions:(NSOrderedSet *)transactions;
- (void)peer:(WSPeer *)peer didReceiveTransaction:(WSSignedTransaction *)transaction;
- (void)peer:(WSPeer *)peer didReceiveAddresses:(NSArray *)addresses isLastRelay:(BOOL)isLastRelay; // WSAddress
- (void)peer:(WSPeer *)peer didReceivePongMesage:(WSMessagePong *)pong;
- (void)peer:(WSPeer *)peer didReceiveDataRequestWithInventories:(NSArray *)inventories; // WSInventory
- (void)peer:(WSPeer *)peer didReceiveRejectMessage:(WSMessageReject *)message;
- (void)peerDidRequestFilterReload:(WSPeer *)peer;
- (void)peer:(WSPeer *)peer didSendNumberOfBytes:(NSUInteger)numberOfBytes;
- (void)peer:(WSPeer *)peer didReceiveNumberOfBytes:(NSUInteger)numberOfBytes;

@end

#pragma mark -

@interface WSConnectionPool (Peer)

- (BOOL)openConnectionToPeer:(WSPeer *)peer;
- (WSPeer *)openConnectionToPeerHost:(NSString *)peerHost parameters:(id<WSParameters>)parameters;

@end
