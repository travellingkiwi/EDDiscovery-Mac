//
//  ThreeDMapRenderer.h
//  EDDiscovery
//
//  3D Views by Hamish Marson <hamish@travellingkiwi.com> 10/07/2016
//  Copyright © 2016 Hamish Marson. All rights reserved.
//
//  Based on Apple MetalRenderer example

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#import "ThreeDMapRenderer.h"

#import "AAPLTransforms.h"
#import "AAPLSharedTypes.h"

#import "Jump.h"

using namespace AAPL;
using namespace simd;

//
// How many buffers to use in parallel for drawing... Apple use 3 (Triple Buffering) in their examples.
static const long kInFlightCommandBuffers = 4;

#if 0
static const float4 kBoxAmbientColors[2] = {
  {0.18, 0.24, 0.8, 1.0},
  {0.8, 0.24, 0.1, 1.0}
};

static const float4 kBoxDiffuseColors[2] = {
  {0.4, 0.4, 1.0, 1.0},
  {0.8, 0.4, 0.4, 1.0}
};
#endif

#define DRAWJOURNEY
#define DRAWGALAXY
#define DRAWAXES

#ifdef DRAWAXES
#define AXES_LEN  500.0/LY_2_MTL

#define SOLS_X    0.0
#define SOLS_Y    0.0
#define SOLS_Z    0.0

#define START_EYE_X  1000.0
#define START_EYE_Y   000.0
#define START_EYE_Z  1000.0

#define POINT_SCALE     5.0

static const float sol_axes[42] = {
  SOLS_X-AXES_LEN, SOLS_Y,          SOLS_Z,
  SOLS_X+AXES_LEN, SOLS_Y,          SOLS_Z,
  SOLS_X,          SOLS_Y-AXES_LEN, SOLS_Z,
  SOLS_X,          SOLS_Y+AXES_LEN, SOLS_Z,
  SOLS_X,          SOLS_Y,          SOLS_Z-AXES_LEN,
  SOLS_X,          SOLS_Y,          SOLS_Z+AXES_LEN,
};

#define SAGA_X    (25.21875/LY_2_MTL)
#define SAGA_Y   (-20.90625/LY_2_MTL)
#define SAGA_Z (25899.96875/LY_2_MTL)

static const float gal_axes[42] = {
  SAGA_X-AXES_LEN, SAGA_Y,          SAGA_Z,
  SAGA_X+AXES_LEN, SAGA_Y,          SAGA_Z,
  SAGA_X,          SAGA_Y-AXES_LEN, SAGA_Z,
  SAGA_X,          SAGA_Y+AXES_LEN, SAGA_Z,
  SAGA_X,          SAGA_Y,          SAGA_Z-AXES_LEN,
  SAGA_X,          SAGA_Y,          SAGA_Z+AXES_LEN
};

#endif

static const float kFOVY    = 65.0f;
static const float3 kUp     = { 0.0f,  1.0f,  0.0f};

float model_scale = 1.0f;

//
static float3 kCentre = { 0.0f,  0.0f,  0.0f};
static float3 kEye    = {START_EYE_X/LY_2_MTL, START_EYE_Y/LY_2_MTL, START_EYE_Z/LY_2_MTL};


galaxy_t *thisGalaxy;

#define COLOUR_IND_STAR     0
#define COLOUR_IND_JOURNEY  1
#define COLOUR_IND_JSTAR    2
#define COLOUR_IND_AXES_SOL 3
#define COLOUR_IND_AXES_SAG 4
#define COLOUR_IND_STATION  5

#define MAX_COLOUR_INDEX    6

static const float4 colours[MAX_COLOUR_INDEX]= {
  { 1.0, 1.0, 0.0, 1.0},                             // COLOUR_IND_STAR
  { 0.0, 1.0, 0.0, 1.0},                             // COLOUR_IND_JOURNEY
  { 1.0, 1.0, 1.0, 1.0},                             // COLOUR_IND_JSTAR
  { 1.0, 0.0, 0.0, 1.0},                             // COLOUR_IND_AXES_SOL
  { 0.0, 0.0, 1.0, 1.0},                             // COLOUR_IND_AXE
  { 1.0, 0.0, 1.0, 1.0},                             // COLOUR_IND_STATION
};

