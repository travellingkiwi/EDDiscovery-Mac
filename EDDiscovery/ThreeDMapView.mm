//
//  ThreeDMapView.mm
//  EDDiscovery
//
//  Created by Hamish Marson on 08/08/2016.
//  Copyright © 2016 Hamish Marson. All rights reserved.
//


#import "ThreeDMapView.h"
#import "ThreeDMapRenderer.h"

@implementation ThreeDMapView {
  
@private
  __weak CAMetalLayer *_metalLayer;
  
  // Mouse Drag stuff...
  BOOL _dragging;
  NSPoint _lastDragLocation;
  
  
  BOOL _layerSizeDidUpdate;
  
  id <MTLTexture>  _depthTex;
  id <MTLTexture>  _stencilTex;
  id <MTLTexture>  _msaaTex;
}
@synthesize currentDrawable      = _currentDrawable;
@synthesize renderPassDescriptor = _renderPassDescriptor;

+ (Class)layerClass {
  return [CAMetalLayer class];
}

- (void)initCommon {
  self.wantsLayer = YES;
  self.layer = _metalLayer = [CAMetalLayer layer];
  
  
  NSArray *devarray = MTLCopyAllDevices();
  for (id devi in devarray) {
    NSLog(@"%s: device: %@", __FUNCTION__, [devi name]);
  }

  _device = MTLCreateSystemDefaultDevice();

  NSLog(@"%s: got default device %@", __FUNCTION__, [_device name]);

  _metalLayer.device          = _device;
  _metalLayer.pixelFormat     = MTLPixelFormatBGRA8Unorm;
  
  // this is the default but if we wanted to perform compute on the final rendering layer we could set this to no
  _metalLayer.framebufferOnly = YES;
}

- (id)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  
  NSLog(@"%s: (%s)", __FUNCTION__, "");

  if(self) {
    [self initCommon];
  }
  
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  
  NSLog(@"%s: (%s)", __FUNCTION__, "");

  if(self) {
    [self initCommon];
  }
  return self;
}

- (void)releaseTextures {
  _depthTex   = nil;
  _stencilTex = nil;
  _msaaTex    = nil;
}

