//
//  WSHDWallet.m
//  WaSPV
//
//  Created by Davide De Rosa on 22/07/14.
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

#import "AutoCoding.h"

#import "WSHDWallet.h"
#import "WSSeed.h"
#import "WSHash256.h"
#import "WSHash160.h"
#import "WSHDKeyring.h"
#import "WSTransactionOutPoint.h"
#import "WSTransactionInput.h"
#import "WSTransactionOutput.h"
#import "WSTransaction.h"
#import "WSBloomFilter.h"
#import "WSPublicKey.h"
#import "WSAddress.h"
#import "WSScript.h"
#import "WSStorableBlock.h"
#import "WSTransactionMetadata.h"
#import "WSConfig.h"
#import "WSBitcoin.h"
#import "WSMacros.h"
#import "WSErrors.h"

NSString *const WSHDWalletDefaultChainsPath      = @"m/0'";

@interface WSHDWallet () {

    // essential backup data
    WSNetworkType _networkType;
    NSUInteger _gapLimit;

    // serialized for convenience
    NSMutableOrderedSet *_allExternalAddresses;         // WSAddress
    NSMutableOrderedSet *_allInternalAddresses;         // WSAddress
    uint32_t _currentExternalAccount;
    uint32_t _currentInternalAccount;
    NSMutableOrderedSet *_txs;                          // WSSignedTransaction
    NSMutableSet *_usedAddresses;                       // WSAddress
    NSMutableDictionary *_metadataByTxId;               // WSHash256 -> WSTransactionMetadata

    // transient (sensitive)
    WSSeed *_seed;
    id<WSBIP32Keyring> _externalChain;
    id<WSBIP32Keyring> _internalChain;

    // transient (not sensitive)
    NSString *_path;
    NSMutableDictionary *_txsById;                      // WSHash256 -> WSSignedTransaction
    NSSet *_spentOutpoints;                             // WSTransactionOutPoint
    NSOrderedSet *_unspentOutpoints;                    // WSTransactionOutPoint
    NSSet *_invalidTxIds;                               // WSHash256
    uint64_t _balance;
    uint64_t _confirmedBalance;
}

@property (nonatomic, strong) id<WSParameters> parameters;

- (BOOL)generateAddressesWithLookAhead:(NSUInteger)lookAhead forced:(BOOL)forced;
- (BOOL)generateAddressesWithLookAhead:(NSUInteger)lookAhead internal:(BOOL)internal forced:(BOOL)forced;
//- (void)cleanTransientStructures;

//
// if (batch == YES)
//
// - transactions are not sorted
// - balance is not updated
// - notifications are disabled
//
- (BOOL)registerTransaction:(WSSignedTransaction *)transaction didGenerateNewAddresses:(BOOL *)didGenerateNewAddresses batch:(BOOL)batch;
- (BOOL)unregisterTransaction:(WSSignedTransaction *)transaction batch:(BOOL)batch;
- (NSDictionary *)registerBlock:(WSStorableBlock *)block batch:(BOOL)batch;
- (NSDictionary *)unregisterBlock:(WSStorableBlock *)block batch:(BOOL)batch;
- (void)sortTransactions;
- (void)recalculateSpendsAndBalance;

// safe accessors ensure existence
- (id<WSBIP32Keyring>)safeExternalChain;
- (id<WSBIP32Keyring>)safeInternalChain;

- (void)setPath:(NSString *)path;
- (void)loadSensitiveDataWithSeed:(WSSeed *)seed chainsPath:(NSString *)chainsPath;
- (void)rebuildTransientStructures;
- (void)unloadSensitiveData;

- (WSTransactionOutput *)previousOutputFromInput:(WSSignedTransactionInput *)input;
- (WSSignedTransaction *)signedTransactionWithBuilder:(WSTransactionBuilder *)builder error:(NSError *__autoreleasing *)error;
- (void)notifyWithName:(NSString *)name userInfo:(NSDictionary *)userInfo;

@end

@implementation WSHDWallet

- (instancetype)initWithParameters:(id<WSParameters>)parameters seed:(WSSeed *)seed
{
    return [self initWithParameters:parameters seed:seed gapLimit:WSHDWalletDefaultGapLimit];
}

- (instancetype)initWithParameters:(id<WSParameters>)parameters seed:(WSSeed *)seed gapLimit:(NSUInteger)gapLimit
{
    return [self initWithParameters:parameters seed:seed gapLimit:gapLimit chainsPath:WSHDWalletDefaultChainsPath];
}

- (instancetype)initWithParameters:(id<WSParameters>)parameters seed:(WSSeed *)seed gapLimit:(NSUInteger)gapLimit chainsPath:(NSString *)chainsPath
{
    WSExceptionCheckIllegal(parameters != nil, @"Nil parameters");
    WSExceptionCheckIllegal(seed != nil, @"Nil seed");
    WSExceptionCheckIllegal(gapLimit > 0, @"Non-positive gapLimit");
    WSExceptionCheckIllegal(chainsPath != nil, @"Nil chainsPath");
    
    if ((self = [self init])) {
        self.parameters = parameters;
        _networkType = parameters.networkType;
        _gapLimit = gapLimit;

        _allExternalAddresses = [[NSMutableOrderedSet alloc] init];
        _allInternalAddresses = [[NSMutableOrderedSet alloc] init];
        _currentExternalAccount = 0;
        _currentInternalAccount = 0;
        _txs = [[NSMutableOrderedSet alloc] init];
        _usedAddresses = [[NSMutableSet alloc] init];
        _metadataByTxId = [[NSMutableDictionary alloc] init];
        
        [self loadSensitiveDataWithSeed:seed chainsPath:chainsPath];
        [self rebuildTransientStructures];
    }
    return self;
}

- (WSSeed *)seed
{
    @synchronized (self) {
        return _seed;
    }
}

- (NSUInteger)gapLimit
{
    @synchronized (self) {
        return _gapLimit;
    }
}

//- (void)cleanTransientStructures
//{
//    @synchronized (self) {
//        _externalChain = nil;
//        _internalChain = nil;
//        _txsById = nil;
//        _spentOutputs = nil;
//        _unspentOutputs = nil;
//        _invalidTxIds = nil;
//        _balance = 0;
//        _confirmedBalance = 0;
//    }
//}

