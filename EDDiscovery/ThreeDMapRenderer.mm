//
//  NSObject+ThreeDMapRenderer.m
//  EDDiscovery
//
//  Created by Hamish Marson on 11/07/2016.
//  Copyright © 2016 Michele Noberasco. All rights reserved.
//

#import "ThreeDMapRenderer.h"

/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Metal Renderer for Metal Basic 3D. Acts as the update and render delegate for the view controller and performs rendering. In MetalBasic3D, the renderer draws 2 cubes, whos color values change every update.
 */

#import "AAPLTransforms.h"
#import "AAPLSharedTypes.h"

using namespace AAPL;
using namespace simd;

static const long kInFlightCommandBuffers = 3;

static const float4 kBoxAmbientColors[2] = {
  {0.18, 0.24, 0.8, 1.0},
  {0.8, 0.24, 0.1, 1.0}
};

static const float4 kBoxDiffuseColors[2] = {
  {0.4, 0.4, 1.0, 1.0},
  {0.8, 0.4, 0.4, 1.0}
};


#define DRAWAXES
#ifdef DRAWAXES
static const float sol_axes[42] = {
   0.0,  0.0,  0.0, 1.0, 0.0, 0.0, 1.0,
   5.0,  0.0,  0.0, 1.0, 0.0, 0.0, 1.0,
   0.0,  0.0,  0.0, 1.0, 0.0, 0.0, 1.0,
   0.0,  5.0,  0.0, 1.0, 0.0, 0.0, 1.0,
   0.0,  0.0,  0.0, 1.0, 0.0, 0.0, 1.0,
   0.0,  0.0,  5.0, 1.0, 0.0, 0.0, 1.0
};

#define SAGA_X    (25.21875/LY_2_MTL)
#define SAGA_Y   (-20.90625/LY_2_MTL)
#define SAGA_Z (25899.96875/LY_2_MTL)

#define AXES_LEN  5.0

static const float gal_axes[42] = {
  SAGA_X,          SAGA_Y,          SAGA_Z,          0.0, 0.0, !.0, 1.0,
  SAGA_X+AXES_LEN, SAGA_Y,          SAGA_Z,          0.0, 0.0, 1.0, 1.0,
  SAGA_X,          SAGA_Y,          SAGA_Z,          0.0, 0.0, 1.0, 1.0,
  SAGA_X,          SAGA_Y+AXES_LEN, SAGA_Z,          0.0, 0.0, 1.0, 1.0,
  SAGA_X,          SAGA_Y,          SAGA_Z,          0.0, 0.0, 1.0, 1.0,
  SAGA_X,          SAGA_Y,          SAGA_Z+AXES_LEN, 0.0, 0.0, 1.0, 1.0
};

#endif

static const float kFOVY    = 100.0f;
static const float3 kEye    = {15.0f,  5.0f,  5.0f};
static const float3 kCenter = { 0.0f,  0.0f,  0.0f};
static const float3 kUp     = { 0.0f,  1.0f,  0.0f};


galaxy_t *thisGalaxy;


@implementation ThreeDMapRenderer {
  // constant synchronization for buffering <kInFlightCommandBuffers> frames
  dispatch_semaphore_t _inflight_semaphore;
  id <MTLBuffer> _dynamicConstantBuffer[kInFlightCommandBuffers];
  
  // renderer global ivars
  id <MTLDevice> _device;
  id <MTLCommandQueue> _commandQueue;
  id <MTLLibrary> _defaultLibrary;
  id <MTLRenderPipelineState> _pipelineState;
  id <MTLDepthStencilState> _depthState;
  
  // globals used in update calculation
  float4x4 _projectionMatrix;
  float4x4 _viewMatrix;
  float _rotation;
  
  long _maxBufferBytesPerFrame;
  size_t _sizeOfConstantT;
  
  // this value will cycle from 0 to g_max_inflight_buffers whenever a display completes ensuring renderer clients
  // can synchronize between g_max_inflight_buffers count buffers, and thus avoiding a constant buffer from being overwritten between draws
  NSUInteger _constantDataBufferIndex;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    
    _sizeOfConstantT = sizeof(constants_t);
    
#pragma FIXME_NO_HARDCODE
    _maxBufferBytesPerFrame = 8192;
    
    _constantDataBufferIndex = 0;
    _inflight_semaphore = dispatch_semaphore_create(kInFlightCommandBuffers);
  }
  return self;
}

#pragma mark Configure

