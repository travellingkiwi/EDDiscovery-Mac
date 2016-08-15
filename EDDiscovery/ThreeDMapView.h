//
//  ThreeDMapView.h
//  EDDiscovery
//
//  Created by Hamish Marson on 08/08/2016.
//  Copyright © 2016 Hamish Marson. All rights reserved.
//


#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>

#import <AppKit/AppKit.h>


@protocol ThreeDMapViewDelegate;

@interface ThreeDMapView : NSView {
  
  
}

- (BOOL)acceptsFirstResponder;
- (void)keyDown:(NSEvent *)event;

@property (nonatomic, weak) id <ThreeDMapViewDelegate> delegate;

// view has a handle to the metal device when created
@property (nonatomic, readonly) id <MTLDevice> device;

// the current drawable created within the view's CAMetalLayer
@property (nonatomic, readonly) id <CAMetalDrawable> currentDrawable;

// The current framebuffer can be read by delegate during -[MetalViewDelegate render:]
// This call may block until the framebuffer is available.
@property (nonatomic, readonly) MTLRenderPassDescriptor *renderPassDescriptor;

// set these pixel formats to have the main drawable framebuffer get created with depth and/or stencil attachments
@property (nonatomic) MTLPixelFormat depthPixelFormat;
@property (nonatomic) MTLPixelFormat stencilPixelFormat;
@property (nonatomic) NSUInteger     sampleCount;

- (void)display;                              // view controller will be call off the main thread
- (void)releaseTextures;                      // release any color/depth/stencil resources. view controller will call when paused.

@end

// rendering delegate (App must implement a rendering delegate that responds to these messages
@protocol ThreeDMapViewDelegate <NSObject>
@required
- (void)reshape:(ThreeDMapView *)view;        // called if the view changes orientation or size, renderer can precompute its view and projection matricies here for example
- (void)render:(ThreeDMapView *)view;         // delegate should perform all rendering here
- (void)toggleFeature:(int)feature;
- (void)zoom:(float)direction;
- (BOOL)keyDown:(NSString *)characters;

@end


