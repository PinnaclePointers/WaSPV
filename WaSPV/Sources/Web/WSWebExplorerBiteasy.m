//
//  WSWebExplorerBiteasy.m
//  WaSPV
//
//  Created by Davide De Rosa on 04/09/14.
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

#import "WSWebExplorerBiteasy.h"
#import "WSJSONClient.h"
#import "WSKey.h"
#import "WSBIP38.h"
#import "WSAddress.h"
#import "WSTransactionInput.h"
#import "WSTransactionOutPoint.h"
#import "WSTransactionOutput.h"
#import "WSTransaction.h"
#import "WSConfig.h"
#import "WSMacros.h"
#import "WSErrors.h"

static NSString *const          WSWebExplorerBiteasyBaseFormat              = @"https://www.biteasy.com/%@/";
static NSString *const          WSWebExplorerBiteasyNetworkMain             = @"blockchain";
static NSString *const          WSWebExplorerBiteasyNetworkTest             = @"testnet";

static NSString *const          WSWebExplorerBiteasyObjectPathFormat        = @"%@/%@";
static NSString *const          WSWebExplorerBiteasyObjectBlock             = @"blocks";
static NSString *const          WSWebExplorerBiteasyObjectTransaction       = @"transactions";

static NSString *const          WSWebExplorerBiteasyBaseAPIFormat           = @"https://api.biteasy.com/%@/v1/";
static NSString *const          WSWebExplorerBiteasyUnspentPathFormat       = @"addresses/%@/unspent-outputs?page=%u&per_page=%u";
static const NSUInteger         WSWebExplorerBiteasyUnspentPerPage          = 100;
static const NSTimeInterval     WSWebExplorerBiteasyYieldInterval           = 1.0;

@interface WSWebExplorerBiteasy ()

@property (nonatomic, assign) WSNetworkType networkType;

- (void)fetchUnspentInputsForAddress:(WSAddress *)address
                                page:(NSUInteger)page
                             handler:(void (^)(WSSignableTransactionInput *, BOOL, BOOL *))handler
                          completion:(void (^)())completion
                             failure:(void (^)(NSError *))failure;

@end

@implementation WSWebExplorerBiteasy

- (NSString *)networkName
{
    switch (self.networkType) {
        case WSNetworkTypeMain: {
            return WSWebExplorerBiteasyNetworkMain;
        }
        case WSNetworkTypeTestnet3: {
            return WSWebExplorerBiteasyNetworkTest;
        }
        case WSNetworkTypeRegtest: {
            WSExceptionRaiseUnsupported(@"Regtest network is not supported");
        }
    }
    return nil;
}

- (NSString *)objectForType:(WSWebExplorerObjectType)type
{
    switch (type) {
        case WSWebExplorerObjectTypeBlock: {
            return WSWebExplorerBiteasyObjectBlock;
        }
        case WSWebExplorerObjectTypeTransaction: {
            return WSWebExplorerBiteasyObjectTransaction;
        }
    }
    return nil;
}

#pragma mark WSWebExplorer

- (NSString *)provider
{
    return WSWebExplorerProviderBiteasy;
}

- (NSURL *)URLForObjectType:(WSWebExplorerObjectType)objectType hash:(WSHash256 *)hash
{
    WSExceptionCheckIllegal(hash != nil, @"Nil hash");
    
    NSString *network = [self networkName];
    NSString *object = [self objectForType:objectType];
    
    NSURL *baseURL = [NSURL URLWithString:[NSString stringWithFormat:WSWebExplorerBiteasyBaseFormat, network]];
    return [NSURL URLWithString:[NSString stringWithFormat:WSWebExplorerBiteasyObjectPathFormat, object, hash] relativeToURL:baseURL];
}

