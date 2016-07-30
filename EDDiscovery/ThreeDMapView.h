/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 View for Metal Sample Code. Manages screen drawable framebuffers and expects a delegate to repond to render commands to perform drawing.
 */

#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>

#import <AppKit/AppKit.h>


@protocol ThreeDMapViewDelegate;

@interface ThreeDMapView : NSView
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

// view controller will be call off the main thread
- (void)display;

// release any color/depth/stencil resources. view controller will call when paused.
- (void)releaseTextures;

@end

// rendering delegate (App must implement a rendering delegate that responds to these messages
@protocol ThreeDMapViewDelegate <NSObject>

@required
// called if the view changes orientation or size, renderer can precompute its view and projection matricies here for example
- (void)reshape:(ThreeDMapView *)view;

// delegate should perform all rendering here
- (void)render:(ThreeDMapView *)view;

@end
