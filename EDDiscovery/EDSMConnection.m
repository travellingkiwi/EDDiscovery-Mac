//
//  EDSMConnection.m
//  EDDiscovery
//
//  Created by Michele Noberasco on 17/04/16.
//  Copyright © 2016 Michele Noberasco. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "EDSMConnection.h"
#import "Jump.h"
#import "System.h"
#import "Note.h"
#import "Commander.h"
#import "EDSM.h"
#import "Distance.h"

#define BASE_URL @"http://www.edsm.net"

@implementation EDSMConnection

+ (void)setup {
  static dispatch_once_t onceToken;
  
  dispatch_once(&onceToken, ^{
    [self setBaseUrl:BASE_URL];
  });
}

+ (void)getSystemInfo:(NSString *)systemName response:(void(^)(NSDictionary *response, NSError *error))response {
  [self setup];
  
  [self callApi:@"api-v1/system"
     concurrent:YES
     withMethod:@"POST"
progressCallBack:nil
responseCallback:^(id data, NSError *error) {
  
  [Answers logCustomEventWithName:@"EDSM API call" customAttributes:@{@"API":@"api-v1/system"}];
  
  if (error == nil) {
    NSError      *error  = nil;
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    
    if (![result isKindOfClass:NSDictionary.class]) {
      result = nil;
    }
    
    response(result, error);
  }
  else {
    response(nil, error);
  }
  
}
     parameters:4,
        @"sysname",       systemName,
        @"coords",        @"1",
        @"distances",     @"1",
        @"problems",      @"1"
      //@"includeHidden", @"1"
   ];
}

+ (void)submitDistances:(NSArray <Distance *> *)distances forSystem:(NSString *)systemName response:(void(^)(BOOL distancesSubmitted, BOOL systemTrilaterated, NSError *error))response {
  Commander      *commander  = Commander.activeCommander;
  NSString       *cmdrName   = (commander == nil) ? @"" : commander.name;
  NSMutableArray *refs       = [NSMutableArray array];
  NSString       *appName    = [NSBundle.mainBundle objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
  NSString       *appVersion = [NSString stringWithFormat:@"%@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
  
  appName = [appName stringByAppendingString:@"-Mac"];
  
  for (Distance *distance in distances) {
    [refs addObject:@{
                      @"name":distance.name,
                      @"dist":distance.distance
                      }];
  }
  
  NSDictionary *dict = @{
                         @"data":@{
                             //@"test":@1, // <-- dry run... API will answer normally but won't store anything to the data base
                             @"ver":@2,
                             @"commander":cmdrName,
                             @"fromSoftware":appName,
                             @"fromSoftwareVersion":appVersion,
                             @"p0":@{
                                 @"name":systemName
                                 },
                             @"refs":refs
                             }
                         };
  
  NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
  
  [self callApi:@"api-v1/submit-distances"
     concurrent:YES
       withBody:data
progressCallBack:nil
responseCallback:^(id output, NSError *error) {
  
  [Answers logCustomEventWithName:@"EDSM API call" customAttributes:@{@"API":@"api-v1/submit-distances"}];
  
  if (error == nil) {
    NSError      *error        = nil;
    NSDictionary *data         = [NSJSONSerialization JSONObjectWithData:output options:0 error:&error];
    BOOL          submitted    = YES;
    BOOL          trilaterated = NO;
    
    if ([data isKindOfClass:NSDictionary.class]) {
      NSDictionary *baseSystem = data[@"basesystem"];
      NSArray      *distances  = data[@"distances"];
      
      if ([distances isKindOfClass:NSArray.class]) {
        for (NSDictionary *distance in distances) {
          NSInteger result = [distance[@"msgnum"] integerValue];
        
          if (result == 201) {
            submitted = NO;
            
            error = [NSError errorWithDomain:@"EDDiscovery"
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey:distance[@"msg"]}];
          }
        }
      }
      
      if ([baseSystem isKindOfClass:NSDictionary.class]) {
        NSInteger result = [baseSystem[@"msgnum"] integerValue];
        
        if (result == 101) {
          submitted = NO;
          
          error = [NSError errorWithDomain:@"EDDiscovery"
                                      code:result
                                  userInfo:@{NSLocalizedDescriptionKey:baseSystem[@"msg"]}];
        }
        else if (result == 102 || result == 104) {
          trilaterated = YES;
        }
      }
      
      response(submitted, trilaterated, error);
    }
    else {
      error = [NSError errorWithDomain:@"EDDiscovery"
                                  code:999
                              userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"Error in server response", @"")}];
      
      response(NO, NO, error);
    }
  }
  else {
    response(NO, NO, error);
  }

}];
}