- (void)buildSweepTransactionsFromKey:(WSKey *)fromKey
                            toAddress:(WSAddress *)toAddress
                                  fee:(uint64_t)fee
                            maxTxSize:(NSUInteger)maxTxSize
                             callback:(void (^)(WSSignedTransaction *))callback
                           completion:(void (^)(NSUInteger))completion
                              failure:(void (^)(NSError *))failure
{
    WSExceptionCheckIllegal(fromKey != nil, @"Nil fromKey");
    WSExceptionCheckIllegal(toAddress != nil, @"Nil toAddress");
    WSExceptionCheckIllegal(completion != NULL, @"NULL completion");
    WSExceptionCheckIllegal(failure != NULL, @"NULL failure");
    
    id<WSParameters> parameters = toAddress.parameters;

    if (maxTxSize == 0) {
        maxTxSize = WSTransactionMaxSize;
    }
    
    WSAddress *fromAddress = [fromKey addressWithParameters:parameters];
    __block WSTransactionBuilder *builder = [[WSTransactionBuilder alloc] init];
    __block NSUInteger numberOfTransactions = 0;
    
    // XXX: unspent outputs may be _A LOT_
    //
    // https://api.biteasy.com/testnet/v1/addresses/muyDoehpBExCbRRXLtDUpw5DaTb33UZeyG/unspent-outputs
    
    DDLogVerbose(@"Sweeping %@ funds into %@", fromAddress, toAddress);
    
    [self fetchUnspentInputsForAddress:fromAddress page:1 handler:^(WSSignableTransactionInput *input, BOOL isLast, BOOL *stop) {
        [builder addSignableInput:input];
        
        const NSUInteger estimatedTxSizeBefore = [builder estimatedSizeWithExtraInputs:nil outputs:1];
        const NSUInteger estimatedTxSizeAfter = [builder estimatedSizeWithExtraInputs:@[input] outputs:1];
        
        DDLogVerbose(@"#%u Sweep transaction estimated size: %u->%u > %u ?",
                     numberOfTransactions, estimatedTxSizeBefore, estimatedTxSizeAfter, maxTxSize);
        
        if (isLast || ((estimatedTxSizeBefore <= maxTxSize) && (estimatedTxSizeAfter > maxTxSize))) {
            DDLogVerbose(@"#%u Sweep inputs (%u): %@", numberOfTransactions, builder.signableInputs.count, builder.signableInputs);
            DDLogVerbose(@"#%u Sweep input value: %llu", numberOfTransactions, [builder inputValue]);
            
            if (![builder addSweepOutputAddress:toAddress fee:fee]) {
                failure(WSErrorMake(WSErrorCodeInsufficientFunds, @"Unspent balance is less than fee + min output value"));
                return;
            }
            
            DDLogVerbose(@"#%u Sweep output value: %llu", numberOfTransactions, [builder outputValue]);
            DDLogVerbose(@"#%u Sweep fee: %llu", numberOfTransactions, [builder fee]);
            
            NSError *error;
            NSDictionary *keys = @{fromAddress: fromKey};
            WSSignedTransaction *transaction = [builder signedTransactionWithInputKeys:keys error:&error];
            if (!transaction) {
//                DDLogDebug(@"#%u Sweep transaction error: %@", (unsigned long)numberOfTransactions, error);
                
                *stop = YES;
                failure(error);
                return;
            }
            DDLogVerbose(@"#%u Sweep transaction: %@", numberOfTransactions, transaction);
            ++numberOfTransactions;
            
            if (callback) {
                callback(transaction);
            }
            
            builder = [[WSTransactionBuilder alloc] init];
        }
    } completion:^{
        completion(numberOfTransactions);
    } failure:failure];
}