- (NSString *)description
{
    return [self descriptionWithIndent:0];
}

#pragma mark Access

- (NSTimeInterval)creationTime
{
    @synchronized (self) {
        WSExceptionCheckIllegal(_seed != nil, @"Seed is missing, probably unloaded with unloadSensitiveData and never reloaded");
        return _seed.creationTime;
    }
}

- (id<WSBIP32Keyring>)safeExternalChain
{
    @synchronized (self) {
        WSExceptionCheckIllegal(_externalChain != nil, @"External chain is missing, probably unloaded with unloadSensitiveData and never reloaded");
        return _externalChain;
    }
}

- (id<WSBIP32Keyring>)safeInternalChain
{
    @synchronized (self) {
        WSExceptionCheckIllegal(_internalChain != nil, @"Internal chain is missing, probably unloaded with unloadSensitiveData and never reloaded");
        return _internalChain;
    }
}

#pragma mark Keys / Addresses

- (NSSet *)usedAddresses
{
    @synchronized (self) {
        return [_usedAddresses copy];
    }
}

- (WSKey *)privateKeyForAddress:(WSAddress *)address
{
    @synchronized (self) {
        WSExceptionCheckIllegal(address != nil, @"Nil address");

        const NSUInteger externalAccount = [_allExternalAddresses indexOfObject:address];
        if (externalAccount != NSNotFound) {
            return [self.safeExternalChain privateKeyForAccount:(uint32_t)externalAccount];
        }

        const NSUInteger internalAccount = [_allInternalAddresses indexOfObject:address];
        if (internalAccount != NSNotFound) {
            return [self.safeInternalChain privateKeyForAccount:(uint32_t)internalAccount];
        }

        return nil;
    }
}

- (WSPublicKey *)publicKeyForAddress:(WSAddress *)address
{
    @synchronized (self) {
        WSExceptionCheckIllegal(address != nil, @"Nil address");
    
        const NSUInteger externalAccount = [_allExternalAddresses indexOfObject:address];
        if (externalAccount != NSNotFound) {
            return [self.safeExternalChain publicKeyForAccount:(uint32_t)externalAccount];
        }
        
        const NSUInteger internalAccount = [_allInternalAddresses indexOfObject:address];
        if (internalAccount != NSNotFound) {
            return [self.safeInternalChain publicKeyForAccount:(uint32_t)internalAccount];
        }
        
        return nil;
    }
}

- (WSAddress *)receiveAddress
{
    @synchronized (self) {
//        return [[self.safeExternalChain publicKeyForAccount:_currentExternalAccount] addressWithParameters:self.parameters];
        return _allExternalAddresses[_currentExternalAccount];
    }
}

- (WSAddress *)changeAddress
{
    @synchronized (self) {
//        return [[self.safeInternalChain publicKeyForAccount:_currentInternalAccount] addressWithParameters:self.parameters];
        return _allInternalAddresses[_currentInternalAccount];
    }
}

- (NSOrderedSet *)allReceiveAddresses
{
    @synchronized (self) {
        return [_allExternalAddresses copy];
    }
}

- (NSOrderedSet *)allChangeAddresses
{
    @synchronized (self) {
        return [_allInternalAddresses copy];
    }
}

- (NSArray *)watchedReceiveAddresses
{
    @synchronized (self) {
        NSArray *addresses = [_allExternalAddresses array];
        return [addresses subarrayWithRange:NSMakeRange(_currentExternalAccount, addresses.count - _currentExternalAccount)];
    }
}

- (BOOL)isWalletAddress:(WSAddress *)address
{
    @synchronized (self) {
        return ([_allExternalAddresses containsObject:address] || [_allInternalAddresses containsObject:address]);
    }
}

#pragma mark History

- (NSArray *)allTransactions
{
    @synchronized (self) {
        return [_txs array];
    }
}

- (NSArray *)transactionsInRange:(NSRange)range
{
    @synchronized (self) {
        NSMutableArray *txs = [[NSMutableArray alloc] init];
        const NSUInteger last = MIN(range.location + range.length, _txs.count);
        for (NSUInteger i = range.location; i < last; ++i) {
            [txs addObject:_txs[i]];
        }
        return txs;
    }
}

- (uint64_t)receivedValueFromTransaction:(WSSignedTransaction *)transaction
{
    WSExceptionCheckIllegal(transaction != nil, @"Nil transaction");
    
    @synchronized (self) {
        uint64_t value = 0;
        for (WSTransactionOutput *output in transaction.outputs) {
            if ([self.usedAddresses containsObject:output.address]) {
                value += output.value;
            }
        }
        return value;
    }
}

- (uint64_t)sentValueByTransaction:(WSSignedTransaction *)transaction
{
    WSExceptionCheckIllegal(transaction != nil, @"Nil transaction");

    @synchronized (self) {
        uint64_t value = 0;
        for (WSSignedTransactionInput *input in transaction.inputs) {
            WSTransactionOutput *previousOutput = [self previousOutputFromInput:input];

            if ([self.usedAddresses containsObject:previousOutput.address]) {
                value += previousOutput.value;
            }
        }
        return value;
    }
}

- (int64_t)valueForTransaction:(WSSignedTransaction *)transaction
{
    WSExceptionCheckIllegal(transaction != nil, @"Nil transaction");

    @synchronized (self) {
        return [self receivedValueFromTransaction:transaction] - [self sentValueByTransaction:transaction];
    }
}

- (uint64_t)feeForTransaction:(WSSignedTransaction *)transaction
{
    WSExceptionCheckIllegal(transaction != nil, @"Nil transaction");
    
    @synchronized (self) {
        uint64_t fee = 0;

        for (WSSignedTransactionInput *input in transaction.inputs) {
            WSTransactionOutput *previousOutput = [self previousOutputFromInput:input];
            
            if (![self.usedAddresses containsObject:previousOutput.address]) {
                return UINT64_MAX;
            }
            fee += previousOutput.value;
        }

        for (WSTransactionOutput *output in transaction.outputs) {
            fee -= output.value;
        }

        return fee;
    }
}