- (void)configure:(ThreeDMapView *)view  galaxy:(galaxy_t *)galaxy {
  NSLog(@"%s: (%s)", __FUNCTION__, "Configuring 3D Map View");

  // find a usable Device
  _device = view.device;
  
  // setup view with drawable formats
  view.depthPixelFormat   = MTLPixelFormatDepth32Float;
  view.stencilPixelFormat = MTLPixelFormatInvalid;
  view.sampleCount        = 1;
  
  // create a new command queue
  _commandQueue = [_device newCommandQueue];
  
  _defaultLibrary = [_device newDefaultLibrary];
  if(!_defaultLibrary) {
    NSLog(@">> ERROR: Couldnt create a default shader library");
    // assert here becuase if the shader libary isn't loading, nothing good will happen
    assert(0);
  }
  
  if (![self preparePipelineState:view]) {
    NSLog(@">> ERROR: Couldnt create a valid pipeline state");
    
    // cannot render anything without a valid compiled pipeline state object.
    assert(0);
  }
  
  MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
  depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
  depthStateDesc.depthWriteEnabled = YES;
  _depthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];
  
  // allocate a number of buffers in memory that matches the sempahore count so that
  // we always have one self contained memory buffer for each buffered frame.
  // In this case triple buffering is the optimal way to go so we cycle through 3 memory buffers
  for (int i = 0; i < kInFlightCommandBuffers; i++) {
    _dynamicConstantBuffer[i] = [_device newBufferWithLength:_maxBufferBytesPerFrame options:0];
    _dynamicConstantBuffer[i].label = [NSString stringWithFormat:@"ConstantBuffer%i", i];
    
    // write initial color values for both cubes (at each offset).
    // Note, these will get animated during update
    constants_t *constant_buffer = (constants_t *)[_dynamicConstantBuffer[i] contents];
    for (int j = 0; j < 1; j++) {
      if (j%2==0) {
        constant_buffer[j].multiplier = 1;
        constant_buffer[j].ambient_color = kBoxAmbientColors[0];
        constant_buffer[j].diffuse_color = kBoxDiffuseColors[0];
      }
      else {
        constant_buffer[j].multiplier = -1;
        constant_buffer[j].ambient_color = kBoxAmbientColors[1];
        constant_buffer[j].diffuse_color = kBoxDiffuseColors[1];
      }
    }
  }
  
  thisGalaxy=galaxy;
}

- (void)setVertexBuffer:(galaxy_t *)galaxy {

  // setup the vertex buffers
  //_vertexBuffer = [_device newBufferWithBytes:kCubeVertexData length:sizeof(kCubeVertexData) options:MTLResourceOptionCPUCacheModeDefault];
  if((galaxy!=nil) && (galaxy->first_journey_block!=nil)) {
#if 0
    NSLog(@"%s: Setting with %d jumps", __FUNCTION__, galaxy->first_journey_block->numsystems);
    _vertexBuffer = [_device newBufferWithBytes:galaxy->first_journey_block->systems length:sizeof(JourneyVertex_t)*galaxy->first_journey_block->numsystems options:MTLResourceOptionCPUCacheModeDefault];
    _vertexBuffer.label = @"Vertices";
#endif
    
  } else {
    if(galaxy==nil) {
      NSLog(@"%s: No jumps (NIL Galaxy)", __FUNCTION__);
    } else if(galaxy->first_journey_block==nil) {
      NSLog(@"%s: No jumps (first_journey_block == nil)", __FUNCTION__);
    } else {
      NSLog(@"%s: No jumps (first_journey_block->numsystems==0)", __FUNCTION__);
    }
  }

}

