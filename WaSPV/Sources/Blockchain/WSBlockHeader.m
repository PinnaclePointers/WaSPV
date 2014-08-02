//
//  WSBlockHeader.m
//  WaSPV
//
//  Created by Davide De Rosa on 24/06/14.
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

#import <openssl/bn.h>

#import "WSBlockHeader.h"
#import "WSBlockMacros.h"
#import "WSCheckpoint.h"
#import "WSBitcoin.h"
#import "WSMacros.h"
#import "WSErrors.h"

@interface WSBlockHeader ()

@property (nonatomic, assign) uint32_t version;
@property (nonatomic, strong) WSHash256 *previousBlockId;
@property (nonatomic, strong) WSHash256 *merkleRoot;
@property (nonatomic, assign) uint32_t timestamp;
@property (nonatomic, assign) uint32_t bits;
@property (nonatomic, assign) uint32_t nonce;

@property (nonatomic, strong) WSHash256 *blockId;

- (WSHash256 *)computeBlockId;
+ (BIGNUM *)largestHash;

@end

@implementation WSBlockHeader

- (instancetype)initWithVersion:(uint32_t)version previousBlockId:(WSHash256 *)previousBlockId merkleRoot:(WSHash256 *)merkleRoot timestamp:(uint32_t)timestamp bits:(uint32_t)bits nonce:(uint32_t)nonce
{
    WSExceptionCheckIllegal(previousBlockId != nil, @"Nil previousBlockId");
    
    if ((self = [super init])) {
        self.version = version;
        self.previousBlockId = previousBlockId;
        self.merkleRoot = merkleRoot;
        self.timestamp = timestamp;
        self.bits = bits;
        self.nonce = nonce;
        self.blockId = [self computeBlockId];
    }
    return self;
}

- (instancetype)initWithCheckpoint:(WSCheckpoint *)checkpoint previousBlockId:(WSHash256 *)previousBlockId
{
    if ((self = [self initWithVersion:0 previousBlockId:previousBlockId merkleRoot:nil timestamp:checkpoint.timestamp bits:checkpoint.bits nonce:0])) {
        self.blockId = checkpoint.blockId;
    }
    return self;
}

- (uint32_t)txCount
{
    return 0;
}

- (BOOL)isComplete
{
    return ((self.version > 0) &&
            self.previousBlockId &&
            self.merkleRoot &&
            (self.timestamp > 0) &&
            (self.bits > 0));
}

- (WSHash256 *)computeBlockId
{
    if (![self isComplete]) {
        return nil;
    }
    WSMutableBuffer *buffer = [[WSMutableBuffer alloc] initWithCapacity:(WSBlockHeaderLength - 1)];
    [buffer appendUint32:self.version];
    [buffer appendHash256:self.previousBlockId];
    [buffer appendHash256:self.merkleRoot];
    [buffer appendUint32:self.timestamp];
    [buffer appendUint32:self.bits];
    [buffer appendUint32:self.nonce];
    return [buffer computeHash256];
}

- (NSData *)difficultyData
{
    return WSBlockGetDifficultyFromBits(self.bits);
}

- (NSString *)difficultyString
{
    return WSBlockGetDifficultyStringFromBits(self.bits);
}

- (NSData *)workData
{
    BIGNUM bnWork;
    BIGNUM bnTargetPlusOne;

    BN_init(&bnWork);
    BN_init(&bnTargetPlusOne);

    BN_CTX *ctx = BN_CTX_new();
    BN_CTX_start(ctx);
    WSBlockSetBits(&bnTargetPlusOne, self.bits);
    BN_add(&bnTargetPlusOne, &bnTargetPlusOne, BN_value_one());
    BN_div(&bnWork, NULL, [[self class] largestHash], &bnTargetPlusOne, ctx);
    BN_CTX_end(ctx);
    BN_CTX_free(ctx);

    NSMutableData *workData = [[NSMutableData alloc] initWithLength:BN_num_bytes(&bnWork)];
    BN_bn2bin(&bnWork, workData.mutableBytes);

    BN_free(&bnWork);
    BN_free(&bnTargetPlusOne);

    return workData;
}

- (NSString *)workString
{
    BIGNUM work;
    
    BN_init(&work);
    WSBlockWorkFromData(&work, self.workData);
    NSString *workString = [[NSString alloc] initWithCString:BN_bn2dec(&work) encoding:NSUTF8StringEncoding];
    BN_free(&work);
    
    return workString;
}