- (BOOL)isInternalTransaction:(WSSignedTransaction *)transaction
{
    WSExceptionCheckIllegal(transaction != nil, @"Nil transaction");

    @synchronized (self) {
        for (WSTransactionOutput *output in transaction.outputs) {
            if (![self.usedAddresses containsObject:output.address]) {
                return NO;
            }
        }

        for (WSSignedTransactionInput *input in transaction.inputs) {
            WSTransactionOutput *previousOutput = [self previousOutputFromInput:input];

            if (![self.usedAddresses containsObject:previousOutput.address]) {
                return NO;
            }
        }

        return YES;
    }
}

- (uint64_t)balance
{
    @synchronized (self) {
        return _balance;
    }
}

- (uint64_t)confirmedBalance
{
    @synchronized (self) {
        return _confirmedBalance;
    }
}

- (WSTransactionMetadata *)metadataForTransactionId:(WSHash256 *)txId
{
    @synchronized (self) {
        WSExceptionCheckIllegal(txId != nil, @"Nil txId");
        
        return _metadataByTxId[txId];
    }
}

#pragma mark Spending

- (WSTransactionOutput *)previousOutputFromInput:(WSSignedTransactionInput *)input
{
    WSSignedTransaction *previousTx = _txsById[input.outpoint.txId];
    if (!previousTx) {
        return nil;
    }
    return [previousTx outputAtIndex:input.outpoint.index];
}

- (WSTransactionBuilder *)buildTransactionToAddress:(WSAddress *)address forValue:(uint64_t)value fee:(uint64_t)fee error:(NSError *__autoreleasing *)error
{
    @synchronized (self) {
        WSExceptionCheckIllegal(address != nil, @"Nil address");
        WSExceptionCheckIllegal(value > 0, @"Zero value");

        WSTransactionOutput *output = [[WSTransactionOutput alloc] initWithAddress:address value:value];
        return [self buildTransactionWithOutputs:[NSOrderedSet orderedSetWithObject:output] fee:fee error:error];
    }
}

- (WSTransactionBuilder *)buildTransactionToAddresses:(NSArray *)addresses forValues:(NSArray *)values fee:(uint64_t)fee error:(NSError *__autoreleasing *)error
{
    @synchronized (self) {
        WSExceptionCheckIllegal(addresses.count > 0, @"Empty addresses");
        WSExceptionCheckIllegal(values.count == addresses.count, @"Values count must match addresses count");
        
        uint64_t totalValue = 0;
        for (NSNumber *value in values) {
            totalValue += [value unsignedLongLongValue];
        }
        WSExceptionCheckIllegal(totalValue > 0, @"Zero total value");

        NSMutableOrderedSet *outputs = [[NSMutableOrderedSet alloc] initWithCapacity:values.count];
        NSUInteger i = 0;
        for (NSNumber *valueNumber in values) {
            const uint64_t value = [valueNumber unsignedLongLongValue];
            WSAddress *address = addresses[i];
            
            WSTransactionOutput *output = [[WSTransactionOutput alloc] initWithAddress:address value:value];
            [outputs addObject:output];
            
            ++i;
        }
        return [self buildTransactionWithOutputs:outputs fee:fee error:error];
    }
}

- (WSTransactionBuilder *)buildTransactionWithOutputs:(NSOrderedSet *)outputs fee:(uint64_t)fee error:(NSError *__autoreleasing *)error
{
    @synchronized (self) {
        WSExceptionCheckIllegal(outputs.count > 0, @"Empty outputs");

        if (self.balance == 0) {
            WSErrorSet(error, WSErrorCodeInsufficientFunds, @"Wallet is empty");
            return nil;
        }

        WSTransactionBuilder *builder = [[WSTransactionBuilder alloc] init];
        
        uint64_t needed = 0;
        for (WSTransactionOutput *output in outputs) {
            [builder addOutput:output];
            needed += output.value;
        }
        uint64_t gathered = 0;
        uint64_t effectiveFee = 0;

        for (WSTransactionOutPoint *utxo in _unspentOutpoints) {
            WSSignedTransaction *unspentTx = _txsById[utxo.txId];
            NSAssert(unspentTx, @"Unspent outputs must only point to wallet transactions, or txsById wasn't rebuilt correctly");
            
            WSSignableTransactionInput *input = [[WSSignableTransactionInput alloc] initWithPreviousTransaction:unspentTx
                                                                                                    outputIndex:utxo.index];

            [builder addSignableInput:input];
            gathered += input.value;
            
            // add change bytes added below
            const uint64_t standardFee = [builder standardFeeWithExtraOutputs:1];
            effectiveFee = MAX(fee, standardFee);
            if ((gathered == needed + effectiveFee) || (gathered >= needed + effectiveFee + WSTransactionMinOutValue)) {
                break;
            }
        }
        
        if (gathered < needed + effectiveFee) {
            WSErrorSetUserInfo(error, WSErrorCodeInsufficientFunds, @{WSErrorFeeKey: @(effectiveFee)},
                               @"Insufficient funds (%llu < %llu + fee(%llu))", gathered, needed, effectiveFee);

            return nil;
        }
        
        const uint64_t change = gathered - (needed + effectiveFee);
        if (change >= WSTransactionMinOutValue) {
            WSTransactionOutput *output = [[WSTransactionOutput alloc] initWithAddress:self.changeAddress value:change];
            [builder addOutput:output];
        }
        else {
            // dust change, lost as additional fee
        }
    
        return builder;
    }
}