- (void)setupRenderPassDescriptorForTexture:(id <MTLTexture>) texture {
  // create lazily
  if (_renderPassDescriptor == nil)
    _renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  // create a color attachment every frame since we have to recreate the texture every frame
  MTLRenderPassColorAttachmentDescriptor *colorAttachment = _renderPassDescriptor.colorAttachments[0];
  colorAttachment.texture = texture;
  
  // make sure to clear every frame for best performance
  colorAttachment.loadAction = MTLLoadActionClear;
  colorAttachment.clearColor = MTLClearColorMake(0.0f, 0.0f, 0.0f, 1.0f);
  
  // if sample count is greater than 1, render into using MSAA, then resolve into our color texture
  if(_sampleCount > 1) {
    BOOL doUpdate =     ( _msaaTex.width       != texture.width  )
    ||  ( _msaaTex.height      != texture.height )
    ||  ( _msaaTex.sampleCount != _sampleCount   );
    
    if(!_msaaTex || (_msaaTex && doUpdate)) {
      MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatBGRA8Unorm
                                                                                      width: texture.width
                                                                                     height: texture.height
                                                                                  mipmapped: NO];
      desc.textureType = MTLTextureType2DMultisample;
      
      // sample count was specified to the view by the renderer.
      // this must match the sample count given to any pipeline state using this render pass descriptor
      desc.sampleCount = _sampleCount;
      
      _msaaTex = [_device newTextureWithDescriptor: desc];
    }
    
    // When multisampling, perform rendering to _msaaTex, then resolve
    // to 'texture' at the end of the scene
    colorAttachment.texture = _msaaTex;
    colorAttachment.resolveTexture = texture;
    
    // set store action to resolve in this case
    colorAttachment.storeAction = MTLStoreActionMultisampleResolve;
  } else {
    // store only attachments that will be presented to the screen, as in this case
    colorAttachment.storeAction = MTLStoreActionStore;
  } // color0
  
  // Now create the depth and stencil attachments
  
  if(_depthPixelFormat != MTLPixelFormatInvalid) {
    BOOL doUpdate =     ( _depthTex.width       != texture.width  )
    ||  ( _depthTex.height      != texture.height )
    ||  ( _depthTex.sampleCount != _sampleCount   );
    
    if(!_depthTex || doUpdate) {
      //  If we need a depth texture and don't have one, or if the depth texture we have is the wrong size
      //  Then allocate one of the proper size
      MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: _depthPixelFormat
                                                                                      width: texture.width
                                                                                     height: texture.height
                                                                                  mipmapped: NO];
      
      desc.textureType = (_sampleCount > 1) ? MTLTextureType2DMultisample : MTLTextureType2D;
      desc.sampleCount = _sampleCount;
      desc.usage = MTLTextureUsageUnknown;
      desc.storageMode = MTLStorageModePrivate;
      
      _depthTex = [_device newTextureWithDescriptor: desc];
      
      MTLRenderPassDepthAttachmentDescriptor *depthAttachment = _renderPassDescriptor.depthAttachment;
      depthAttachment.texture = _depthTex;
      depthAttachment.loadAction = MTLLoadActionClear;
      depthAttachment.storeAction = MTLStoreActionDontCare;
      depthAttachment.clearDepth = 1.0;
    }
  } // depth
  
  if(_stencilPixelFormat != MTLPixelFormatInvalid) {
    BOOL doUpdate  =    ( _stencilTex.width       != texture.width  )
    ||  ( _stencilTex.height      != texture.height )
    ||  ( _stencilTex.sampleCount != _sampleCount   );
    
    if(!_stencilTex || doUpdate) {
      //  If we need a stencil texture and don't have one, or if the depth texture we have is the wrong size
      //  Then allocate one of the proper size
      MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: _stencilPixelFormat
                                                                                      width: texture.width
                                                                                     height: texture.height
                                                                                  mipmapped: NO];
      
      desc.textureType = (_sampleCount > 1) ? MTLTextureType2DMultisample : MTLTextureType2D;
      desc.sampleCount = _sampleCount;
      
      _stencilTex = [_device newTextureWithDescriptor: desc];
      
      MTLRenderPassStencilAttachmentDescriptor* stencilAttachment = _renderPassDescriptor.stencilAttachment;
      stencilAttachment.texture = _stencilTex;
      stencilAttachment.loadAction = MTLLoadActionClear;
      stencilAttachment.storeAction = MTLStoreActionDontCare;
      stencilAttachment.clearStencil = 0;
    }
  } //stencil
}

- (MTLRenderPassDescriptor *)renderPassDescriptor {
  id <CAMetalDrawable> drawable = self.currentDrawable;
  if(!drawable) {
    NSLog(@">> ERROR: Failed to get a drawable!");
    _renderPassDescriptor = nil;
  } else {
    [self setupRenderPassDescriptorForTexture: drawable.texture];
  }
  
  return _renderPassDescriptor;
}


- (id <CAMetalDrawable>)currentDrawable {
  if (_currentDrawable == nil)
    _currentDrawable = [_metalLayer nextDrawable];
  
  return _currentDrawable;
}

