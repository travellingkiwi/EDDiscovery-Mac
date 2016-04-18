//
//  System.m
//  EDDiscovery
//
//  Created by thorin on 18/04/16.
//  Copyright © 2016 Moonrays. All rights reserved.
//

#import "System.h"
#import "Distance.h"
#import "Image.h"
#import "Jump.h"

@implementation System

+ (System *)systemWithName:(NSString *)name inContext:(NSManagedObjectContext *)context {
  NSString            *className = NSStringFromClass([System class]);
  NSFetchRequest      *request   = [[NSFetchRequest alloc] init];
  NSEntityDescription *entity    = [NSEntityDescription entityForName:className inManagedObjectContext:context];
  NSPredicate         *predicate = [NSPredicate predicateWithFormat:@"name == %@", name];
  NSError             *error     = nil;
  NSArray             *array     = nil;
  
  request.entity    = entity;
  request.predicate = predicate;
  
  array = [context executeFetchRequest:request error:&error];
  
  NSAssert1(error == nil, @"could not execute fetch request: %@", error);
  NSAssert2(array.count <= 1, @"this query should return at maximum 1 element: got %lu instead (name %@)", (unsigned long)array.count, name);
  
  return array.lastObject;
}

@end