#define POINT_IND_DEFAULT 0
#define POINT_IND_JSTAR   1
#define POINT_IND_BLINE   2
#define POINT_IND_STATION 3
#define MAX_POINT_SIZES   4

static const float pointsize[MAX_POINT_SIZES]={1.0, 15.00, 20.000, 15.00};

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

static char *features[MAX_FEATURES] = {
  "Journey", "JStars", "Stations",
};

static BOOL enabled[MAX_FEATURES] = {1, 1, 1};

- (void)setPosition:(float)x y:(float)y z:(float)z  {
  kCentre[0]=x;
  kCentre[1]=y;
  kCentre[2]=z;
  
  //kEye[0]=kCentre[0]+10.0f;
  //kEye[1]=kCentre[1]+5.0f;
  //kEye[2]=kCentre[2]+5.0f;
  kEye[0]=kCentre[0]+(START_EYE_X/LY_2_MTL);
  kEye[1]=kCentre[1]+(START_EYE_Y/LY_2_MTL);
  kEye[2]=kCentre[2]+(START_EYE_Z/LY_2_MTL);
  
  NSLog(@"%s: kCentre set [%8.4f %8.4f %8.4f]", __FUNCTION__, kCentre[0], kCentre[1], kCentre[2]);
  NSLog(@"%s: kEye    set [%8.4f %8.4f %8.4f]", __FUNCTION__, kEye[0], kEye[1], kEye[2]);
  
}

- (instancetype)init {
  self = [super init];
  if (self) {
    
    _sizeOfConstantT = sizeof(constants_t);
    
#warning FIXME_NO_HARDCODE
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
        // constant_buffer[j].ambient_color = kBoxAmbientColors[0];
        // constant_buffer[j].diffuse_color = kBoxDiffuseColors[0];
      }
      else {
        constant_buffer[j].multiplier = -1;
        // constant_buffer[j].ambient_color = kBoxAmbientColors[1];
        // constant_buffer[j].diffuse_color = kBoxDiffuseColors[1];
      }
    }
  }
  
  thisGalaxy=galaxy;


}