+ (void)getNightlyDumpWithProgress:(ProgressBlock)progress response:(void(^)(NSArray *response, NSError *error))response {
  [self setup];
  
  [self callApi:@"dump/systemsWithCoordinates.json"
     concurrent:YES
     withMethod:@"GET"
progressCallBack:^(long long downloaded, long long total) {
  if (progress != nil) {
#warning FIXME: making assumptions on nightly dump file size!
    //EDSM does not return expected content size of nightly dumps
    //assume a size of 340 GB
    
    total = 1024 * 1024 * 340;
  
    progress(downloaded, MAX(downloaded,total));
  }
}
responseCallback:^(id output, NSError *error) {

  [Answers logCustomEventWithName:@"EDSM API call" customAttributes:@{@"API":@"dump/systemsWithCoordinates.json"}];
  
  if (error == nil) {
    NSError *error   = nil;
    NSArray *systems = [NSJSONSerialization JSONObjectWithData:output options:0 error:&error];
    
    if (![systems isKindOfClass:NSArray.class]) {
      systems = nil;
    }
    
    response(systems, error);
  }
  else {
    response(nil, error);
  }
  
}
     parameters:0];
}

+ (void)getSystemsInfoWithProgress:(ProgressBlock)progress response:(void(^)(NSArray *response, NSError *error))response {
  NSDate *lastSyncDate = [NSUserDefaults.standardUserDefaults objectForKey:EDSM_SYSTEM_UPDATE_TIMESTAMP];
  
  if (lastSyncDate == nil) {
    NSLog(@"Fetching nightly systems dump!");
    
    [self getNightlyDumpWithProgress:progress response:^(NSArray *output, NSError *error) {
      //save sync date 1 day in the past as the nighly dumps are generated once per day
      
      if (output != nil) {
        NSDateComponents *dayComponent = [[NSDateComponents alloc] init];
        
        dayComponent.day = -1;
        
        NSCalendar *calendar     = [NSCalendar currentCalendar];
        NSDate     *lastSyncDate = [calendar dateByAddingComponents:dayComponent toDate:NSDate.date options:0];
        
        [NSUserDefaults.standardUserDefaults setObject:lastSyncDate forKey:EDSM_SYSTEM_UPDATE_TIMESTAMP];
        
        [self getSystemsInfoWithProgress:nil response:^(NSArray *output2, NSError *error2) {
          NSMutableArray *array = [NSMutableArray arrayWithArray:output];
          
          if ([output2 isKindOfClass:NSArray.class]) {
            [array addObjectsFromArray:output2];
          }
          
          response(array, error);
        }];
      }
    }];
  }
  else {
    //perform delta queries in batches of 28 days
    
    NSDateComponents *dayComponent = [[NSDateComponents alloc] init];
    
    dayComponent.day = 28;
    
    NSCalendar         *calendar    = [NSCalendar currentCalendar];
    NSDate             *fromDate    = lastSyncDate;
    NSDate             *toDate      = [calendar dateByAddingComponents:dayComponent toDate:fromDate options:0];
    NSDate             *currDate    = NSDate.date;
    NSMutableArray     *systems     = [NSMutableArray array];
    __block NSUInteger  numRequests = 1;
    __block NSUInteger  numDone     = 0;
    __block NSError    *error       = nil;
    
    ProgressBlock progressBlock = ^void(long long downloaded, long long total) {
      if (progress != nil) {
        @synchronized (self.class) {
          long long myTotal      = numRequests + numDone;
          long long currProgress = numDone;
          
          //NSLog(@"progressBlock currProgress %ll myTotal %ll", (unsigned long)currProgress, (unsigned long)myTotal);

          progress(currProgress, myTotal);
        }
      }
    };
    
    void (^responseBlock)(NSArray *, NSError *) = ^void(NSArray *output, NSError *err) {
      NSLog(@"updateSystemsFromEDSM::response");

      @synchronized (self.class) {
        if (err != nil) {
          error = err;
        }
        else if ([output isKindOfClass:NSArray.class]) {
          [systems addObjectsFromArray:output];
        }
        
        numRequests--;
        numDone++;
        
        NSLog(@"responseBlock numRequests %lu numDone %lu", (unsigned long)numRequests, (unsigned long)numDone);
        
        if (progress != nil) {
          long long myTotal      = numRequests + numDone;
          long long currProgress = numDone;
          
          progress(currProgress, myTotal);
        }
        
        if (numRequests == 0) {
          if (error == nil) {
            response(systems, nil);
            
            [NSUserDefaults.standardUserDefaults setObject:currDate forKey:EDSM_SYSTEM_UPDATE_TIMESTAMP];
          }
          else {
            response(nil, error);
          }
        }
      }
    };
    
    while (toDate.timeIntervalSinceReferenceDate < currDate.timeIntervalSinceReferenceDate) {
      @synchronized (self.class) {
        numRequests++;
      }
      
      [self getSystemsInfoFrom:fromDate
                            to:toDate
                      progress:progressBlock
                      response:responseBlock];
      
      fromDate = toDate;
      toDate   = [calendar dateByAddingComponents:dayComponent toDate:fromDate options:0];
    
    }
    
    if (toDate.timeIntervalSinceReferenceDate > currDate.timeIntervalSinceReferenceDate) {
      toDate = currDate;
    }
    
    [self getSystemsInfoFrom:fromDate
                          to:toDate
                    progress:progressBlock
                    response:responseBlock];
  }
}