- (WSTransactionBuilder *)buildSweepTransactionToAddress:(WSAddress *)address fee:(uint64_t)fee error:(NSError *__autoreleasing *)error
{
    @synchronized (self) {
        WSExceptionCheckIllegal(address != nil, @"Nil address");

        if (self.balance == 0) {
            WSErrorSet(error, WSErrorCodeInsufficientFunds, @"Wallet is empty");
            return nil;
        }
        
        WSTransactionBuilder *builder = [[WSTransactionBuilder alloc] init];
        uint64_t gathered = 0;

        for (WSTransactionOutPoint *utxo in _unspentOutpoints) {
            WSSignedTransaction *unspentTx = _txsById[utxo.txId];
            NSAssert(unspentTx, @"Unspent outputs must only point to wallet transactions, or txsById wasn't rebuilt correctly");
            
            WSSignableTransactionInput *input = [[WSSignableTransactionInput alloc] initWithPreviousTransaction:unspentTx
                                                                                                    outputIndex:utxo.index];

            [builder addSignableInput:input];
            gathered += input.value;
        }
        
        // we know by construction that we're adding typical inputs/outputs, so fee is predictable
        const NSUInteger estimatedTxSize = WSTransactionTypicalSize(builder.signableInputs.count, 1);
        const uint64_t effectiveFee = MAX(fee, WSTransactionStandardRelayFee(estimatedTxSize));
        
        WSTransactionOutput *output = [[WSTransactionOutput alloc] initWithAddress:address value:(gathered - effectiveFee)];
        [builder addOutput:output];
        
        NSAssert(gathered == self.balance, @"Transaction doesn't spend full balance (%llu != %llu)",
                 gathered, self.balance);
        
        return builder;
    }
}

- (WSSignedTransaction *)signedTransactionWithBuilder:(WSTransactionBuilder *)builder error:(NSError *__autoreleasing *)error
{
    @synchronized (self) {
        NSMutableDictionary *keys = [[NSMutableDictionary alloc] initWithCapacity:builder.signableInputs.count];

        for (WSSignableTransactionInput *input in builder.signableInputs) {
            WSAddress *inputAddress = input.address;
            WSKey *key = [self privateKeyForAddress:inputAddress];
            if (!key) {
                const NSUInteger index = keys.count;
                WSErrorSetUserInfo(error, WSErrorCodeSignature, @{WSErrorInputAddressKey: inputAddress},
                                   @"Missing key for input address %@", index, inputAddress);

                return nil;
            }
            keys[inputAddress] = key;
        }
        
        return [builder signedTransactionWithInputKeys:keys error:error];
    }
}

#pragma mark Serialization

- (void)setPath:(NSString *)path
{
    @synchronized (self) {
        _path = path;
    }
}

- (BOOL)saveToPath:(NSString *)path
{
    WSExceptionCheckIllegal(path != nil, @"Nil path");
    
    @synchronized (self) {
        if (![NSKeyedArchiver archiveRootObject:self toFile:path]) {
            return NO;
        }
        _path = path;
        return YES;
    }
}

- (BOOL)save
{
    WSExceptionCheckIllegal(_path != nil, @"No implicit path set, call saveToPath: first");
    
    @synchronized (self) {
        return [self saveToPath:_path];
    }
}

+ (instancetype)loadFromPath:(NSString *)path parameters:(id<WSParameters>)parameters seed:(WSSeed *)seed
{
    return [self loadFromPath:path parameters:parameters seed:seed chainsPath:WSHDWalletDefaultChainsPath];
}

+ (instancetype)loadFromPath:(NSString *)path parameters:(id<WSParameters>)parameters seed:(WSSeed *)seed chainsPath:(NSString *)chainsPath
{
    WSExceptionCheckIllegal(path != nil, @"Nil path");
    WSExceptionCheckIllegal(seed != nil, @"Nil seed");
    WSExceptionCheckIllegal(chainsPath != nil, @"Nil chainsPath");

    @synchronized (self) {
        WSHDWallet *wallet = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
        if (![wallet isKindOfClass:[WSHDWallet class]]) {
            return nil;
        }

        // safe check on singletons
        WSExceptionCheckIllegal(parameters == wallet.parameters,
                                @"Wallet created on '%@' network (expected: '%@')",
                                WSNetworkTypeString([wallet.parameters networkType]),
                                WSNetworkTypeString([parameters networkType]));

        wallet.path = path;
        [wallet loadSensitiveDataWithSeed:seed chainsPath:chainsPath];
        [wallet rebuildTransientStructures];
        return wallet;
    }
}

- (void)loadSensitiveDataWithSeed:(WSSeed *)seed chainsPath:(NSString *)chainsPath
{
    NSParameterAssert(seed);
    NSParameterAssert(chainsPath);
    
    NSAssert(self.parameters, @"Parameters not set (check init* and loadFromPath*)");

    @synchronized (self) {
        _seed = seed;
        WSHDKeyring *keyring = [[WSHDKeyring alloc] initWithParameters:self.parameters data:[_seed derivedKeyData]];
        _externalChain = [keyring keyringAtPath:[NSString stringWithFormat:@"%@/0", chainsPath]];
        _internalChain = [keyring keyringAtPath:[NSString stringWithFormat:@"%@/1", chainsPath]];
    }
}

- (void)rebuildTransientStructures
{
    @synchronized (self) {
        NSAssert(self.seed, @"Nil seed, call loadSensitiveDataWithSeed: first");
        
        const NSTimeInterval rebuildStartTime = [NSDate timeIntervalSinceReferenceDate];
        
        _txsById = [[NSMutableDictionary alloc] initWithCapacity:_txs.count];
        for (WSSignedTransaction *tx in _txs) {
            _txsById[tx.txId] = tx;
        }
        
        [self recalculateSpendsAndBalance];
        [self generateAddressesWithLookAhead:(4 * _gapLimit) forced:YES];
        
        const NSTimeInterval rebuildTime = [NSDate timeIntervalSinceReferenceDate] - rebuildStartTime;
        DDLogDebug(@"Rebuilt wallet transient structures in %.3fs", rebuildTime);
    }
}

- (void)unloadSensitiveData
{
    @synchronized (self) {
        _seed = nil;
        _externalChain = nil;
        _internalChain = nil;
    }
}

#pragma mark WSSynchronizableWallet

- (uint32_t)earliestKeyTimestamp
{
    @synchronized (self) {
        return (NSTimeIntervalSince1970 + self.creationTime);
    }
}

- (BOOL)generateAddressesIfNeeded
{
    return [self generateAddressesWithLookAhead:0 forced:NO];
}

- (BOOL)generateAddressesWithLookAhead:(NSUInteger)lookAhead
{
    return [self generateAddressesWithLookAhead:lookAhead forced:NO];
}