- (void)display {
  // Create autorelease pool per frame to avoid possible deadlock situations
  // because there are 3 CAMetalDrawables sitting in an autorelease pool.
  
  //NSLog(@"%s: (%s)", __FUNCTION__, "");

  @autoreleasepool {
    // handle display changes here
    if(_layerSizeDidUpdate) {
      // set the metal layer to the drawable size in case orientation or size changes
      CGSize drawableSize = self.bounds.size;
      
      // scale drawableSize so that drawable is 1:1 width pixels not 1:1 to points
      NSScreen* screen = self.window.screen ?: [NSScreen mainScreen];
      drawableSize.width *= screen.backingScaleFactor;
      drawableSize.height *= screen.backingScaleFactor;
      
      _metalLayer.drawableSize = drawableSize;
      
      // renderer delegate method so renderer can resize anything if needed
      [_delegate reshape:self];
      
      _layerSizeDidUpdate = NO;
    }
    
    // rendering delegate method to ask renderer to draw this frame's content
    [self.delegate render:self];
    
    // do not retain current drawable beyond the frame.
    // There should be no strong references to this object outside of this view class
    _currentDrawable    = nil;
  }
}

- (void)setFrameSize:(NSSize)newSize {
  [super setFrameSize:newSize];
  _layerSizeDidUpdate = YES;
}

- (void)setBoundsSize:(NSSize)newSize {
  [super setBoundsSize:newSize];
  _layerSizeDidUpdate = YES;
}
- (void)viewDidChangeBackingProperties {
  [super viewDidChangeBackingProperties];
  _layerSizeDidUpdate = YES;
}

#if 1

- (void)scrollWheel:(NSEvent *)theEvent {
  NSLog(@"%s: user scrolled %f horizontally and %f vertically", __FUNCTION__, [theEvent deltaX], [theEvent deltaY]);
  if([theEvent deltaY] < 0.0f ) {
    [_delegate zoom:0.95];
  } else if([theEvent deltaY] > 0.0f) {
    [_delegate zoom:1.05];
  }
}

-(void)mouseDown:(NSEvent *)event {
  NSPoint clickLocation;
  //BOOL itemHit=NO;
  
  // convert the click location into the view coords
  clickLocation = [self convertPoint:[event locationInWindow] fromView:nil];
  
  // did the click occur in the item?
  //itemHit = [self isPointInItem:clickLocation];
  
  // Yes it did, note that we're starting to drag
  //if (itemHit) {
    // flag the instance variable that indicates
    // a drag was actually started
    _dragging=YES;
    
    // store the starting click location;
    _lastDragLocation=clickLocation;
    
    // set the cursor to the closed hand cursor
    // for the duration of the drag
    [[NSCursor closedHandCursor] push];
  //}
}

-(void)mouseDragged:(NSEvent *)event {
  if (_dragging) {
    NSPoint newDragLocation=[self convertPoint:[event locationInWindow] fromView:nil];
    
    NSLog(@"%s: x %8.4f y %8.4f z %8.4f", __FUNCTION__, (newDragLocation.x-_lastDragLocation.x), (newDragLocation.y-_lastDragLocation.y), 0.0f);
    
    // Rotate...
    [_delegate rotateView:(newDragLocation.y-_lastDragLocation.y) y:(newDragLocation.x-_lastDragLocation.x) z:0.0f];
    
    // save the new drag location for the next drag event
    _lastDragLocation=newDragLocation;
    
    // support automatic scrolling during a drag
    // by calling NSView's autoscroll: method
    [self autoscroll:event];
  }
}

-(void)mouseUp:(NSEvent *)event {
  _dragging=NO;
  
  // finished dragging, restore the cursor
  [NSCursor pop];
  
  // the item has moved, we need to reset our cursor
  // rectangle
  //[[self window] invalidateCursorRectsForView:self];
}
#endif

- (BOOL)acceptsFirstResponder {
  NSLog(@"%s:", __FUNCTION__);
  return YES;
}

// -----------------------------------
// Handle KeyDown Events
// -----------------------------------
- (void)keyDown:(NSEvent *)event {
  BOOL handled = NO;
  NSString  *characters;
 
  // get the pressed key
  characters = [event charactersIgnoringModifiers];
  
  handled=[_delegate keyDown:characters keycode:[event keyCode]];
  
  if (!handled) {
    NSLog(@"%s: (%@) %u", __FUNCTION__, characters, [event keyCode]);
    [super keyDown:event];
  }
}

@end