+ (void)getSystemsInfoFrom:(NSDate *)fromDate to:(NSDate *)toDate progress:(ProgressBlock)progress response:(void(^)(NSArray *response, NSError *error))response {
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  
  formatter.timeZone   = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
  formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
  
  NSString *from = [formatter stringFromDate:fromDate];
  NSString *to   = [formatter stringFromDate:toDate];
  
  NSLog(@"Fetching delta systems from %@ to %@!", from, to);
  
  [self setup];
  
  [self callApi:@"api-v1/systems"
     concurrent:YES
     withMethod:@"GET"
progressCallBack:progress
responseCallback:^(id output, NSError *error) {
  
  [Answers logCustomEventWithName:@"EDSM API call" customAttributes:@{@"API":@"api-v1/systems"}];
  
  //  NSLog(@"ERR: %@", error);
  //  NSLog(@"RES: %@", response);
  
  if (error == nil) {
    NSError *error   = nil;
    NSArray *systems = [NSJSONSerialization JSONObjectWithData:output options:0 error:&error];
    
    if (![systems isKindOfClass:NSArray.class]) {
      systems = nil;
    }
    
    response(systems, error);
  }
  else {
    response(nil, error);
  }
}
     parameters:5,
   @"startdatetime", from,   // <-- return only systems updated after this date
   @"endDateTime",   to,     // <-- return only systems updated before this date
   @"known",         @"1",   // <-- return only systems with known coordinates
   @"coords",        @"1",   // <-- include system coordinates
   //@"distances",     @"1", // <-- include distances from other susyems
   @"problems",      @"1"    // <-- include information about known errors
   //@"includeHidden", @"1"  // <-- include systems with wrong names or wrong distances
   ];
}

