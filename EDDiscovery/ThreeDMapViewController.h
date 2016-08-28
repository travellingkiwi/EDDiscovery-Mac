//
//  3DMapViewController.h
//  EDDiscovery
//
//  3D Views by Hamish Marson <hamish@travellingkiwi.com> 10/07/2016
//  Copyright © 2016 Hamish Marson. All rights reserved.
//
//  Based on Apple MetalRenderer example

#import <AppKit/AppKit.h>
#import <simd/simd.h>
#import <Metal/Metal.h>
#import "NetLogParser.h"

#define LY_2_MTL 300.0

@protocol ThreeDMapViewControllerDelegate;

@interface ThreeDMapViewController : NSViewController

@property (nonatomic, weak) id <ThreeDMapViewControllerDelegate> delegate;

// the time interval from the last draw
@property (nonatomic, readonly) NSTimeInterval timeSinceLastDraw;

// What vsync refresh interval to fire at. (Sets CADisplayLink frameinterval property)
// set to 1 by default, which is the CADisplayLink default setting (60 FPS).
// Setting to 2, will cause gameloop to trigger every other vsync (throttling to 30 FPS)
@property (nonatomic) NSUInteger interval;

// Used to pause and resume the controller.
@property (nonatomic, getter=isPaused) BOOL paused;

// use invalidates the main game loop. when the app is set to terminate
- (void)stopGameLoop;
- (void)jumpToSystem:(System * __nonnull)system;

@end

// required view controller delegate functions.
@protocol ThreeDMapViewControllerDelegate <NSObject>
@required

// Note this method is called from the thread the main game loop is run
- (void)update:(ThreeDMapViewController *)controller;

// called whenever the main game loop is paused, such as when the app is backgrounded
- (void)viewController:(ThreeDMapViewController *)controller willPause:(BOOL)pause;


@end