- (BOOL)verifyWithError:(NSError *__autoreleasing *)error
{
    BOOL verificationFailed = NO;
    BIGNUM target;
    BIGNUM maxTarget;
    BIGNUM hash;
    
    BN_init(&target);
    BN_init(&maxTarget);
    BN_init(&hash);

    WSBlockSetBits(&target, self.bits);
    WSBlockSetBits(&maxTarget, [WSCurrentParameters maxProofOfWork]);

    // range out of [1, maxProofOfWork]
    if ((BN_cmp(&target, BN_value_one()) < 0) || (BN_cmp(&target, &maxTarget) > 0)) {
        WSErrorSet(error, WSErrorCodeInvalidBlock, @"Target out of range (%x)", self.bits);
        verificationFailed = YES;
    }

    // invalid proof-of-work (smaller values are more difficult)
    if (!verificationFailed) {
        WSBlockSetHash(&hash, self.blockId);

        if (BN_cmp(&hash, &target) > 0) {
            WSErrorSet(error, WSErrorCodeInvalidBlock, @"Block less difficult (greater) than target (%x > %x)",
                       WSBlockGetBits(&hash), self.bits);

            verificationFailed = YES;
        }
    }
    
//    DDLogDebug(@"Target: %s", BN_bn2hex(&target));
//    DDLogDebug(@"Hash  : %s", BN_bn2hex(&hash));
    
    // timestamp in the future
    if (!verificationFailed) {
        const uint32_t currentTimestamp = WSCurrentTimestamp();
        if (self.timestamp > currentTimestamp + WSBlockAllowedTimeDrift) {
            WSErrorSet(error, WSErrorCodeInvalidBlock, @"Timestamp ahead in the future (%u > %u + %u)",
                       self.timestamp, currentTimestamp, WSBlockAllowedTimeDrift);

            verificationFailed = YES;
        }
    }
    
    BN_free(&target);
    BN_free(&maxTarget);
    BN_free(&hash);

    return !verificationFailed;
}

+ (BIGNUM *)largestHash
{
    static BIGNUM largest;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BN_init(&largest);
        BN_set_bit(&largest, 256);
    });
    return &largest;
}

- (NSString *)description
{
    return [self descriptionWithIndent:0];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
    WSBlockHeader *copy = [[self class] allocWithZone:zone];
    copy.version = self.version;
    copy.previousBlockId = [self.previousBlockId copyWithZone:zone];
    copy.merkleRoot = [self.merkleRoot copyWithZone:zone];
    copy.timestamp = self.timestamp;
    copy.bits = self.bits;
    copy.nonce = self.nonce;
    copy.blockId = [self.blockId copyWithZone:zone];
    return copy;
}

#pragma mark WSBufferEncoder

- (void)appendToMutableBuffer:(WSMutableBuffer *)buffer
{
    [buffer appendUint32:self.version];
    [buffer appendHash256:self.previousBlockId];
    [buffer appendHash256:self.merkleRoot];
    [buffer appendUint32:self.timestamp];
    [buffer appendUint32:self.bits];
    [buffer appendUint32:self.nonce];
    [buffer appendUint8:self.txCount];
}

- (WSBuffer *)toBuffer
{
    WSMutableBuffer *buffer = [[WSMutableBuffer alloc] initWithCapacity:WSBlockHeaderLength];
    [self appendToMutableBuffer:buffer];
    return buffer;
}

#pragma mark WSBufferDecoder

- (instancetype)initWithBuffer:(WSBuffer *)buffer from:(NSUInteger)from available:(NSUInteger)available error:(NSError *__autoreleasing *)error
{
    if (available < WSBlockHeaderLength) {
        WSErrorSetNotEnoughBytes(error, [self class], available, WSBlockHeaderLength);
        return nil;
    }
    NSUInteger offset = from;

    const uint32_t version = [buffer uint32AtOffset:offset];
    offset += sizeof(uint32_t);

    WSHash256 *previousBlockId = [buffer hash256AtOffset:offset];
    offset += WSHash256Length;

    WSHash256 *merkleRoot = [buffer hash256AtOffset:offset];
    offset += WSHash256Length;

    const uint32_t timestamp = [buffer uint32AtOffset:offset];
    offset += sizeof(uint32_t);

    const uint32_t bits = [buffer uint32AtOffset:offset];
    offset += sizeof(uint32_t);

    const uint32_t nonce = [buffer uint32AtOffset:offset];
    
    return [self initWithVersion:version previousBlockId:previousBlockId merkleRoot:merkleRoot timestamp:timestamp bits:bits nonce:nonce];
}

#pragma mark WSIndentableDescription

- (NSString *)descriptionWithIndent:(NSUInteger)indent
{
    NSMutableArray *tokens = [[NSMutableArray alloc] init];
    [tokens addObject:[NSString stringWithFormat:@"version = %u", self.version]];
    [tokens addObject:[NSString stringWithFormat:@"id = %@", self.blockId]];
    [tokens addObject:[NSString stringWithFormat:@"previous = %@", self.previousBlockId]];
    [tokens addObject:[NSString stringWithFormat:@"merkleRoot = %@", self.merkleRoot]];
    [tokens addObject:[NSString stringWithFormat:@"timestamp = %u (%@)", self.timestamp, [NSDate dateWithTimeIntervalSince1970:self.timestamp]]];
    [tokens addObject:[NSString stringWithFormat:@"bits = %x", self.bits]];
    [tokens addObject:[NSString stringWithFormat:@"difficulty = %@", self.difficultyString]];
    [tokens addObject:[NSString stringWithFormat:@"nonce = %u", self.nonce]];
    return [NSString stringWithFormat:@"{%@}", WSStringDescriptionFromTokens(tokens, indent)];
}

@end