//
// When we get the jumps for the commander, we don't want to get more than we need to... So we start at
// the last time we sync'ed (Or 01/01/2015) and continue to the date we lookup that was the last entry
// to be added to EDSM (From the get-position API)
+ (void)getJumpsForCommander:(Commander *)commander response:(void(^)(NSArray *jumps, NSError *error))response {
  __block NSDate   *lastSyncDate = nil;
  __block NSString *startDateString = nil;
  __block NSString *endDateString = nil;
  __block NSDate   *endDate;
  
  __block NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  
  formatter.timeZone   = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
  formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";

  NSLog(@"getJumpsForCommander: Commander %@", commander.name);
  
  if (commander.edsmAccount.jumpsUpdateTimestamp != 0) {
    lastSyncDate = [NSDate dateWithTimeIntervalSinceReferenceDate:commander.edsmAccount.jumpsUpdateTimestamp];
    
    startDateString = [formatter stringFromDate:lastSyncDate];
  }
  if(startDateString == nil) {
    // We don't have a start date, so set it to 01/01/2015 as an arbitrary start...
    startDateString=@"2015-01-01 00:00:00";
  }
  
  [self setup];
  
  NSLog(@"getJumpsForCommander: Commander %@ From %@", commander.name, startDateString);

  // The new api (api-logs-v1/get-logs specifies a maximum of 1 week interval between starttime and endtime...
  // So need to iterate forwards 1 week at a time. (In fact we just specify the start time and iterate from the
  // last end time so we don't have to worry about the 1 week interval.
  
  // if we don't have an endDate yet, get it from the commanders last position...
  // First get the commanders last position (Which incldeus the timedate - so we know where to start working backwards on the logs from
  // Synchronous not possible with old call... Need to find out how....
  NSLog(@"getJumpsForCommander::get-position");
  [self      callApi:@"api-logs-v1/get-position"
          concurrent:NO
          withMethod:@"POST"
    progressCallBack:nil
    responseCallback:^(id output, NSError *error) {

      NSLog(@"getJumpsForCommander::get-position responseCallback");
      [Answers logCustomEventWithName:@"EDSM API call" customAttributes:@{@"API":@"api-logs-v1/get-position"}];

      if (error == nil) {
        NSError      *error = nil;
        NSDictionary *data  = [NSJSONSerialization JSONObjectWithData:output options:0 error:&error];
        
        NSLog(@"getJumpsForCommander::get-position responseCallback - no error %@", data);
        endDateString=[data valueForKey:@"dateLastActivity"];
        endDate=[formatter dateFromString:endDateString];
        
        NSLog(@"getJumpsForCommander::get-position responseCallback endDate %@", endDateString);
       }
    }
    parameters:2,
    @"commanderName", commander.name,
    @"apiKey", commander.edsmAccount.apiKey
   
  ];
  
  NSLog(@"getJumpsForCommander::get-logs from %@ to %@", startDateString, endDateString);
  
  //
  // Because we need to iterate over the jumps... And the call is rate limited at EDSM to 1 every 10 seconds, we
  // now run get-logs in a loop, with 100ms between each call...
  __block BOOL            getLogsFinished=FALSE;
  __block NSMutableArray *jumps = nil;
  
  while(!getLogsFinished) {
    NSLog(@"getJumpsForCommander::get-logs endDate %@", endDate);
    
    [self       callApi:@"api-logs-v1/get-logs"
             concurrent:NO
             withMethod:@"POST"
       progressCallBack:nil
       responseCallback:^(id output, NSError *error) {
  
         NSLog(@"getJumpsForCommander::get-logs responseCallback");
         [Answers logCustomEventWithName:@"EDSM API call" customAttributes:@{@"API":@"api-logs-v1/get-logs"}];
  
         if (error == nil) {
           NSError      *error = nil;
           NSDictionary *data  = [NSJSONSerialization JSONObjectWithData:output options:0 error:&error];

           NSLog(@"getJumpsForCommander::get-logs  responseCallback - no error");

           if ([data isKindOfClass:NSDictionary.class]) {
             NSInteger result = [data[@"msgnum"] integerValue];

             //100 --> success
      
             NSLog(@"getJumpsForCommander::get-logs  responseCallback result %ld", result);
             if (result == 100) {
               [jumps addObjectsFromArray:data[@"logs"]];

               // Reset the endDate...
               NSString *thisDateString=data [@"endDateTime"];
               __block NSDate   *thisDate=[formatter dateFromString:thisDateString];
               
               // If the endDate >= lastSyncTime then we've finished...
               if(thisDate > endDate) {
                 NSLog(@"getJumpsForCommander::get-logs thisdate > lastSyncTime. Assuming end of scan as %@ > %@", thisDateString, endDate);
                 getLogsFinished=TRUE;
                 lastSyncDate=[thisDate dateByAddingTimeInterval:1];
                 commander.edsmAccount.jumpsUpdateTimestamp = [lastSyncDate timeIntervalSinceReferenceDate];
               } else {
                 NSLog(@"getJumpsForCommander::get-logs moving start to %@", thisDateString);
                 startDateString=thisDateString;
               }
            
             } else {
               getLogsFinished=TRUE;
               error = [NSError errorWithDomain:@"EDDiscovery"
                                           code:result
                                      userInfo:@{NSLocalizedDescriptionKey:data[@"msg"]}];
             }
           }
         }
       }
       parameters:3,
       @"commanderName", commander.name,
       @"apiKey", commander.edsmAccount.apiKey,
       @"startDateTime", startDateString
    ];
  }
     
  if(jumps.count !=0 ) {
    NSLog(@"getJumpsForCommander sending response with jump count %lu", jumps.count);
    response(jumps, nil);
  } else {
    NSLog(@"getJumpsForCommander sending response no jumps");
    response(nil, nil);
  }

  NSLog(@"getJumpsForCommander finished");
}

