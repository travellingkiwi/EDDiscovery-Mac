//
//  NetLogParser.h
//  EDDiscovery
//
//  Created by Michele Noberasco on 18/04/16.
//  Copyright © 2016 Michele Noberasco. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "System.h"

#define DEFAULT_LOG_DIR_PATH_DIR [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Frontier Developments/Elite Dangerous"]

@class Commander;

@interface NetLogParser : NSObject {
  
}

+ (nullable NetLogParser *)instanceOrNil:(Commander * __nonnull)commander;
+ (nullable NetLogParser *)createInstanceForCommander:(Commander * __nonnull)commander;

- (void)startInstance:(void(^__nonnull)(void))completionBlock;
- (void)stopInstance;

@end