- (BOOL)generateAddressesWithLookAhead:(NSUInteger)lookAhead forced:(BOOL)forced
{
    @synchronized (self) {
        BOOL didGenerate = [self generateAddressesWithLookAhead:lookAhead internal:NO forced:forced];
        didGenerate |= [self generateAddressesWithLookAhead:lookAhead internal:YES forced:forced];

        return didGenerate;
    }
}

- (BOOL)generateAddressesWithLookAhead:(NSUInteger)lookAhead internal:(BOOL)internal forced:(BOOL)forced
{
    @synchronized (self) {
        id<WSBIP32Keyring> targetChain = nil;
        NSMutableOrderedSet *targetAddresses = nil;
        uint32_t *currentAccount = NULL;

        if (internal) {
            targetChain = self.safeInternalChain;
            targetAddresses = _allInternalAddresses;
            currentAccount = &_currentInternalAccount;
        }
        else {
            targetChain = self.safeExternalChain;
            targetAddresses = _allExternalAddresses;
            currentAccount = &_currentExternalAccount;
        }

//        NSAssert(targetAddresses.count > 0, @"Wallet must have at least 1 account");
        
        __block NSUInteger accountOfFirstUnusedAddress = targetAddresses.count;
        __block NSUInteger numberOfUsedAddresses = 0;
        
        [targetAddresses enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            WSAddress *address = obj;
            if ([self.usedAddresses containsObject:address]) {
                numberOfUsedAddresses = idx + 1;
                *stop = YES;
            }
            else {
                accountOfFirstUnusedAddress = idx;
            }
        }];
        
        *currentAccount = (uint32_t)accountOfFirstUnusedAddress;
        
        DDLogDebug(@"Used %u/%u accounts", numberOfUsedAddresses, targetAddresses.count);
        DDLogDebug(@"Current account set to first unused account (%u)", *currentAccount);
        
        const NSUInteger watchedCount = _gapLimit + lookAhead;
        if (forced) {
            DDLogDebug(@"Forcing generation of %u watched addresses", watchedCount);
        }
        else {
            const NSUInteger available = targetAddresses.count - numberOfUsedAddresses;
            if (available >= watchedCount) {
                DDLogDebug(@"Still more available addresses than watched (%u >= %u), skipping generation",
                           available, watchedCount);

                return NO;
            }
            else {
                DDLogDebug(@"All available addresses were used, reestablish watched addresses (%u)", watchedCount);
            }
        }
        
        const NSTimeInterval generationStartTime = [NSDate timeIntervalSinceReferenceDate];
        
        const NSUInteger firstGenAccount = targetAddresses.count;
        const NSUInteger lastGenAccount = accountOfFirstUnusedAddress + watchedCount; // excluded
        for (NSUInteger i = firstGenAccount; i < lastGenAccount; ++i) {
            WSAddress *address = [[targetChain publicKeyForAccount:(uint32_t)i] addressWithParameters:self.parameters];
            [targetAddresses addObject:address];
        }
        
        const NSUInteger expectedWatchedCount = lastGenAccount - *currentAccount;
        NSAssert(expectedWatchedCount == watchedCount, @"Number of watched addresses must be equal to gap limit plus look-ahead (%u != %u)",
                 expectedWatchedCount, watchedCount);
        
        const NSTimeInterval generationTime = [NSDate timeIntervalSinceReferenceDate] - generationStartTime;
        DDLogDebug(@"Generated accounts in %.3fs: %u -> %u (watched: %u)",
                   generationTime, firstGenAccount, lastGenAccount, watchedCount);
        
        return YES;
    }
}

#if (WASPV_WALLET_FILTER == WASPV_WALLET_FILTER_PUBKEYS)

- (WSBloomFilter *)bloomFilterWithParameters:(WSBIP37FilterParameters *)parameters
{
    @synchronized (self) {
        WSExceptionCheckIllegal(parameters != nil, @"Nil parameters");
        
        NSUInteger capacity = 2 * (_allExternalAddresses.count + _allInternalAddresses.count);
        
        // heuristic
        if (capacity < 200) {
            capacity *= 1.5;
        }
        else {
            capacity += 100;
        }
        
        WSMutableBloomFilter *filter = [[WSMutableBloomFilter alloc] initWithParameters:parameters capacity:capacity];
        
        // number of watched accounts is based on external chain
        NSArray *chains = @[self.safeExternalChain, self.safeInternalChain];
        NSArray *counts = @[@(_allExternalAddresses.count), @(_allInternalAddresses.count)];
        
        for (NSUInteger i = 0; i < 2; ++i) {
            id<WSBIP32Keyring> chain = chains[i];
            const uint32_t numberOfWatchedAddresses = [counts[i] unsignedIntegerValue];
            
            for (uint32_t account = 0; account < numberOfWatchedAddresses; ++account) {
                WSPublicKey *pubKey = [chain publicKeyForAccount:account];
                
                // public keys match inputs scriptSig (sent money)
                [filter insertData:[pubKey encodedData]];
                
                // addresses match outputs scriptPubKey (received money)
                [filter insertData:[pubKey hash160].data];
            }
        }
        
        return filter;
    }
}

- (BOOL)isCoveredByBloomFilter:(WSBloomFilter *)bloomFilter
{
    WSExceptionCheckIllegal(bloomFilter != nil, @"Nil bloomFilter");
    
    @synchronized (self) {
        NSArray *chains = @[self.safeExternalChain, self.safeInternalChain];
        NSArray *counts = @[@(_allExternalAddresses.count), @(_allInternalAddresses.count)];
        
        for (NSUInteger i = 0; i < 2; ++i) {
            id<WSBIP32Keyring> chain = chains[i];
            const uint32_t numberOfWatchedAddresses = [counts[i] unsignedIntegerValue];
            
            for (uint32_t account = 0; account < numberOfWatchedAddresses; ++account) {
                WSPublicKey *pubKey = [chain publicKeyForAccount:account];

                if (![bloomFilter containsData:[pubKey encodedData]]) {
                    return NO;
                }
                if (![bloomFilter containsData:[pubKey hash160].data]) {
                    return NO;
                }
            }
        }
    }
    return YES;
}

#elif (WASPV_WALLET_FILTER == WASPV_WALLET_FILTER_UNSPENT)