+ (void)getDiscards:(NSString *)commanderName apiKey:(NSString *)apiKey response:(void(^)(NSArray *ignore_events, NSError *error))response {
  NSAssert(commanderName != nil, @"missing commander");
  NSAssert(apiKey != nil, @"missing apiKey");

  NSLog(@"getDiscards");
  [self      callApi:@"api-journal-v1/discard"
          concurrent:NO
          withMethod:@"GET"
    progressCallBack:nil
    responseCallback:^(id output, NSError *error) {
      
      NSLog(@"getDiscards::api-journal-v1/discard responseCallback");
      [Answers logCustomEventWithName:@"EDSM API call" customAttributes:@{@"API":@"api-journal-v1/discard"}];
      
      if (error == nil) {
        NSError      *error = nil;
        NSArray *data  = [NSJSONSerialization JSONObjectWithData:output options:0 error:&error];
        
        NSLog(@"getDiscards::api-journal-v1/discard responseCallback - no error %@", data);

        if(response!=nil) {
          response(data, error);
        }
        
      }
    }
   parameters:2,
   @"commanderName", commanderName,
   @"apiKey", apiKey
   
   ];
}

+ (void)addJournal:(NSString *)json journal:(NSDictionary *)journal forCommander:(NSString *)commanderName apiKey:(NSString *)apiKey response:(void(^)(BOOL success, NSError *error))response {
  NSAssert(json != nil, @"missing json string");
  NSAssert(journal != nil, @"missing journal");
  //NSAssert(jump.edsm == nil, @"jump already sent to EDSM");
  
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  
  formatter.timeZone   = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
  formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
  
  NSString *event=[journal valueForKey:@"event"];
  
  //NSString   *name       = jump.system.name;
  //NSString   *timestamp  = [formatter stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:jump.timestamp]];
  NSString   *appName    = [NSBundle.mainBundle objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
  NSString   *appVersion = [NSString stringWithFormat:@"%@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
  //BOOL        sendCoords = NO;
  
  NSLog(@"addJournal: Commander %@ event %@", commanderName, event);
  
  void (^responseBlock)(id output, NSError *error) = ^void(id output, NSError *error) {
    [Answers logCustomEventWithName:@"EDSM API call" customAttributes:@{@"API":@"api-journal-v1"}];
    
    if (error == nil) {
      NSError      *error = nil;
      NSDictionary *data  = [NSJSONSerialization JSONObjectWithData:output options:0 error:&error];
      
      if ([data isKindOfClass:NSDictionary.class]) {
        NSInteger result = [data[@"msgnum"] integerValue];
        
        NSLog(@"addJournal:Response %ld", result);
        //100 --> success
        //401 --> An entry for the same system already exists at that date -> success
        
        if (result == 100 || result == 401) {
          response(YES, nil);
        }
        else {
          error = [NSError errorWithDomain:@"EDDiscovery"
                                      code:result
                                  userInfo:@{NSLocalizedDescriptionKey:data[@"msg"]}];
          
          response(NO, error);
        }
      }
    }
    else {
      response(NO, error);
    }
  };
  
  [self setup];
  
  [self callApi:@"api-journal-v1"
       concurrent:NO
       withMethod:@"POST"
 progressCallBack:nil
 responseCallback:responseBlock
       parameters:5,
     @"commanderName", commanderName,
     @"apiKey", apiKey,
     @"fromSoftware", appName,
     @"fromSoftwareVersion", appVersion,
     @"message", json
     ];
  
}

+ (void)addJump:(Jump *)jump forCommander:(NSString *)commanderName apiKey:(NSString *)apiKey response:(void(^)(BOOL success, NSError *error))response {
  NSAssert(jump != nil, @"missing jump");
  NSAssert(jump.edsm == nil, @"jump already sent to EDSM");

  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  
  formatter.timeZone   = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
  formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
  
  NSString   *name       = jump.system.name;
  NSString   *timestamp  = [formatter stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:jump.timestamp]];
  NSString   *appName    = [NSBundle.mainBundle objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
  NSString   *appVersion = [NSString stringWithFormat:@"%@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
  BOOL        sendCoords = NO;
  
  NSLog(@"addJump: Commander %@ system %@", commanderName, name);
  
  if ([jump.system hasCoordinates] == YES) {
    sendCoords = YES;
  }

  void (^responseBlock)(id output, NSError *error) = ^void(id output, NSError *error) {
    [Answers logCustomEventWithName:@"EDSM API call" customAttributes:@{@"API":@"api-v1/set-log"}];
    
    if (error == nil) {
      NSError      *error = nil;
      NSDictionary *data  = [NSJSONSerialization JSONObjectWithData:output options:0 error:&error];
      
      if ([data isKindOfClass:NSDictionary.class]) {
        NSInteger result = [data[@"msgnum"] integerValue];
  
        NSLog(@"addJump:Response %ld", result);
        //100 --> success
        //401 --> An entry for the same system already exists at that date -> success
        
        if (result == 100 || result == 401) {
          response(YES, nil);
        }
        else {
          error = [NSError errorWithDomain:@"EDDiscovery"
                                      code:result
                                  userInfo:@{NSLocalizedDescriptionKey:data[@"msg"]}];
          
          response(NO, error);
        }
      }
    }
    else {
      response(NO, error);
    }
  };
  
  [self setup];
  
  if (sendCoords == YES) {
    [self callApi:@"api-logs-v1/set-log"
       concurrent:NO
       withMethod:@"POST"
 progressCallBack:nil
 responseCallback:responseBlock
       parameters:9,
     @"systemName", name,
     @"commanderName", commanderName,
     @"apiKey", apiKey,
     @"fromSoftware", appName,
     @"fromSoftwareVersion", appVersion,
     @"x", [NSString stringWithFormat:@"%f", jump.system.x],
     @"y", [NSString stringWithFormat:@"%f", jump.system.y],
     @"z", [NSString stringWithFormat:@"%f", jump.system.z],
     @"dateVisited", timestamp
     ];
  }
  else {
    [self callApi:@"api-logs-v1/set-log"
       concurrent:NO
       withMethod:@"POST"
 progressCallBack:nil
 responseCallback:responseBlock
       parameters:6,
     @"systemName", name,
     @"commanderName", commanderName,
     @"apiKey", apiKey,
     @"fromSoftware", appName,
     @"fromSoftwareVersion", appVersion,
     @"dateVisited", timestamp
     ];
  }
}

+ (void)deleteJump:(Jump *)jump forCommander:(NSString *)commanderName apiKey:(NSString *)apiKey response:(void(^)(BOOL success, NSError *error))response {
  NSAssert(jump != nil, @"missing jump");
  NSAssert(jump.edsm != nil, @"jump not sent to EDSM");
  
  NSLog(@"WARNING: Tried to delete jump");
  return;
  
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  
  formatter.timeZone   = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
  formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
  
  NSString   *name       = jump.system.name;
  NSString   *timestamp  = [formatter stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:jump.timestamp]];
  NSString   *appName    = [NSBundle.mainBundle objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
  NSString   *appVersion = [NSString stringWithFormat:@"%@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
  
  [self setup];
  
  [self callApi:@"api-logs-v1/delete-log"
     concurrent:YES
     withMethod:@"POST"
progressCallBack:nil
responseCallback:^(id output, NSError *error) {
  [Answers logCustomEventWithName:@"EDSM API call" customAttributes:@{@"API":@"api-v1/delete-log"}];
  
  if (error == nil) {
    NSError      *error = nil;
    NSDictionary *data  = [NSJSONSerialization JSONObjectWithData:output options:0 error:&error];
    
    if ([data isKindOfClass:NSDictionary.class]) {
      NSInteger result = [data[@"msgnum"] integerValue];
      
      //100 --> success
      
      if (result == 100) {
        response(YES, nil);
      }
      else {
        error = [NSError errorWithDomain:@"EDDiscovery"
                                    code:result
                                userInfo:@{NSLocalizedDescriptionKey:data[@"msg"]}];
        
        response(NO, error);
      }
    }
  }
  else {
    response(NO, error);
  }
}
     parameters:6,
   @"systemName", name,
   @"commanderName", commanderName,
   @"apiKey", apiKey,
   @"fromSoftware", appName,
   @"fromSoftwareVersion", appVersion,
   @"dateVisited", timestamp
   ];
}

+ (void)getNotesForCommander:(Commander *)commander response:(void(^)(NSArray *comments, NSError *error))response {
  NSDate *lastSyncDate = nil;
  
  if (commander.edsmAccount.notesUpdateTimestamp != 0) {
    lastSyncDate = [NSDate dateWithTimeIntervalSinceReferenceDate:commander.edsmAccount.notesUpdateTimestamp];
  }
  
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  
  formatter.timeZone   = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
  formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
  
  NSString *from = [formatter stringFromDate:lastSyncDate];
  
  [self setup];
  
  [self callApi:@"api-logs-v1/get-comments"
     concurrent:YES
     withMethod:@"POST"
progressCallBack:nil
responseCallback:^(id output, NSError *error) {
  
  [Answers logCustomEventWithName:@"EDSM API call" customAttributes:@{@"API":@"api-v1/get-comments"}];
  
  if (error == nil) {
    NSArray      *comments = nil;
    NSError      *error    = nil;
    NSDictionary *data     = [NSJSONSerialization JSONObjectWithData:output options:0 error:&error];
    
    if ([data isKindOfClass:NSDictionary.class]) {
      NSInteger result = [data[@"msgnum"] integerValue];
      
      //100 --> success
      
      if (result == 100) {
        comments = data[@"comments"];
        
        if (comments.count > 0) {
          NSDictionary *latestComment = comments.lastObject;
          NSDate       *lastSyncDate  = [formatter dateFromString:latestComment[@"lastUpdate"]];
          
          //add 1 second to date of last recorded comment (otherwise EDSM will return this comment to me next time I sync)
          lastSyncDate = [lastSyncDate dateByAddingTimeInterval:1];
          
          commander.edsmAccount.notesUpdateTimestamp = [lastSyncDate timeIntervalSinceReferenceDate];
        }
      }
      else {
        error = [NSError errorWithDomain:@"EDDiscovery"
                                    code:result
                                userInfo:@{NSLocalizedDescriptionKey:data[@"msg"]}];
      }
    }
    
    response(comments, error);
  }
  else {
    response(nil, error);
  }
  
}
     parameters:3,
   @"startdatetime", from, // <-- return only systems updated after this date
   @"commanderName", commander.name,
   @"apiKey", commander.edsmAccount.apiKey
   ];
}

+ (void)setNote:(NSString *)note system:(NSString *)system commander:(NSString *)commanderName apiKey:(NSString *)apiKey response:(void(^)(BOOL success, NSError *error))response {
  NSAssert(system != nil, @"missing system");
  
  [self setup];
  
  [self callApi:@"api-logs-v1/set-comment"
     concurrent:YES
     withMethod:@"POST"
progressCallBack:nil
responseCallback:^(id output, NSError *error) {
  
  [Answers logCustomEventWithName:@"EDSM API call" customAttributes:@{@"API":@"api-v1/set-comment"}];
  
  if (error == nil) {
    NSError      *error   = nil;
    NSDictionary *data    = [NSJSONSerialization JSONObjectWithData:output options:0 error:&error];
    BOOL          success = NO;
    
    if ([data isKindOfClass:NSDictionary.class]) {
      NSInteger result = [data[@"msgnum"] integerValue];
      
      //100 --> success
      
      if (result == 100) {
        success = YES;
      }
      else {
        error = [NSError errorWithDomain:@"EDDiscovery"
                                    code:result
                                userInfo:@{NSLocalizedDescriptionKey:data[@"msg"]}];
      }
    }
    
    response(success, error);
  }
  else {
    response(NO, error);
  }
  
}
     parameters:4,
   @"systemName", system,
   @"comment", (note.length > 0) ? note : @"",
   @"commanderName", commanderName,
   @"apiKey", apiKey
   ];
}

@end
