//
//  URLConnection.h
//  EDDiscovery
//
//  Created by Hamish Marson on 06/12/2018.
//  From https://gist.github.com/SQiShER/5009086
//

#import <Foundation/Foundation.h>

@interface URLConnection : NSObject <NSURLConnectionDataDelegate, NSURLConnectionDelegate>

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSURLResponse **)response
                             error:(NSError **)error;

@end