- (WSBloomFilter *)bloomFilterWithParameters:(WSBIP37FilterParameters *)parameters
{
    @synchronized (self) {
        WSExceptionCheckIllegal(parameters != nil, @"Nil parameters");
        
        NSUInteger capacity = _allExternalAddresses.count + _allInternalAddresses.count + _unspentOutpoints.count;
        
        // heuristic
        if (capacity < 200) {
            capacity *= 1.5;
        }
        else {
            capacity += 100;
        }
        
        WSMutableBloomFilter *filter = [[WSMutableBloomFilter alloc] initWithParameters:parameters capacity:capacity];
        
        // add addresses to watch for any tx receiveing money to the wallet
        for (WSAddress *address in _allExternalAddresses) {
            [filter insertAddress:address];
        }
        for (WSAddress *address in _allInternalAddresses) {
            [filter insertAddress:address];
        }
        
        // add unspent outputs to watch for any tx sending money from the wallet
        for (WSTransactionOutPoint *unspent in _unspentOutpoints) {
            [filter insertUnspent:unspent];
        }
        
        return filter;
    }
}

- (BOOL)isCoveredByBloomFilter:(WSBloomFilter *)bloomFilter
{
    for (WSAddress *address in _allExternalAddresses) {
        if (![bloomFilter containsAddress:address]) {
            return NO;
        }
    }
    for (WSAddress *address in _allInternalAddresses) {
        if (![bloomFilter containsAddress:address]) {
            return NO;
        }
    }
    for (WSTransactionOutPoint *unspent in _unspentOutpoints) {
        if (![bloomFilter containsUnspent:unspent]) {
            return NO;
        }
    }
    return YES;
}

#else

- (WSBloomFilter *)bloomFilterWithParameters:(WSBIP37FilterParameters *)parameters
{
    @synchronized (self) {
        WSExceptionCheckIllegal(parameters != nil, @"Nil parameters");
        
        return [[WSBloomFilter alloc] initWithFullMatch];
    }
}

- (BOOL)isCoveredByBloomFilter:(WSBloomFilter *)bloomFilter
{
    return YES;
}

#endif

- (BOOL)isRelevantTransaction:(WSSignedTransaction *)transaction
{
    return [self isRelevantTransaction:transaction savingReceivingAddresses:nil];
}

- (BOOL)isRelevantTransaction:(WSSignedTransaction *)transaction savingReceivingAddresses:(NSMutableSet *)receivingAddresses
{
#ifdef WASPV_TEST_DUMMY_TXS
    return YES;
#endif
    
    @synchronized (self) {
        WSExceptionCheckIllegal(transaction != nil, @"Nil transaction");
        
        //
        // the major weakness is that the test would drop new unconfirmed transactions received during
        // sync because spent transaction has not been registered yet (previous transaction in outpoint
        // not found in wallet). the missed transaction should be recovered from mempool after download
        // finish or after it's received in a block.
        //
        // by the way, say we're not synced and we receive an inv for a high block with a transaction we
        // know to be relevant to us as it spends money from another transaction of ours. the block is
        // requested and stored into the blockchain as an orphan, but the transaction spends inputs from
        // an older transactions we're still not aware of, so the relevacy test fails and the transaction
        // is dropped.
        //
        // later on we catch up with the blockchain and the orphan gets eventually connected. now
        // mempool is requested but the transaction is not there anymore since it was included in a
        // block. we actually own the block, so it won't be requested again.
        //
        // the transaction is lost unless a new registration attempt is done for all the transactions
        // from blocks added to the blockchain. following blockchain extension guarantees that
        // even in the worst case transactions are registered in ascending height.
        //
        // it's worth noting that most of the time the wallet will already have the transactions because
        // of the 'tx' messages preceeding the block.
        //
        
        BOOL isRelevant = NO;
        
        //
        // inputs relevancy test relies on transaction order, and we know that if a transaction spends another
        // one in the same block, the spending transaction always comes AFTER the input transaction
        //
        // http://bitcoin.stackexchange.com/questions/3870/what-order-do-transactions-appear-in-a-block-is-it-up-to-the-miner
        //
        
        // relevant if inputs spend wallet transaction
        for (WSSignedTransactionInput *input in transaction.inputs) {
            if (_txsById[input.outpoint.txId]) {
                isRelevant = YES;
                break;
            }
        }
        
        // if transaction is relevant from previous checks, receivingAddresses must be filled anyway (if not nil)
        if (!isRelevant || receivingAddresses) {
            NSSet *txOutputAddresses = [transaction outputAddresses];
            
            // relevant if outputs contain at least one wallet address
            NSMutableOrderedSet *walletReceivingAddresses = [NSMutableOrderedSet orderedSetWithSet:txOutputAddresses];

#warning TODO: wallet, optimize this
            NSMutableOrderedSet *allAddresses = [_allExternalAddresses mutableCopy];
            [allAddresses unionOrderedSet:_allInternalAddresses];
            [walletReceivingAddresses intersectOrderedSet:allAddresses];

            if (walletReceivingAddresses.count > 0) {
                isRelevant = YES;
                [receivingAddresses addObjectsFromArray:[walletReceivingAddresses array]];
            }
        }
        
        return isRelevant;
    }
}

- (BOOL)registerTransaction:(WSSignedTransaction *)transaction didGenerateNewAddresses:(BOOL *)didGenerateNewAddresses
{
    return [self registerTransaction:transaction didGenerateNewAddresses:didGenerateNewAddresses batch:NO];
}

- (BOOL)unregisterTransaction:(WSSignedTransaction *)transaction
{
    return [self unregisterTransaction:transaction batch:NO];
}

- (NSDictionary *)registerBlock:(WSStorableBlock *)block
{
    return [self registerBlock:block batch:NO];
}

- (NSDictionary *)unregisterBlock:(WSStorableBlock *)block
{
    return [self unregisterBlock:block batch:NO];
}