- (void)setVertexBuffer:(galaxy_t *)galaxy {
  NSLog(@"%s:", __FUNCTION__);

  // setup the vertex buffers
  if((galaxy!=nil) && (galaxy->first_journey_block!=nil)) {
    
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
#ifdef DEBUG_RENDER
  NSLog(@"%s: rendering", __FUNCTION__);
#endif
  // Allow the renderer to preflight 3 frames on the CPU (using a semapore as a guard) and commit them to the GPU.
  // This semaphore will get signaled once the GPU completes a frame's work via addCompletedHandler callback below,
  // signifying the CPU can go ahead and prepare another frame.
  dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);
  
  // Prior to sending any data to the GPU, constant buffers should be updated accordingly on the CPU.
  [self updateConstantBuffer];
  
  // create a new command buffer for each renderpass to the current drawable
  id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
  
  // create a render command encoder so we can render into something
  MTLRenderPassDescriptor *renderPassDescriptor =view.renderPassDescriptor;
  if (renderPassDescriptor) {

    id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

    [renderEncoder setDepthStencilState:_depthState];
    [renderEncoder setRenderPipelineState:_pipelineState];
 
#ifdef DRAWAXES
    // Draw the axes....
    [renderEncoder pushDebugGroup:@"Axes"];

    simd::float4 axes_colour_sol;
    axes_colour_sol[0]=1.0;
    axes_colour_sol[1]=0.0;
    axes_colour_sol[2]=0.0;
    axes_colour_sol[3]=1.0;
    
    id <MTLBuffer> _sol_axesBuffer;
    _sol_axesBuffer = [_device newBufferWithBytes:sol_axes length:sizeof(float)*42 options:MTLResourceOptionCPUCacheModeDefault];
    _sol_axesBuffer.label = @"SolAxes";
    
    //  set vertex buffer for each journey segment
    [renderEncoder setVertexBuffer:_sol_axesBuffer offset:0 atIndex:0 ];
    [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
    [renderEncoder setVertexBytes:&colours[COLOUR_IND_AXES_SOL] length:sizeof(float4) atIndex:2 ];
    [renderEncoder setVertexBytes:&pointsize[POINT_IND_DEFAULT] length:sizeof(float) atIndex:3 ];
    
    [renderEncoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:6];
#ifdef DEBUG_RENDER
    NSLog(@"%s: encoded Sol Axes MTLPrimitiveTypeLine vertexcount %d", __FUNCTION__, 6);
#endif
    
    simd::float4 axes_colour_saga;
    axes_colour_saga[0]=0.0;
    axes_colour_saga[1]=0.0;
    axes_colour_saga[2]=1.0;
    axes_colour_saga[3]=1.0;
    
    id <MTLBuffer> _gal_axesBuffer;
    _gal_axesBuffer = [_device newBufferWithBytes:gal_axes length:sizeof(float)*42 options:MTLResourceOptionCPUCacheModeDefault];
    _gal_axesBuffer.label = @"GalAxes";
    
    //  set vertex buffer for each journey segment
    [renderEncoder setVertexBuffer:_gal_axesBuffer offset:0 atIndex:0 ];
    [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
    [renderEncoder setVertexBytes:&colours[COLOUR_IND_AXES_SAG] length:sizeof(float4) atIndex:2 ];
    [renderEncoder setVertexBytes:&pointsize[POINT_IND_DEFAULT] length:sizeof(float) atIndex:3 ];

    [renderEncoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:6];
#ifdef DEBUG_RENDER
    NSLog(@"%s: encoded Gal Axes MTLPrimitiveTypeLine vertexcount %d", __FUNCTION__, 6);
#endif
    [renderEncoder popDebugGroup];

    
#endif
    
#ifdef DRAWGALAXY
    [renderEncoder pushDebugGroup:@"Galaxy"];
    simd::float4 colour_systems;
    colour_systems[0]=0.0;
    colour_systems[1]=0.0;
    colour_systems[2]=1.0;
    colour_systems[3]=1.0;
    
    galaxy_block_t *gb=thisGalaxy->first_galaxy_block;
    for (int i = 0; i < thisGalaxy->num_galaxy_blocks; i++) {
#ifdef DEBUG_RENDER
      NSLog(@"%s: %d galaxy block %d of %d", __FUNCTION__, gb->numsystems, i, thisGalaxy->num_galaxy_blocks);
#endif
      
      id <MTLBuffer> _vertexBuffer;
      
      _vertexBuffer = [_device newBufferWithBytes:gb->systems length:sizeof(SystemVertex_t)*gb->numsystems options:MTLResourceOptionCPUCacheModeDefault];
      _vertexBuffer.label = @"Systems";
      
      //  set vertex buffer for each journey segment
      [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0 ];
      [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
      [renderEncoder setVertexBytes:&colours[COLOUR_IND_STAR] length:sizeof(float4) atIndex:2 ];
      float starSize=pointsize[POINT_IND_DEFAULT]*(model_scale/POINT_SCALE);
      [renderEncoder setVertexBytes:&starSize length:sizeof(float) atIndex:3 ];

      // tell the render context we want to draw our primitives
      [renderEncoder drawPrimitives:MTLPrimitiveTypePoint vertexStart:0 vertexCount:gb->numsystems];
#ifdef DEBUG_RENDER
      NSLog(@"%s: encoded MTLPrimitiveTypePoint vertexcount %d", __FUNCTION__, gb->numsystems);
#endif
      gb=gb->next;
    }
    [renderEncoder popDebugGroup];

    
#endif
    
#ifdef DRAWJOURNEY
    if(enabled[FEATURE_JOURNEY]) {
      [renderEncoder pushDebugGroup:@"Journey"];

      simd::float4 colour_journey;
      colour_journey[0]=0.0;
      colour_journey[1]=1.0;
      colour_journey[2]=0.0;
      colour_journey[3]=1.0;
    
      journey_block_t *jb=thisGalaxy->first_journey_block;
      for (int i = 0; i < thisGalaxy->num_journey_blocks; i++) {
#ifdef DEBUG_RENDER
        NSLog(@"%s: %d systems block %d of %d", __FUNCTION__, jb->numsystems, i, thisGalaxy->num_journey_blocks);
#endif
        id <MTLBuffer> _vertexBuffer;
      
        _vertexBuffer = [_device newBufferWithBytes:jb->systems length:sizeof(JourneyVertex_t)*jb->numsystems options:MTLResourceOptionCPUCacheModeDefault];
        _vertexBuffer.label = @"Vertices";
      
        //  set vertex buffer for each journey segment
        [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0 ];
        [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
        [renderEncoder setVertexBytes:&colours[COLOUR_IND_JOURNEY] length:sizeof(float4) atIndex:2 ];
        float starSize=pointsize[POINT_IND_BLINE]*(model_scale/POINT_SCALE);
        [renderEncoder setVertexBytes:&starSize length:sizeof(float) atIndex:3 ];

        // tell the render context we want to draw our primitives
        [renderEncoder drawPrimitives:MTLPrimitiveTypeLineStrip vertexStart:0 vertexCount:jb->numsystems ];
#ifdef DEBUG_RENDER
        NSLog(@"%s: encoded MTLPrimitiveTypeLineStrip vertexcount %d", __FUNCTION__, jb->numsystems);
#endif
        jb=jb->next;
      }
      [renderEncoder popDebugGroup];
    }
    
    
    if(enabled[FEATURE_JSTARS]) {
      [renderEncoder pushDebugGroup:@"Journey"];

      simd::float4 colour_jstars;
      colour_jstars[0]=1.0;
      colour_jstars[1]=1.0;
      colour_jstars[2]=1.0;
      colour_jstars[3]=1.0;
      
      // Slightly fuzzy would be nice too...
      journey_block_t *jb=thisGalaxy->first_journey_block;
      for (int i = 0; i < thisGalaxy->num_journey_blocks; i++) {
#ifdef DEBUG_RENDER
        NSLog(@"%s: %d systems block %d of %d", __FUNCTION__, jb->numsystems, i, thisGalaxy->num_journey_blocks);
#endif
        id <MTLBuffer> _vertexBuffer;
      
        _vertexBuffer = [_device newBufferWithBytes:jb->systems length:sizeof(JourneyVertex_t)*jb->numsystems options:MTLResourceOptionCPUCacheModeDefault];
        _vertexBuffer.label = @"Vertices";
      
        //  set vertex buffer for each journey segment
        [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0 ];
        [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
        [renderEncoder setVertexBytes:&colours[COLOUR_IND_JSTAR] length:sizeof(float4) atIndex:2 ];
        float starSize=pointsize[POINT_IND_JSTAR]*(model_scale/POINT_SCALE);
        [renderEncoder setVertexBytes:&starSize length:sizeof(float) atIndex:3 ];

        //[renderEncoder setVertexBytes:&pointsize[POINT_IND_JSTAR] length:sizeof(float) atIndex:3 ];

        // tell the render context we want to draw our primitives
        [renderEncoder drawPrimitives:MTLPrimitiveTypePoint vertexStart:0 vertexCount:jb->numsystems ];
#ifdef DEBUG_RENDER
        NSLog(@"%s: encoded MTLPrimitiveTypeLineStrip vertexcount %d", __FUNCTION__, jb->numsystems);
#endif
        jb=jb->next;
      }
#endif
      [renderEncoder popDebugGroup];
    }
    
    
    if(enabled[FEATURE_STATIONS]) {
      [renderEncoder pushDebugGroup:@"Stations"];
      
      simd::float4 colour_jstars;
      colour_jstars[0]=1.0;
      colour_jstars[1]=1.0;
      colour_jstars[2]=1.0;
      colour_jstars[3]=1.0;
//
      station_block_t *sb=thisGalaxy->first_station_block;
      for (int i = 0; i < thisGalaxy->num_station_blocks; i++) {
#ifdef DEBUG_RENDER
        NSLog(@"%s: %d station block %d of %d", __FUNCTION__, sb->numstations, i, thisGalaxy->num_station_blocks);
#endif
        id <MTLBuffer> _vertexBuffer;
      
        _vertexBuffer = [_device newBufferWithBytes:sb->stations length:sizeof(StationVertex_t)*sb->numstations options:MTLResourceOptionCPUCacheModeDefault];
        _vertexBuffer.label = @"Vertices";
      
        //  set vertex buffer for each journey segment
        [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0 ];
        [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
        [renderEncoder setVertexBytes:&colours[COLOUR_IND_STATION] length:sizeof(float4) atIndex:2 ];
        //[renderEncoder setVertexBytes:&pointsize[POINT_IND_STATION] length:sizeof(float) atIndex:3 ];
        float starSize=pointsize[POINT_IND_STATION]*(model_scale/POINT_SCALE);
        [renderEncoder setVertexBytes:&starSize length:sizeof(float) atIndex:3 ];
      
        // tell the render context we want to draw our primitives
        [renderEncoder drawPrimitives:MTLPrimitiveTypePoint vertexStart:0 vertexCount:sb->numstations ];
#ifdef DEBUG_RENDER
        NSLog(@"%s: encoded MTLPrimitiveTypeLineStrip vertexcount %d", __FUNCTION__, sb->numstations);
#endif
        sb=sb->next;
      }
      [renderEncoder popDebugGroup];
    }
  
  
  
  
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
  _viewMatrix = lookAt(kEye, kCentre, kUp);
  
  NSLog(@"%s: (reshaped aspect=%8.4f)", __FUNCTION__, aspect);

}

#pragma mark Update

// called every frame
- (void)updateConstantBuffer {
  
  //float4x4 baseModelViewMatrix = translate(0.0f, 0.0f, 0.0f) * rotate(_rotation, 0.0f, 0.0f, 0.0f);
  float4x4 baseModelViewMatrix = translate(0.0f, 0.0f, 0.0f) ;
  baseModelViewMatrix = _viewMatrix * baseModelViewMatrix;
  
  constants_t *constant_buffer = (constants_t *)[_dynamicConstantBuffer[_constantDataBufferIndex] contents];
  
  //simd::float4x4 modelViewMatrix = AAPL::translate(0.0f, 0.0f, 1.5f) * AAPL::rotate(_rotation, 0.0f, 1.0f, 0.0f);
  simd::float4x4 modelViewMatrix = AAPL::translate(kCentre[0], kCentre[1], kCentre[2]) * AAPL::rotate(_rotation, 0.0f, 1.0f, 0.0f) * scale(model_scale, model_scale, model_scale) * AAPL::translate(-kCentre[0], -kCentre[1], -kCentre[2]);
  modelViewMatrix = baseModelViewMatrix * modelViewMatrix;

  int i=0;
  
  constant_buffer[i].normal_matrix = inverse(transpose(modelViewMatrix));
  constant_buffer[i].modelview_projection_matrix = _projectionMatrix * modelViewMatrix;
  
}

// just use this to update app globals
- (void)update:(ThreeDMapViewController *)controller {
  _rotation += controller.timeSinceLastDraw * 5.0f;
  

  
}

- (void)viewController:(ThreeDMapViewController *)controller willPause:(BOOL)pause {
  // timer is suspended/resumed
  // Can do any non-rendering related background work here when suspended
  NSLog(@"%s: willPause is %d", __FUNCTION__, pause);

}

- (void)setFeatureEnable:(int)feature enable:(BOOL)enable {
  if(feature>=MAX_FEATURES) {
    NSLog(@"%s: feature %d (%s)", __FUNCTION__, feature, "INVALID");
    return;
  }
  NSLog(@"%s: feature %d (%s)", __FUNCTION__, feature, features[feature]);
  enabled[feature]=enable;
}

- (void)toggleFeature:(int)feature {
  if(feature>=MAX_FEATURES) {
    NSLog(@"%s: feature %d (%s)", __FUNCTION__, feature, "INVALID");
    return;
  }
  NSLog(@"%s: feature %d (%s)", __FUNCTION__, feature, features[feature]);
  enabled[feature]=!enabled[feature];
}

- (void)zoom:(float)direction {
  model_scale+=direction;
  
  NSLog(@"%s: scale=%8.4f", __FUNCTION__, model_scale);
  
  
  //[self updateConstantBuffer];
}

- (BOOL)keyDown:(NSString *)characters {
  if ([characters isEqual:@"j"]) {
    // Toggle the journey...
    [self toggleFeature:FEATURE_JOURNEY];
    return TRUE;
  }
  if ([characters isEqual:@"s"]) {
    // Toggle the stations...
    [self toggleFeature:FEATURE_STATIONS];
    return TRUE;
  }
  if ([characters isEqual:@"["]) {
    [self zoom:0.05];
    return TRUE;
  }
  if ([characters isEqual:@"]"]) {
    // Toggle the journey...
    [self zoom:-0.05];
    return TRUE;
  }
  return FALSE;
}

@end

