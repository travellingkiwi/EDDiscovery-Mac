//
//  backLoader.h
//  EDDiscovery
//
//  Created by Hamish Marson on 08/08/2016.
//  Copyright © 2016 Hamish Marson. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ThreeDMaprenderer.h"

@interface backLoader : NSObject <NSURLSessionDelegate, NSURLSessionDataDelegate> {
  
  
}

- (id)startEDDB:(galaxy_t *)theGalaxy;

@end
