//
//  WSSeedGenerator.h
//  WaSPV
//
//  Created by Davide De Rosa on 08/06/14.
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

#import "WSSeed.h"

@interface WSSeedGenerator : NSObject

@property (nonatomic, copy) NSString *wordsPath;

+ (instancetype)sharedInstance;
- (NSString *)generateRandomMnemonic;
- (WSSeed *)generateRandomSeed;
- (NSString *)mnemonicFromData:(NSData *)data error:(NSError **)error;
- (NSData *)dataFromMnemonic:(NSString *)mnemonic error:(NSError **)error;
- (NSData *)deriveKeyDataFromMnemonic:(NSString *)mnemonic;

- (NSArray *)wordList;
- (void)unloadWords;

@end