- (BOOL)preparePipelineState:(ThreeDMapView *)view {
  NSLog(@"%s: (%s)", __FUNCTION__, "PREPARING PIPELINE");

  // get the fragment function from the library
  id <MTLFunction> fragmentProgram = [_defaultLibrary newFunctionWithName:@"journey_fragment"];
  if(!fragmentProgram) {
    NSLog(@">> ERROR: Couldn't load journey fragment function from default library");
    exit(-1);
  }
  
  // get the vertex function from the library
  id <MTLFunction> vertexProgram = [_defaultLibrary newFunctionWithName:@"journey_vertex"];
  if(!vertexProgram) {
    NSLog(@">> ERROR: Couldn't load journey vertex function from default library");
    exit(-1);
  }
  
#if 0
  // setup the vertex buffers
  //_vertexBuffer = [_device newBufferWithBytes:kCubeVertexData length:sizeof(kCubeVertexData) options:MTLResourceOptionCPUCacheModeDefault];
  if((thisGalaxy!=nil) && (thisGalaxy->first_journey_block!=nil)) {
    _vertexBuffer = [_device newBufferWithBytes:thisGalaxy->first_journey_block->systems length:sizeof(JourneyVertex_t)*thisGalaxy->first_journey_block->numsystems options:MTLResourceOptionCPUCacheModeDefault];
    _vertexBuffer.label = @"Vertices";
  }
#endif
#if 0
  // Set dynamically in each render frame...
  [self setVertexBuffer:thisGalaxy];
#endif
  
  // create a pipeline state descriptor which can be used to create a compiled pipeline state object
  MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
  
  pipelineStateDescriptor.label                           = @"MyPipeline";
  pipelineStateDescriptor.sampleCount                     = view.sampleCount;
  pipelineStateDescriptor.vertexFunction                  = vertexProgram;
  pipelineStateDescriptor.fragmentFunction                = fragmentProgram;
  pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  pipelineStateDescriptor.depthAttachmentPixelFormat      = view.depthPixelFormat;
  
  // create a compiled pipeline state object. Shader functions (from the render pipeline descriptor)
  // are compiled when this is created unlessed they are obtained from the device's cache
  NSError *error = nil;
  _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
  if(!_pipelineState) {
    NSLog(@">> ERROR: Failed Aquiring pipeline state: %@", error);
    return NO;
  }
  
  return YES;
}

#pragma mark Render

- (void)render:(ThreeDMapView *)view {
  NSLog(@"%s: rendering", __FUNCTION__);
  // Allow the renderer to preflight 3 frames on the CPU (using a semapore as a guard) and commit them to the GPU.
  // This semaphore will get signaled once the GPU completes a frame's work via addCompletedHandler callback below,
  // signifying the CPU can go ahead and prepare another frame.
  dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);
  
  // Prior to sending any data to the GPU, constant buffers should be updated accordingly on the CPU.
  [self updateConstantBuffer];
  
  // create a new command buffer for each renderpass to the current drawable
  id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
  
  // create a render command encoder so we can render into something
  MTLRenderPassDescriptor *renderPassDescriptor = view.renderPassDescriptor;
  if (renderPassDescriptor) {
    id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [renderEncoder pushDebugGroup:@"Journey"];
    [renderEncoder setDepthStencilState:_depthState];
    [renderEncoder setRenderPipelineState:_pipelineState];
    
    journey_block_t *jb=thisGalaxy->first_journey_block;
    for (int i = 0; i < thisGalaxy->num_journey_blocks; i++) {
      NSLog(@"%s: %d systems block %d of %d", __FUNCTION__, jb->numsystems, i, thisGalaxy->num_journey_blocks);

      id <MTLBuffer> _vertexBuffer;

      _vertexBuffer = [_device newBufferWithBytes:jb->systems length:sizeof(JourneyVertex_t)*jb->numsystems options:MTLResourceOptionCPUCacheModeDefault];
      _vertexBuffer.label = @"Vertices";
      
      //  set vertex buffer for each journey segment
      [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0 ];
      [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];

      // tell the render context we want to draw our primitives
      [renderEncoder drawPrimitives:MTLPrimitiveTypeLineStrip vertexStart:0 vertexCount:jb->numsystems];
      NSLog(@"%s: encoded MTLPrimitiveTypeLineStrip vertexcount %d", __FUNCTION__, jb->numsystems);
      jb=jb->next;
    }
    
#ifdef DRAWAXES
    // Draw the axes....
    id <MTLBuffer> _sol_axesBuffer;
    _sol_axesBuffer = [_device newBufferWithBytes:sol_axes length:sizeof(float)*42 options:MTLResourceOptionCPUCacheModeDefault];
    _sol_axesBuffer.label = @"SolAxes";
    
    //  set vertex buffer for each journey segment
    [renderEncoder setVertexBuffer:_sol_axesBuffer offset:0 atIndex:0 ];
    [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
    
    [renderEncoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:6];
    NSLog(@"%s: encoded Sol Axes MTLPrimitiveTypeLine vertexcount %d", __FUNCTION__, 6);
    
    id <MTLBuffer> _gal_axesBuffer;
    _gal_axesBuffer = [_device newBufferWithBytes:gal_axes length:sizeof(float)*42 options:MTLResourceOptionCPUCacheModeDefault];
    _gal_axesBuffer.label = @"GalAxes";
    
    //  set vertex buffer for each journey segment
    [renderEncoder setVertexBuffer:_gal_axesBuffer offset:0 atIndex:0 ];
    [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
    
    [renderEncoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:6];
    NSLog(@"%s: encoded Gal Axes MTLPrimitiveTypeLine vertexcount %d", __FUNCTION__, 6);
    
    
    
#endif
    
    [renderEncoder endEncoding];
    [renderEncoder popDebugGroup];
    
    // schedule a present once rendering to the framebuffer is complete
    [commandBuffer presentDrawable:view.currentDrawable];
  }
  
  // call the view's completion handler which is required by the view since it will signal its semaphore and set up the next buffer
  __block dispatch_semaphore_t block_sema = _inflight_semaphore;
  [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    
    // GPU has completed rendering the frame and is done using the contents of any buffers previously encoded on the CPU for that frame.
    // Signal the semaphore and allow the CPU to proceed and construct the next frame.
    dispatch_semaphore_signal(block_sema);
  }];
  
  // finalize rendering here. this will push the command buffer to the GPU
  [commandBuffer commit];
  
  // This index represents the current portion of the ring buffer being used for a given frame's constant buffer updates.
  // Once the CPU has completed updating a shared CPU/GPU memory buffer region for a frame, this index should be updated so the
  // next portion of the ring buffer can be written by the CPU. Note, this should only be done *after* all writes to any
  // buffers requiring synchronization for a given frame is done in order to avoid writing a region of the ring buffer that the GPU may be reading.
  _constantDataBufferIndex = (_constantDataBufferIndex + 1) % kInFlightCommandBuffers;
}