- (void)buildSweepTransactionsFromBIP38Key:(WSBIP38Key *)fromBIP38Key
                                passphrase:(NSString *)passphrase
                                 toAddress:(WSAddress *)toAddress
                                       fee:(uint64_t)fee
                                 maxTxSize:(NSUInteger)maxTxSize
                                  callback:(void (^)(WSSignedTransaction *))callback
                                completion:(void (^)(NSUInteger))completion
                                   failure:(void (^)(NSError *))failure
{
    WSExceptionCheckIllegal(fromBIP38Key != nil, @"Nil fromBIP38Key");
    WSExceptionCheckIllegal(toAddress != nil, @"Nil toAddress");
    WSExceptionCheckIllegal(completion != NULL, @"NULL completion");
    WSExceptionCheckIllegal(failure != NULL, @"NULL failure");
    
    WSKey *fromKey = [fromBIP38Key decryptedKeyWithPassphrase:passphrase];
    [self buildSweepTransactionsFromKey:fromKey toAddress:toAddress fee:fee maxTxSize:maxTxSize callback:callback completion:completion failure:failure];
}

#pragma mark Helpers

- (void)fetchUnspentInputsForAddress:(WSAddress *)address
                                page:(NSUInteger)page
                             handler:(void (^)(WSSignableTransactionInput *, BOOL, BOOL *))handler
                          completion:(void (^)())completion
                             failure:(void (^)(NSError *))failure
{
    NSParameterAssert(address);
    NSParameterAssert(page > 0);
    NSParameterAssert(handler);
    NSParameterAssert(completion);
    NSParameterAssert(failure);
    
    id<WSParameters> parameters = address.parameters;

    NSURL *baseURL = [NSURL URLWithString:[NSString stringWithFormat:WSWebExplorerBiteasyBaseAPIFormat, [self networkName]]];
    NSString *path = [NSString stringWithFormat:WSWebExplorerBiteasyUnspentPathFormat, address, page, WSWebExplorerBiteasyUnspentPerPage];
    
    [[WSJSONClient sharedInstance] asynchronousRequestWithBaseURL:baseURL path:path success:^(NSInteger statusCode, id object) {
        NSDictionary *jsonData = object[@"data"];
        NSArray *jsonOutputs = jsonData[@"outputs"];
        NSDictionary *jsonPagination = jsonData[@"pagination"];
        const NSUInteger nextPage = [jsonPagination[@"next_page"] unsignedIntegerValue];
        const BOOL isLastPage = (nextPage == 0);
        
        for (NSDictionary *jsonOutput in jsonOutputs) {
            const uint64_t previousValue = [jsonOutput[@"value"] unsignedLongLongValue];
            WSAddress *previousAddress = WSAddressFromString(parameters, jsonOutput[@"to_address"]);
            
            NSAssert([previousAddress isEqual:address], @"Output address should be searched address (%@ != %@)",
                     previousAddress, address);
            
            WSHash256 *previousTxId = WSHash256FromHex(jsonOutput[@"transaction_hash"]);
            const uint32_t previousIndex = (uint32_t)[jsonOutput[@"transaction_index"] unsignedIntegerValue];
            
            WSTransactionOutput *previousOutput = [[WSTransactionOutput alloc] initWithAddress:previousAddress value:previousValue];
            WSTransactionOutPoint *previousOutpoint = [WSTransactionOutPoint outpointWithParameters:parameters txId:previousTxId index:previousIndex];
            WSSignableTransactionInput *input = [[WSSignableTransactionInput alloc] initWithPreviousOutput:previousOutput outpoint:previousOutpoint];
            
            const BOOL isLast = (isLastPage && (jsonOutput == [jsonOutputs lastObject]));
            BOOL stop = NO;
            handler(input, isLast, &stop);
            if (stop) {
                return;
            }
        }
        
        if (isLastPage) {
            completion();
        }
        else {
            
            // yield to avoid rate limiting
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, WSWebExplorerBiteasyYieldInterval * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self fetchUnspentInputsForAddress:address page:nextPage handler:handler completion:completion failure:failure];
            });
        }
    } failure:^(NSInteger statusCode, NSError *error) {
        failure(error ? : WSErrorMake(WSErrorCodeNetworking, @"HTTP %u", statusCode));
    }];
}

@end