- (BOOL)registerTransaction:(WSSignedTransaction *)transaction didGenerateNewAddresses:(BOOL *)didGenerateNewAddresses batch:(BOOL)batch
{
    @synchronized (self) {
        WSExceptionCheckIllegal(transaction != nil, @"Nil transaction");
        
        if (_txsById[transaction.txId]) {
            DDLogVerbose(@"Ignored wallet transaction %@ (already registered)", transaction.txId);
            return NO;
        }
        if (![self isRelevantTransaction:transaction savingReceivingAddresses:_usedAddresses]) {
            DDLogVerbose(@"Ignored wallet transaction %@ (not relevant)", transaction.txId);
            return NO;
        }
        if (didGenerateNewAddresses) {
            *didGenerateNewAddresses = NO;
        }
        
        [_txs insertObject:transaction atIndex:0];
        _txsById[transaction.txId] = transaction;
        _metadataByTxId[transaction.txId] = [[WSTransactionMetadata alloc] initWithNoParentBlock];
        
        if (!batch) {
            [self sortTransactions];
            [self recalculateSpendsAndBalance];
            if (self.shouldAutosave) {
                [self save];
            }

            [self notifyWithName:WSWalletDidRegisterTransactionNotification userInfo:@{WSWalletTransactionKey: transaction}];
        }
        
        const uint32_t previousExternalAccount = _currentExternalAccount;
        const uint32_t previousInternalAccount = _currentInternalAccount;

        const BOOL didGenerate = [self generateAddressesIfNeeded];
        if (didGenerateNewAddresses) {
            *didGenerateNewAddresses = didGenerate;
        }
        if (!batch && ((_currentExternalAccount != previousExternalAccount) || (_currentInternalAccount != previousInternalAccount))) {
            [self notifyWithName:WSWalletDidUpdateAddressesNotification userInfo:nil];
        }
        
        return YES;
    }
}

- (BOOL)unregisterTransaction:(WSSignedTransaction *)transaction batch:(BOOL)batch
{
    @synchronized (self) {
        if (!_txsById[transaction.txId]) {
            return NO;
        }
        
        [_metadataByTxId removeObjectForKey:transaction.txId];
        [_txsById removeObjectForKey:transaction.txId];
        [_txs removeObject:transaction];
        
        if (!batch) {
            [self sortTransactions];
            [self recalculateSpendsAndBalance];
            if (self.shouldAutosave) {
                [self save];
            }

            [self notifyWithName:WSWalletDidUnregisterTransactionNotification userInfo:@{WSWalletTransactionKey: transaction}];
        }
        
        return YES;
    }
}

- (NSDictionary *)registerBlock:(WSStorableBlock *)block batch:(BOOL)batch
{
    NSMutableDictionary *updates = nil;
    
    @synchronized (self) {
        WSExceptionCheckIllegal(block != nil, @"Nil block");
        
        for (WSSignedTransaction *tx in block.transactions) {
            WSTransactionMetadata *metadata = _metadataByTxId[tx.txId];
            if (!metadata || [block.blockId isEqual:metadata.parentBlockId]) {
                continue;
            }
            
            metadata = [[WSTransactionMetadata alloc] initWithParentBlock:block];
            _metadataByTxId[tx.txId] = metadata;
            
            if (!updates) {
                updates = [[NSMutableDictionary alloc] init];
            }
            updates[tx.txId] = metadata;
        }
    
        if (!batch && updates) {
            if (self.shouldAutosave) {
                [self save];
            }

            [self notifyWithName:WSWalletDidUpdateTransactionsMetadataNotification userInfo:@{WSWalletTransactionsMetadataKey: updates}];
        }
        return updates;
    }
}

- (NSDictionary *)unregisterBlock:(WSStorableBlock *)block batch:(BOOL)batch
{
    NSMutableDictionary *updates = nil;
    
    @synchronized (self) {
        WSExceptionCheckIllegal(block != nil, @"Nil block");
        
        for (WSSignedTransaction *tx in block.transactions) {
            WSTransactionMetadata *metadata = _metadataByTxId[tx.txId];
            if (!metadata) {
                continue;
            }
            
            metadata = [[WSTransactionMetadata alloc] initWithNoParentBlock];
            _metadataByTxId[tx.txId] = metadata;
            
            if (!updates) {
                updates = [[NSMutableDictionary alloc] init];
            }
            updates[tx.txId] = metadata;
        }
    
        if (!batch && updates) {
            if (self.shouldAutosave) {
                [self save];
            }

            [self notifyWithName:WSWalletDidUpdateTransactionsMetadataNotification userInfo:@{WSWalletTransactionsMetadataKey: updates}];
        }
        return updates;
    }
}

- (void)reorganizeWithOldBlocks:(NSArray *)oldBlocks newBlocks:(NSArray *)newBlocks didGenerateNewAddresses:(BOOL *)didGenerateNewAddresses
{
    @synchronized (self) {
        WSExceptionCheckIllegal(oldBlocks.count > 0, @"Empty oldBlocks");
        WSExceptionCheckIllegal(newBlocks.count > 0, @"Empty newBlocks");
        
        if (didGenerateNewAddresses) {
            *didGenerateNewAddresses = NO;
        }
        
        NSMutableDictionary *unregisteredUpdates = [[NSMutableDictionary alloc] init];;
        NSMutableDictionary *updates = [[NSMutableDictionary alloc] init];;
        
        for (WSStorableBlock *block in oldBlocks) {
            [unregisteredUpdates addEntriesFromDictionary:[self unregisterBlock:block batch:YES]];
        }
        
        for (WSStorableBlock *block in [newBlocks reverseObjectEnumerator]) {
            for (WSSignedTransaction *transaction in block.transactions) {
                BOOL txDidGenerateNewAddresses = NO;
                [self registerTransaction:transaction didGenerateNewAddresses:&txDidGenerateNewAddresses];
                
                if (didGenerateNewAddresses) {
                    *didGenerateNewAddresses |= txDidGenerateNewAddresses;
                }
            }
            
            [updates addEntriesFromDictionary:[self registerBlock:block batch:YES]];
        }
        
        [self sortTransactions];
        [self recalculateSpendsAndBalance];
        
        // remove transactions that got reconfirmed in new blocks
        [unregisteredUpdates removeObjectsForKeys:[updates allKeys]];
        
        // merge all updates
        [updates addEntriesFromDictionary:unregisteredUpdates];
        
        if (updates.count > 0) {
            if (self.shouldAutosave) {
                [self save];
            }

            [self notifyWithName:WSWalletDidUpdateTransactionsMetadataNotification userInfo:@{WSWalletTransactionsMetadataKey: updates}];
        }
    }
}

