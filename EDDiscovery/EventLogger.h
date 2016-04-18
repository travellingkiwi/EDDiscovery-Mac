//
//  EventLogger.h
//  EDDiscovery
//
//  Created by thorin on 18/04/16.
//  Copyright © 2016 Moonrays. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@interface EventLogger : NSObject

+ (EventLogger *)instance;

+ (void)addProcessingStep;
+ (void)addLog:(NSString *)msg;
+ (void)addLog:(NSString *)msg timestamp:(BOOL)timestamp newline:(BOOL)newline;

@property(nonatomic, strong) NSTextView *textView;

@end
