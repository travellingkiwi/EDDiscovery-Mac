//
//  NSManagedObjectContext+DeepSave.m
//  EDDiscovery
//
//  Created by thorin on 09/05/16.
//  Copyright © 2016 Michele Noberasco. All rights reserved.
//

#import "NSManagedObjectContext+Parenthood.h"
#import "CoreDataManager.h"

@implementation NSManagedObjectContext (Parenthood)

+ (NSManagedObjectContext *)mainContext {
  static NSManagedObjectContext *mainContext = nil;
  
  if (mainContext == nil) {
    NSPersistentStoreCoordinator *coordinator = CoreDataManager.instance.persistentStoreCoordinator;
    
    if (coordinator != nil) {
      mainContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
      
      [mainContext setPersistentStoreCoordinator:coordinator];
    
      NSLog(@"Set mainContext.undoManager=nil");
      mainContext.undoManager = nil;

    }
  }
  
  return mainContext;
}

+ (NSManagedObjectContext *)workContext {
  static NSManagedObjectContext *workContext = nil;
  
  if (workContext == nil) {
    workContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    
    workContext.parentContext = self.mainContext;
    NSLog(@"Set workContext.undoManager=nil");
    workContext.undoManager = nil;
  }
  
  return workContext;
}

- (void)save {
  [self performBlockAndWait:^{
    NSError *error = nil;
    
    [self save:&error];
    
    NSAssert1(error == nil, @"ERROR: could not save context: %@", error.localizedDescription);
    
    if (error != nil) {
      exit(-1);
    }
    
    if (self.parentContext != nil) {
      [self.parentContext save];
    }
  }];
}

@end