- (void)sortTransactions
{
    @synchronized (self) {
        [_txs sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            WSSignedTransaction *tx1 = obj1;
            WSSignedTransaction *tx2 = obj2;
            WSTransactionMetadata *m1 = _metadataByTxId[tx1.txId];
            WSTransactionMetadata *m2 = _metadataByTxId[tx2.txId];
            
            if (m1.height > m2.height) {
                return NSOrderedAscending;
            }
            else if (m1.height < m2.height) {
                return NSOrderedDescending;
            }
            
            // same height, dependent first
            if ([tx1.inputTxIds containsObject:tx2.txId]) {
                return NSOrderedAscending;
            }
            else if ([tx2.inputTxIds containsObject:tx1.txId]) {
                return NSOrderedDescending;
            }
            
            return NSOrderedSame;
        }];
    }
}

- (void)recalculateSpendsAndBalance
{
    @synchronized (self) {
        NSMutableSet *spentOutpoints = [[NSMutableSet alloc] init];
        NSMutableOrderedSet *unspentOutpoints = [[NSMutableOrderedSet alloc] init];
        NSMutableSet *invalidTxIds = [[NSMutableSet alloc] init];
        
        for (WSSignedTransaction *tx in [_txs reverseObjectEnumerator]) {
            NSMutableSet *spentTxOutpoints = [[NSMutableSet alloc] init];
            
            // inputs are spent outputs
            for (WSSignedTransactionInput *input in tx.inputs) {
                [spentTxOutpoints addObject:input.outpoint];
            }
            
            // if tx is unconfirmed, invalidate on (double-spent input OR input from invalid tx output)
            WSTransactionMetadata *metadata = _metadataByTxId[tx.txId];
            if (!metadata.parentBlockId &&
                ([spentTxOutpoints intersectsSet:spentOutpoints] || [tx.inputTxIds intersectsSet:invalidTxIds])) {
                
                [invalidTxIds addObject:tx.txId];
                continue;
            }
            
            [spentOutpoints unionSet:spentTxOutpoints];
            
            // own outputs are unspent outputs
            uint32_t index = 0;
            for (WSTransactionOutput *output in tx.outputs) {
                WSTransactionOutPoint *outpoint = [WSTransactionOutPoint outpointWithParameters:self.parameters txId:tx.txId index:index];
                if ([self isWalletAddress:output.address] && ![spentOutpoints containsObject:outpoint]) {
                    [unspentOutpoints addObject:outpoint];
                }
                ++index;
            }
        }
        
        [unspentOutpoints minusSet:spentOutpoints];
        
        uint64_t balance = 0;
        uint64_t confirmedBalance = 0;
        for (WSTransactionOutPoint *outpoint in unspentOutpoints) {
            WSSignedTransaction *tx = _txsById[outpoint.txId];
            WSTransactionOutput *output = [tx outputAtIndex:outpoint.index];
            
            balance += output.value;

            WSTransactionMetadata *metadata = _metadataByTxId[tx.txId];
            if (metadata.parentBlockId) {
                confirmedBalance += output.value;
            }
        }
        
        _invalidTxIds = invalidTxIds;
        _spentOutpoints = spentOutpoints;
        _unspentOutpoints = unspentOutpoints;

        BOOL shouldNotify = NO;
        if (balance != _balance) {
            _balance = balance;
            shouldNotify = YES;
        }
        if (confirmedBalance != _confirmedBalance) {
            _confirmedBalance = confirmedBalance;
            shouldNotify = YES;
        }
        if (shouldNotify) {
            [self notifyWithName:WSWalletDidUpdateBalanceNotification userInfo:nil];
        }
    }
}

- (void)removeAllTransactions
{
    @synchronized (self) {
        DDLogDebug(@"Removing %u wallet transactions", _txs.count);
        
        [_txs removeAllObjects];
        [_txsById removeAllObjects];
        [_usedAddresses removeAllObjects];
        [_metadataByTxId removeAllObjects];
        
        [self recalculateSpendsAndBalance];

        NSAssert(self.allTransactions.count == 0, @"Expected zero transactions");
        NSAssert(_balance == 0ULL, @"Expected zero balance after forgetting all transactions");
    }
}

#pragma mark Utils

- (void)notifyWithName:(NSString *)name userInfo:(NSDictionary *)userInfo
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:name object:self userInfo:userInfo];
    });
}

#pragma mark WSIndentableDescription

- (NSString *)descriptionWithIndent:(NSUInteger)indent
{
    NSMutableArray *tokens = [[NSMutableArray alloc] init];

    @synchronized (self) {
        [tokens addObject:[NSString stringWithFormat:@"created = %@", [NSDate dateWithTimeIntervalSinceReferenceDate:self.creationTime]]];
        [tokens addObject:[NSString stringWithFormat:@"receive = %@", self.receiveAddress]];
        [tokens addObject:[NSString stringWithFormat:@"transactions = %u", _txs.count]];
        [tokens addObject:[NSString stringWithFormat:@"balance = %llu", _balance]];
    }

    return [NSString stringWithFormat:@"{%@}", WSStringDescriptionFromTokens(tokens, indent)];
}

#pragma mark AutoCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if ((self = [super initWithCoder:aDecoder])) {
        self.parameters = WSParametersForNetworkType(_networkType);
    }
    return self;
}

+ (NSDictionary *)codableProperties
{
    return @{@"_networkType": [NSNumber class],
             @"_gapLimit": [NSNumber class],
             @"_allExternalAddresses": [NSMutableOrderedSet class],
             @"_allInternalAddresses": [NSMutableOrderedSet class],
             @"_currentExternalAccount": [NSNumber class],
             @"_currentInternalAccount": [NSNumber class],
             @"_txs": [NSMutableOrderedSet class],
             @"_usedAddresses": [NSMutableSet class],
             @"_metadataByTxId": [NSMutableDictionary class]};
}

@end
