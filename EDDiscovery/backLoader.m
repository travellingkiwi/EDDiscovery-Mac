//
//  backLoader.m
//  EDDiscovery
//
//  Created by Hamish Marson on 08/08/2016.
//  Copyright © 2016 Hamish Marson. All rights reserved.
//


#import "backLoader.h"
#import "ThreeDMapRenderer.h"

//
// Experimental at the moment...

//
// Hard-Coded? Are you kidding Hamish?
#warning Don't Hard-Code Stuff Hamish!
#define STATION_FILE "file:///Users/hamish/Source/EDDiscovery-Mac/Data/stations.json"
#define SYSTEMS_FILE "file:///Users/hamish/Source/EDDiscovery-Mac/Data/systems.json"

#define DOWNLOAD_IDLE
#define DOWNLOAD_SYSTEMS  1
#define DOWNLOAD_STATION  2

@implementation backLoader  {
@private
  int downloadType;
  
  unsigned long long recvBytes;
  unsigned long long expectedBytes;
  
  NSMutableData *recvData;
  
  galaxy_t *galaxy;
}


- (id)init {

  return self;
}

// called when loaded from storyboard
- (id)startEDDB:(galaxy_t *)theGalaxy {
  NSLog(@"%s:", __FUNCTION__);
  
  galaxy=theGalaxy;
  
  recvData=[NSMutableData data];

  NSLog(@"%s: data from %s is %lu Bytes", __FUNCTION__, SYSTEMS_FILE, recvData.length);
  
  NSURLSessionConfiguration *config=[NSURLSessionConfiguration defaultSessionConfiguration];
  NSOperationQueue *queue=[NSOperationQueue mainQueue];
  NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:queue];
  NSURLSessionDataTask *dataTask = [session dataTaskWithURL:[NSURL URLWithString:@SYSTEMS_FILE]];
  downloadType=DOWNLOAD_SYSTEMS;
  
  NSLog(@"%s: Resuming the systems download", __FUNCTION__);
  //dispatch_async(dispatch_get_main_queue(), ^{
    [dataTask resume];
  //});
  
  return self;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
  unsigned long long remainBytes;
  
  recvBytes+=data.length;
  remainBytes=expectedBytes-recvBytes;
  
  NSLog(@"%s: BYTES %lu kB %lu MB %lu TOTAL(%llu kB %llu MB %llu) REMAIN(%llu kB %llu MB %llu)", __FUNCTION__,
          data.length, data.length/1024, data.length/(1024*1024),
          recvBytes, recvBytes/1024, recvBytes/(1024*1024),
          remainBytes, remainBytes/1024, remainBytes/(1024*1024));
  [recvData appendData:data];
  
  if(remainBytes==0) {
    switch(downloadType) {
    case DOWNLOAD_SYSTEMS : {
      NSLog(@"%s: DOWNLOAD_SYSTEMS completed - starting processing", __FUNCTION__);
      // We've recieved all the data we were expecting... So now kick off a thread in the background to load it...
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSError *jsonParsingError = nil;
        NSArray *publicTimeline = [NSJSONSerialization JSONObjectWithData:recvData options:0 error:&jsonParsingError];
        
        NSDictionary *system;
        for(int i=0; i < [publicTimeline count];i++) {
          system = [publicTimeline objectAtIndex:i];
          //NSLog(@"%s: %@", __FUNCTION__, system);
          
          // Get the system that relates to the name...
          
          
        }
        // Empty the removed data so we can fill it up with the stations...
        [recvData setLength:0];
      
        NSURLSessionConfiguration *config=[NSURLSessionConfiguration defaultSessionConfiguration];
        NSOperationQueue *queue=[NSOperationQueue mainQueue];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:queue];
        NSURLSessionDataTask *dataTask = [session dataTaskWithURL:[NSURL URLWithString:@STATION_FILE]];
        
        NSLog(@"%s: Resuming the stations download", __FUNCTION__);
        downloadType=DOWNLOAD_STATION;
        // resume has to be handled by the mian thread...
        dispatch_async(dispatch_get_main_queue(), ^{
          [dataTask resume];
        });
      });
    }
    break;

    case DOWNLOAD_STATION : {
      NSLog(@"%s: DOWNLOAD_STATION completed - starting processing", __FUNCTION__);
      // We've recieved all the data we were expecting... So now kick off a thread in the background to load it...
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSError *jsonParsingError = nil;
        NSArray *publicTimeline = [NSJSONSerialization JSONObjectWithData:recvData options:0 error:&jsonParsingError];
      
        NSDictionary *station;
        for(int i=0; i < [publicTimeline count];i++) {
          station = [publicTimeline objectAtIndex:i];
          NSLog(@"%s: %@", __FUNCTION__, station);
        
          // Get the system that relates to the name...
        
          // And add the station to it...
        
        }
      });
    }
    break;

    default : {
      NSLog(@"%s: Complection of unknown download", __FUNCTION__);

      }
      break;
    }
    
  }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask willCacheResponse:(NSCachedURLResponse *)proposedResponse completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {
  NSLog(@"%s: proposedResponse ", __FUNCTION__);
  
  NSData *response =[proposedResponse data];
  NSError *jsonParsingError = nil;
  NSArray *publicTimeline = [NSJSONSerialization JSONObjectWithData:response options:0 error:&jsonParsingError];
  
  NSDictionary *system;
  for(int i=0; i < [publicTimeline count];i++) {
    system = [publicTimeline objectAtIndex:i];
    NSLog(@"%s: %@", __FUNCTION__, system);
    
    // Get the system that relates to the name...
    
    
    // And update it...
    
    
    
  }

  
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
  
  self->expectedBytes=[response expectedContentLength];
  NSLog(@"%s: Download Started expecting %llu Bytes", __FUNCTION__, self->expectedBytes);

  self->recvBytes=0;
  
#if 0
  receivedData=nil; receivedData=[[NSMutableData alloc] init];
  [receivedData setLength:0];
#endif
  
  
  completionHandler(NSURLSessionResponseAllow);
}

@end