- (void)reshape:(ThreeDMapView *)view {
  // when reshape is called, update the view and projection matricies since this means the view orientation or size changed
  float aspect = fabs(view.bounds.size.width / view.bounds.size.height);
  _projectionMatrix = perspective_fov(kFOVY, aspect, 0.1f, 100.0f);
  _viewMatrix = lookAt(kEye, kCenter, kUp);
  
  NSLog(@"%s: (reshaped aspect=%8.4f)", __FUNCTION__, aspect);
  
}

#pragma mark Update

// called every frame
- (void)updateConstantBuffer {
  float4x4 baseModelViewMatrix = translate(0.0f, 0.0f, 5.0f) * rotate(_rotation, 0.0f, 1.0f, 0.0f);
  baseModelViewMatrix = _viewMatrix * baseModelViewMatrix;
  
  constants_t *constant_buffer = (constants_t *)[_dynamicConstantBuffer[_constantDataBufferIndex] contents];
  
  simd::float4x4 modelViewMatrix = AAPL::translate(0.0f, 0.0f, 1.5f) * AAPL::rotate(_rotation, 0.0f, 1.0f, 0.0f);
  modelViewMatrix = baseModelViewMatrix * modelViewMatrix;

  int i=0;
  
  constant_buffer[i].normal_matrix = inverse(transpose(modelViewMatrix));
  constant_buffer[i].modelview_projection_matrix = _projectionMatrix * modelViewMatrix;
    
  // change the color each frame
  // reverse direction if we've reached a boundary
  if (constant_buffer[i].ambient_color.y >= 0.8) {
    constant_buffer[i].multiplier = -1;
    constant_buffer[i].ambient_color.y = 0.79;
  } else if (constant_buffer[i].ambient_color.y <= 0.2) {
    constant_buffer[i].multiplier = 1;
    constant_buffer[i].ambient_color.y = 0.21;
  } else {
    constant_buffer[i].ambient_color.y += constant_buffer[i].multiplier * 0.01*i;
  }
  NSLog(@"%s: matrix ambient_colour %8.4f rotation %8.4f", __FUNCTION__, constant_buffer[i].ambient_color.y, _rotation);
}

// just use this to update app globals
- (void)update:(ThreeDMapViewController *)controller {
  _rotation += controller.timeSinceLastDraw * 5.0f;
  
#if 0
  if(_rotation>1000.0) {
    _rotation=0.0;
  }
#endif
  
}

- (void)viewController:(ThreeDMapViewController *)controller willPause:(BOOL)pause {
  // timer is suspended/resumed
  // Can do any non-rendering related background work here when suspended
  NSLog(@"%s: willPause is %d", __FUNCTION__, pause);

}


@end

