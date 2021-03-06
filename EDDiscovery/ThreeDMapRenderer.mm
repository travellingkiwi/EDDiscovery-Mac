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
static const long kInFlightCommandBuffers = 3;

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

#define DECAY_DEFAULT 200.0f

#define DRAWJOURNEY
#define DRAWGALAXY
#define DRAWAXES

#ifdef DRAWAXES
#define AXES_LEN    (1000.0/LY_2_MTL)

#define SOLS_X         (0.0/LY_2_MTL)
#define SOLS_Y         (0.0/LY_2_MTL)
#define SOLS_Z         (0.0/LY_2_MTL)

#define SAGA_X    (25.21875/LY_2_MTL)
#define SAGA_Y   (-20.90625/LY_2_MTL)
#define SAGA_Z (25899.96875/LY_2_MTL)

static const float sol_axes[18] = {
  SOLS_X-AXES_LEN, SOLS_Y,          SOLS_Z,
  SOLS_X+AXES_LEN, SOLS_Y,          SOLS_Z,
  SOLS_X,          SOLS_Y-AXES_LEN, SOLS_Z,
  SOLS_X,          SOLS_Y+AXES_LEN, SOLS_Z,
  SOLS_X,          SOLS_Y,          SOLS_Z-AXES_LEN,
  SOLS_X,          SOLS_Y,          SOLS_Z+AXES_LEN,
};

static const float gal_axes[18] = {
  SAGA_X-AXES_LEN, SAGA_Y,          SAGA_Z,
  SAGA_X+AXES_LEN, SAGA_Y,          SAGA_Z,
  SAGA_X,          SAGA_Y-AXES_LEN, SAGA_Z,
  SAGA_X,          SAGA_Y+AXES_LEN, SAGA_Z,
  SAGA_X,          SAGA_Y,          SAGA_Z-AXES_LEN,
  SAGA_X,          SAGA_Y,          SAGA_Z+AXES_LEN
};

// A flat plane composed of two triangles...
#define PLANE_WIDTH  (10000.0f/LY_2_MTL)
#define PLANE_HEIGHT     (0.0f/LY_2_MTL)
#define PLANE_DEPTH  (10000.0f/LY_2_MTL)

static const float galactic_plane [] = {
  SOLS_X-PLANE_WIDTH, SOLS_Y+PLANE_HEIGHT, SOLS_Z+PLANE_DEPTH,   0.0, 1.0,  0.0,
  SOLS_X+PLANE_WIDTH, SOLS_Y+PLANE_HEIGHT, SOLS_Z+PLANE_DEPTH,   0.0, 1.0,  0.0,
  SOLS_X+PLANE_WIDTH, SOLS_Y+PLANE_HEIGHT, SOLS_Z-PLANE_DEPTH,   0.0, 1.0,  0.0,
  SOLS_X+PLANE_WIDTH, SOLS_Y+PLANE_HEIGHT, SOLS_Z-PLANE_DEPTH,   0.0, 1.0,  0.0,
  SOLS_X-PLANE_WIDTH, SOLS_Y+PLANE_HEIGHT, SOLS_Z+PLANE_DEPTH,   0.0, 1.0,  0.0,
  SOLS_X+PLANE_WIDTH, SOLS_Y+PLANE_HEIGHT, SOLS_Z-PLANE_DEPTH,   0.0, 1.0,  0.0,
};

#define START_EYE_X   500.0
#define START_EYE_Y     0.0
#define START_EYE_Z   500.0

#define POINT_SCALE     5.0

#endif

static const float kFOVY    = 65.0f;

float model_scale = 1.0;

//
static float3 kUp        = { 0.0f,  1.0f,  0.0f};
static float3 kCentre    = { 0.0f,  0.0f,  0.0f};

// For the eye... We keep two points. The kEyeOffset is the offset we apply to the kCentre to
// get the actual eye location. We keep this separate so when we jump the centre by an arbitrary
// amount, we simple re-calculate the kEye by translating kEyeOffset by kCentre
static float3 kEyeOffset = {START_EYE_X/LY_2_MTL, START_EYE_Y/LY_2_MTL, START_EYE_Z/LY_2_MTL};
static float3 kEye       = {kCentre.x+kEyeOffset.x, kCentre.y+kEyeOffset.y, kCentre.z+kEyeOffset.z};

galaxy_t *thisGalaxy;

#define COLOUR_IND_STAR       0
#define COLOUR_IND_JOURNEY    1
#define COLOUR_IND_JSTAR      2
#define COLOUR_IND_AXES_SOL   3
#define COLOUR_IND_AXES_SAG   4
#define COLOUR_IND_STATION    5
#define COLOUR_IND_PLANE      6
#define COLOUR_IND_PLANE_GRID 7

#define MAX_COLOUR_INDEX      8

static const float4 colours[MAX_COLOUR_INDEX]= {
  { 0.4, 0.4, 0.2, 0.05},                             // COLOUR_IND_STAR
  { 0.0, 1.0, 0.0, 1.00},                             // COLOUR_IND_JOURNEY
  { 1.0, 0.0, 0.0, 1.00},                             // COLOUR_IND_JSTAR
  { 1.0, 0.0, 0.0, 1.00},                             // COLOUR_IND_AXES_SOL
  { 0.0, 0.0, 1.0, 1.00},                             // COLOUR_IND_AXES_SAG
  { 1.0, 0.0, 1.0, 1.00},                             // COLOUR_IND_STATION
  { 0.2, 0.2, 0.8, 0.01},                             // COLOUR_IND_PLANE
  { 0.2, 0.2, 0.8, 0.25},                             // COLOUR_IND_PLANE_GRID
  
};

#define DIVISOR  50.0f

#define ISOVERTS 12

// 0  b -a (5)   b  a  0 (8)  -b  a  0 (9)
// 0  b  a (4)  -b  a  0 (9)   b  a  0 (8)
// 0  b  a (4)   0 -b  a (6)  -a  0  b (0)
// 0  b  a (4)   a  0  b (1)   0 -b  a (6)
// 0  b -a (5)   0 -b -a (7)   a  0 -b (3)
// 0  b -a (5)  -a  0 -b (2)   0 -b -a (7)
// 0 -b  a (6)   b -a  0 (10) -b -a  0 (11)
// 0 -b -a (7)  -b -a  0 (11)  b -a  0 (10)
//-b  a  0 (9)  -a  0  b (0)  -a  0 -b (2)
//-b -a  0 (11) -a  0 -b (2)  -a  0  b (0)
// b  a  0 (8)   a  0 -b (3)   a  0  b (1)
// b -a  0 (10)  a  0  b (1)   a  0 -b (3)
// 0  b  a (4)  -a  0  b (0)  -b  a  0 (9)
// 0  b  a (4)   b  a  0 (8)   a  0  b (1)
// 0  b -a (5)  -b  a  0 (9)  -a  0 -b (2)
// 0  b -a (5)   a  0 -b (3)   b  a  0 (8)
// 0 -b -a (7)  -a  0 -b (2)  -b -a  0 (11)
// 0 -b -a (7)   b -a  0 (10)  a  0 -b (3)
// 0 -b  a (6)  -b -a  0 (11) -a  0  b (0)
// 0 -b  a (6)   a  0  b (1)   b -a  0 (10)
//
//Where a = 1 / 2 and b = 1 / (2 * phi)
//phi is the golden ratio = (1 + sqrt(5)) / 2

// Geometry based on Paul Bourke's excellent article:
//   Platonic Solids (Regular polytopes in 3D)
//   http://astronomy.swin.edu.au/~pbourke/polyhedra/platonic/
const float sqrt5 = sqrt (5.0f);
const float phi = (1.0f + sqrt5) * 0.5f; // "golden ratio"
                                         // ratio of edge length to radius
const float radius=0.01f;
const float ratio = sqrt (10.0f + (2.0f * sqrt5)) / (4.0f * phi);
const float a = (radius / ratio) * 0.5;
const float b = (radius / ratio) / (2.0f * phi);

static float3 pb_vdata_simple[ISOVERTS+1] = {
// define the icosahedron's 12 vertices:
  { 0.0f,  0.0f,  0.0f},
  { 0.0f,    b ,   -a },
  {   b ,    a ,  0.0f},
  {  -b ,    a ,  0.0f},
  { 0.0f,    b ,    a },
  { 0.0f,   -b ,    a },
  {  -a ,  0.0f,    b },
  { 0.0f,   -b ,   -a },
  {   a ,  0.0f,   -b },
  {   a ,  0.0f,    b },
  {  -a ,  0.0f,   -b },
  {   b ,   -a ,  0.0f},
  {  -b ,   -a ,  0.0f},
};

static UInt16 pb_icos_tri[20][3] = {
  // draw the icosahedron's 20 triangular faces:
  { 1,  2,  3},
  { 4,  3,  2},
  { 4,  5,  6},
  { 4,  9,  5},
  { 1,  7,  8},
  { 1, 10,  7},
  { 5, 11, 12},
  { 7, 12, 11},
  { 3,  6, 10},
  { 12, 6, 10},
  { 2,  8,  9},
  {11,  9,  8},
  { 4,  6,  3},
  { 4,  2,  9},
  { 1,  3, 10},
  { 1,  8,  2},
  { 7, 10, 12},
  { 7, 11,  8},
  { 5, 12,  6},
  { 5,  9, 11},
};

#define POINT_IND_DEFAULT 0
#define POINT_IND_JSTAR   1
#define POINT_IND_BLINE   2
#define POINT_IND_STATION 3
#define MAX_POINT_SIZES   4

static const float pointsize[MAX_POINT_SIZES]={1.0, 5.00, 20.000, 15.00};

#define MTL_PIPE_SIMPLELINE     0        // Simple lines - e.g. the Axes of interest
#define MTL_PIPE_GALAXY_STAR    1        // Draws the stars in the galaxy...
#define MTL_PIPE_JOURNEY_STAR   2        // Draws the stars that we've journeyed to
#define MTL_PIPE_JOURNEY        3        // Draws the journey itself
#define MTL_PIPE_STATION        4        // Draws the journey itself
#define MTL_PIPE_GALACTIC_PLANE 5
#define MTL_PIPE_SPHERE         6
#define MTL_PIPE_SPHERE_SIMPLE  7
#define MTL_PIPE_COUNT          8        // Number of metal pipelines to have defined

typedef struct mtl_pipe_s {
  const char *name;
  const char *vertex_prog_name;
  const char *fragmt_prog_name;
  id vertex_prog;
  id fragmt_prog;
} mtl_pipe_t;

static const mtl_pipe_t mtl_pipe[MTL_PIPE_COUNT]={
  {"Simple Line", "simple_line_vertex", "simple_line_frag", NULL, NULL},
  {"Galaxy Star", "galaxy_star_vertex", "galaxy_star_frag", NULL, NULL},
  {"Journey Star", "journey_star_vertex", "journey_star_frag", NULL, NULL},
  {"Journey Path", "journey_path_vertex", "journey_star_frag", NULL, NULL},
  {"Station", "galaxy_star_vertex", "galaxy_star_frag", NULL, NULL},
  {"Galactic Plane", "galactic_plane_vertex", "galactic_plane_frag", NULL, NULL},
  {"Sphere", "sphere_vertex", "sphere_frag", NULL, NULL},
  {"Sphere Simple", "sphere_simple_vertex", "sphere_frag", NULL, NULL},
  //  {"Galactic Grid", "galactic_grid_vertex", "gatactic_grid_frag", NULL, NULL},
  
};

@implementation ThreeDMapRenderer {
  // constant synchronization for buffering <kInFlightCommandBuffers> frames
  dispatch_semaphore_t _inflight_semaphore;
  id <MTLBuffer> _dynamicConstantBuffer[kInFlightCommandBuffers];
  
  // renderer global ivars..
  id <MTLDevice> _device;
  id <MTLCommandQueue> _commandQueue;
  id <MTLLibrary> _defaultLibrary;
  id <MTLRenderPipelineState> _pipelineState[MTL_PIPE_COUNT];
  id <MTLDepthStencilState> _depthState;

  // Buffers
  id <MTLBuffer> _sol_axesBuffer;
  id <MTLBuffer> _gal_axesBuffer;
  id <MTLBuffer> _sphere_pb_vertexBuffer;
  id <MTLBuffer> _sphere_pb_indexBuffer;

  // globals used in update calculation
  float4x4 _projectionMatrix;
  float4x4 _viewMatrix;
  float _rotate_x;
  float _rotate_y;
  float _rotate_z;
  
  float _star_decay;
  
  long _maxBufferBytesPerFrame;
  size_t _sizeOfConstantT;
  
  // If we've done something to deserve a redraw then set this TRUE...
  BOOL _redrawPending;
  
  // this value will cycle from 0 to g_max_inflight_buffers whenever a display completes ensuring renderer clients
  // can synchronize between g_max_inflight_buffers count buffers, and thus avoiding a constant buffer from being overwritten between draws
  NSUInteger _constantDataBufferIndex;
  
  // Stats....
  unsigned long long _totalRedraws;             // Total number of times redraw was called...
  unsigned long long _actualRedraws;            // Actual number of times we redrew the display
  unsigned long long _avoidRedraws;             // Number of times we avoided a redraw because we didnt' change anything
}

static const char *features[MAX_FEATURES] = {
  "Journey", "JStars", "Stations", "Galactic Plane",
};

static BOOL enabled[MAX_FEATURES] = {1, 1, 1, 0};

#if 0
//
// This render_text is based on the openGL code from https://en.wikibooks.org/wiki/OpenGL_Programming/Modern_OpenGL_Tutorial_Text_Rendering_01
//
void render_text(const char *text, float x, float y, float sx, float sy) {
  const char *p;
  
  for(p = text; *p; p++) {
    if(FT_Load_Char(face, *p, FT_LOAD_RENDER))
      continue;
    
    glTexImage2D(
                 GL_TEXTURE_2D,
                 0,
                 GL_RED,
                 g->bitmap.width,
                 g->bitmap.rows,
                 0,
                 GL_RED,
                 GL_UNSIGNED_BYTE,
                 g->bitmap.buffer
                 );
    
    float x2 = x + g->bitmap_left * sx;
    float y2 = -y - g->bitmap_top * sy;
    float w = g->bitmap.width * sx;
    float h = g->bitmap.rows * sy;
    
    GLfloat box[4][4] = {
      {x2,     -y2    , 0, 0},
      {x2 + w, -y2    , 1, 0},
      {x2,     -y2 - h, 0, 1},
      {x2 + w, -y2 - h, 1, 1},
    };
    
    glBufferData(GL_ARRAY_BUFFER, sizeof box, box, GL_DYNAMIC_DRAW);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    x += (g->advance.x/64) * sx;
    y += (g->advance.y/64) * sy;
  }
}

void subdivide(float u1[2], float u2[2], float u3[2],
               float cutoff, long depth)
{
  GLfloat v1[3], v2[3], v3[3], n1[3], n2[3], n3[3];
  GLfloat u12[2], u23[2], u32[2];
  GLint i;
  
  if (depth == maxdepth || (curv(u1) < cutoff &&
                            curv(u2) < cutoff && curv(u3) < cutoff)) {
    surf(u1, v1, n1); surf(u2, v2, n2); surf(u3, v3, n3);
    glBegin(GL_POLYGON);
    glNormal3fv(n1); glVertex3fv(v1);
    glNormal3fv(n2); glVertex3fv(v2);
    glNormal3fv(n3); glVertex3fv(v3);
    glEnd();
    return;
  }
  for (i = 0; i < 2; i++) {
    u12[i] = (u1[i] + u2[i])/2.0;
    u23[i] = (u2[i] + u3[i])/2.0;
    u31[i] = (u3[i] + u1[i])/2.0;
  }
  subdivide(u1, u12, u31, cutoff, depth+1);
  subdivide(u2, u23, u12, cutoff, depth+1);
  subdivide(u3, u31, u23, cutoff, depth+1);
  subdivide(u12, u23, u31, cutoff, depth+1);
}
#endif

//- (void)setConstatBuffer {
//  for(int i=0; i<kInFlightCommandBuffers; i++) {
//    constants_t *constant_buffer = (constants_t *)[_dynamicConstantBuffer[i] contents];
//    constant_buffer[0].kCentre=kCentre;
//    constant_buffer[0].kEye=kEye;
//  }//
//}

- (void)setPosition:(float)x y:(float)y z:(float)z  {
  NSLog(@"%s:         set [%8.4f %8.4f %8.4f]", __FUNCTION__, x, y, z);

  kCentre.x=x;
  kCentre.y=y;
  kCentre.z=z;
  
  //kEye[0]=kCentre[0]+10.0f;
  //kEye[1]=kCentre[1]+5.0f;
  //kEye[2]=kCentre[2]+5.0f;
  //kEye[0]=kCentre[0]+(START_EYE_X/LY_2_MTL);
  //kEye[1]=kCentre[1]+(START_EYE_Y/LY_2_MTL);
  //kEye[2]=kCentre[2]+(START_EYE_Z/LY_2_MTL);
  
  //[self rotateView:0.0f y:0.0f z:0.0f];

  //[self setConstatBuffer];

  NSLog(@"%s: kUp        set [%8.4f %8.4f %8.4f]", __FUNCTION__, kUp.x, kUp.y, kUp.z);
  NSLog(@"%s: kEye       set [%8.4f %8.4f %8.4f]", __FUNCTION__, kEye.x, kEye.y, kEye.z);
  NSLog(@"%s: kCentre    set [%8.4f %8.4f %8.4f]", __FUNCTION__, kCentre.x, kCentre.y, kCentre.z);
  NSLog(@"%s: kEyeOffset set [%8.4f %8.4f %8.4f]", __FUNCTION__, kEyeOffset.x, kEyeOffset.y, kEyeOffset.z);
  
  _redrawPending=TRUE;
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
  
  _rotate_x=0.0f;
  _rotate_y=0.0f;
  _rotate_z=0.0f;
  
  _star_decay=DECAY_DEFAULT;
  
  _redrawPending=TRUE;
  _totalRedraws=0;
  _actualRedraws=0;
  _avoidRedraws=0;
  
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
  // This is only creating one command queue. We should really be creating one per GPU
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
  
  if(![self prepareBuffers]) {
    NSLog(@"ERROR: Couldn't prepare the vertex buffers");
    
    //
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

- (BOOL)preparePipelineState:(ThreeDMapView *)view {

  for (int i=0; i<MTL_PIPE_COUNT; i++) {
    NSLog(@"%s: PREPARING PIPELINE [%d] %s", __FUNCTION__, i, mtl_pipe[i].name);

    id <MTLFunction> vertexProgram=[_defaultLibrary newFunctionWithName:[NSString stringWithUTF8String:mtl_pipe[i].vertex_prog_name]];
    if(!vertexProgram) {
      NSLog(@"%s: >> ERROR: Couldn't load vertex function %s from default library", __FUNCTION__, mtl_pipe[i].vertex_prog_name);
      exit(-1);
    }
    // get the vertex function from the library
    id <MTLFunction> fragmentProgram = [_defaultLibrary newFunctionWithName:[NSString stringWithUTF8String:mtl_pipe[i].fragmt_prog_name]];
    if(!fragmentProgram) {
      NSLog(@"%s: >> ERROR: Couldn't load fragment function %s from default library", __FUNCTION__, mtl_pipe[i].fragmt_prog_name);
      exit(-1);
    }
    // create a pipeline state descriptor which can be used to create a compiled pipeline state object
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    
    pipelineStateDescriptor.label                                      = @"MyPipeline";
    pipelineStateDescriptor.sampleCount                                = view.sampleCount;
    pipelineStateDescriptor.vertexFunction                             = vertexProgram;
    pipelineStateDescriptor.fragmentFunction                           = fragmentProgram;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat            = MTLPixelFormatBGRA8Unorm;
    pipelineStateDescriptor.colorAttachments[0].blendingEnabled        = YES;
    pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation           = MTLBlendOperationAdd;
    pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation         = MTLBlendOperationAdd;
    pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor        = MTLBlendFactorOne;
    pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor      = MTLBlendFactorOne;
    pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor   = MTLBlendFactorOneMinusSourceAlpha;
    pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    pipelineStateDescriptor.depthAttachmentPixelFormat          = view.depthPixelFormat;
    pipelineStateDescriptor.alphaToCoverageEnabled              = YES;

    // create a compiled pipeline state object. Shader functions (from the render pipeline descriptor)
    // are compiled when this is created unlessed they are obtained from the device's cache
    NSError *error = nil;
    _pipelineState[i] = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if(!_pipelineState[i]) {
      NSLog(@"%s: >> ERROR: Failed Aquiring pipeline state: %@", __FUNCTION__, error);
      return NO;
    }


  }
  NSLog(@"%s: %d PIPELINES created", __FUNCTION__, MTL_PIPE_COUNT);

  return YES;
}

- (BOOL) prepareBuffers {
  NSLog(@"%s: SIZES float3 %lu float %lu UInt16 %lu", __FUNCTION__, sizeof(float3), sizeof(float), sizeof(UInt16));
  _sol_axesBuffer = [_device newBufferWithBytes:sol_axes length:sizeof(gal_axes) options:MTLResourceOptionCPUCacheModeDefault];
  _sol_axesBuffer.label = @"SolAxes";
  
  _gal_axesBuffer = [_device newBufferWithBytes:gal_axes length:sizeof(gal_axes) options:MTLResourceOptionCPUCacheModeDefault];
  _gal_axesBuffer.label = @"GalAxes";
  
  _sphere_pb_vertexBuffer= [_device newBufferWithBytes:pb_vdata_simple length:sizeof(float3)*13 options:MTLResourceOptionCPUCacheModeDefault];
  _sphere_pb_vertexBuffer.label = @"JStar PB Vertices";
  _sphere_pb_indexBuffer = [_device newBufferWithBytes:pb_icos_tri length:sizeof(unsigned short)*3*20 options:MTLResourceOptionCPUCacheModeDefault];
  _sphere_pb_indexBuffer.label = @"JStar PB Index";

  return YES;
}

- (void)strip4Sphere:(float4 *)strip resolution:(float)resolution {
  float Long, Lat;
  
#if 0
  glBegin(GL_TRIANGLE_STRIP);
  //  glBegin(GL_LINE_STRIP);
  glVertex3f(0.0, 0.0, -10.0);
  for(Long = 0.0; Long<360.0; Long += resolution){
    for(Lat = -80; Lat<90; Lat += resolution/2.0f){
      if((int)Lat % 20) glColor3fv(color[0]);
      else glColor3fv(color[1]);
      cartesian(Long, Lat);
      glVertex3fv(cart);
      cartesian(Long+10.0, Lat);
      glVertex3fv(cart);
    }
    glVertex3f(0.0, 0.0, 10.0);
    for(Lat = 80; Lat> -90; Lat -= resolution/2.0f) {
      if((int)Lat % 20) glColor3fv(color[2]);
      else glColor3fv(color[3]);
      cartesian(Long +10.1, Lat);
      glVertex3fv(cart);
      cartesian(Long+20.0-0.1, Lat);
      glVertex3fv(cart);
    }
    glVertex3f(0.0, 0.0, -10.0);
  }
  glEnd();
  glFlush();
#endif
  
}

#pragma mark Render

- (void)render:(ThreeDMapView *)view {
  _totalRedraws++;
  
  // If we're not pending a redraw, just return...
#if 0
  if(! _redrawPending) {
    // Avoiding the redraw so increment...
    _avoidRedraws++;
    return;
  }
  NSLog(@"%s: _totalRedraws %llu _avoidedRedraw %llu _actualRedraw %llu", __FUNCTION__, _totalRedraws, _avoidRedraws, _actualRedraws);
#endif
#ifdef DEBUG_RENDER
  //NSLog(@"%s: Rotate     (%8.4f %8.4f %8.4f) now (%8.4f %8.4f %8.4f)", __FUNCTION__, x, y, z, _rotate_x, _rotate_y, _rotate_z);
  NSLog(@"%s: kUp        (%8.4f %8.4f %8.4f)", __FUNCTION__, kUp.x, kUp.y, kUp.z);
  NSLog(@"%s: kEye       (%8.4f %8.4f %8.4f)", __FUNCTION__, kEye.x, kEye.y, kEye.z);
  NSLog(@"%s: kCentre    (%8.4f %8.4f %8.4f)", __FUNCTION__, kCentre.x, kCentre.y, kCentre.z);
  NSLog(@"%s: kEyeOffset [%8.4f %8.4f %8.4f]", __FUNCTION__, kEyeOffset.x, kEyeOffset.y, kEyeOffset.z);
  
#endif

  // Allow the renderer to preflight 3 frames on the CPU (using a semapore as a guard) and commit them to the GPU.
  // This semaphore will get signaled once the GPU completes a frame's work via addCompletedHandler callback below,
  // signifying the CPU can go ahead and prepare another frame.
  dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);

  // Increment actual redraws since we've started...
  _actualRedraws++;
  
  // Prior to sending any data to the GPU, constant buffers should be updated accordingly on the CPU.
  [self updateConstantBuffer];
  
  // create a new command buffer for each renderpass to the current drawable
  id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
  
  // create the render command encoders so we can render into something
  MTLRenderPassDescriptor *renderPassDescriptor =view.renderPassDescriptor;
  
  id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

  [renderEncoder setDepthStencilState:_depthState];
  [renderEncoder setRenderPipelineState:_pipelineState[MTL_PIPE_SIMPLELINE]];
  
#ifdef DRAWAXES
  // Draw the axes....
  [renderEncoder pushDebugGroup:@"Axes"];
    
  //  set vertex buffer for each journey segment
  [renderEncoder setVertexBuffer:_sol_axesBuffer offset:0 atIndex:0 ];
  [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
  [renderEncoder setVertexBytes:&colours[COLOUR_IND_AXES_SOL] length:sizeof(float4) atIndex:2 ];
  [renderEncoder setVertexBytes:&pointsize[POINT_IND_DEFAULT] length:sizeof(float) atIndex:3 ];
  [renderEncoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:6];
  
    
  //  set vertex buffer for each journey segment
  [renderEncoder setVertexBuffer:_gal_axesBuffer offset:0 atIndex:0 ];
  [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
  [renderEncoder setVertexBytes:&colours[COLOUR_IND_AXES_SAG] length:sizeof(float4) atIndex:2 ];
  [renderEncoder setVertexBytes:&pointsize[POINT_IND_DEFAULT] length:sizeof(float) atIndex:3 ];
  [renderEncoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:6];

  [renderEncoder popDebugGroup];

  
#endif
  
  if(enabled[FEATURE_GALACTIC_PLANE]) {
    // Draw the plane of the galaxy...
    [renderEncoder setDepthStencilState:_depthState];
    [renderEncoder setRenderPipelineState:_pipelineState[MTL_PIPE_GALACTIC_PLANE]];
  
    [renderEncoder pushDebugGroup:@"Galactic Plane"];
  
    id <MTLBuffer> _galactic_plane_buffer;
    _galactic_plane_buffer = [_device newBufferWithBytes:galactic_plane length:sizeof(galactic_plane) options:MTLResourceOptionCPUCacheModeDefault];
    _galactic_plane_buffer.label = @"GalacticPlane";
  
    //  set vertex buffer for each journey segment
    [renderEncoder setVertexBuffer:_galactic_plane_buffer offset:0 atIndex:0 ];
    [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
    [renderEncoder setVertexBytes:&colours[COLOUR_IND_PLANE] length:sizeof(float4) atIndex:2 ];
    [renderEncoder setVertexBytes:&pointsize[POINT_IND_DEFAULT] length:sizeof(float) atIndex:3 ];
  
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];

    [renderEncoder popDebugGroup];
  }
  
#ifdef DRAWGALAXY
  
  [renderEncoder setDepthStencilState:_depthState];
  [renderEncoder setRenderPipelineState:_pipelineState[MTL_PIPE_GALAXY_STAR]];
  
  [renderEncoder pushDebugGroup:@"Galaxy"];
  
  galaxy_block_t *gb=thisGalaxy->first_galaxy_block;
  while (gb!=NULL) {
      
    id <MTLBuffer> _vertexBuffer;
    
    _vertexBuffer = [_device newBufferWithBytes:gb->systems length:sizeof(SystemVertex_t)*gb->numsystems options:MTLResourceOptionCPUCacheModeDefault];
    _vertexBuffer.label = @"Systems";
      
    //  set vertex buffer for each journey segment
    [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0 ];
    [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
    [renderEncoder setVertexBytes:&colours[COLOUR_IND_STAR] length:sizeof(float4) atIndex:2 ];
    [renderEncoder setVertexBytes:&_star_decay length:sizeof(float) atIndex:3 ];
    float starSize=MIN(pointsize[POINT_IND_DEFAULT]*(model_scale/POINT_SCALE), 10.0f);
    [renderEncoder setVertexBytes:&starSize length:sizeof(float) atIndex:4 ];

#if 0
    // tell the render context we want to draw our primitives
    if (starSize>10.0) {
      [renderEncoder drawPrimitives:MTLPr vertexStart:0 vertexCount:gb->numsystems];

    } else {
#endif
      [renderEncoder drawPrimitives:MTLPrimitiveTypePoint vertexStart:0 vertexCount:gb->numsystems];
      
#ifdef DEBUG_RENDER
    NSLog(@"%s: encoded MTLPrimitiveTypePoint vertexcount %d", __FUNCTION__, gb->numsystems);
#endif
    gb=gb->next;
  }
    
  [renderEncoder popDebugGroup];
    //[renderEncoder endEncoding];
    
#endif
    
  if(enabled[FEATURE_JOURNEY]) {
    [renderEncoder pushDebugGroup:@"Journey"];

    [renderEncoder setDepthStencilState:_depthState];
    [renderEncoder setRenderPipelineState:_pipelineState[MTL_PIPE_JOURNEY]];
    
    journey_block_t *jb=thisGalaxy->first_journey_block;
    while (jb!=NULL) {
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

      jb=jb->next;
    }
    
    [renderEncoder popDebugGroup];
    //[renderEncoder endEncoding];
    
  }
    
    
  if(enabled[FEATURE_JSTARS]) {
    
    [renderEncoder pushDebugGroup:@"Journey"];

    [renderEncoder setDepthStencilState:_depthState];
    [renderEncoder setRenderPipelineState:_pipelineState[MTL_PIPE_JOURNEY_STAR]];
    
    // Slightly fuzzy would be nice too...
    journey_block_t *jb=thisGalaxy->first_journey_block;
    while (jb!=NULL) {

#if 0
      id <MTLBuffer> _vertexBuffer;

      [renderEncoder setRenderPipelineState:_pipelineState[MTL_PIPE_JOURNEY_STAR]];

      _vertexBuffer = [_device newBufferWithBytes:jb->systems length:sizeof(JourneyVertex_t)*jb->numsystems options:MTLResourceOptionCPUCacheModeDefault];
      _vertexBuffer.label = @"JStars Vertices";

      //  set vertex buffer for each journey star
      [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0 ];
      [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
      [renderEncoder setVertexBytes:&colours[COLOUR_IND_JSTAR] length:sizeof(float4) atIndex:2 ];
      float starSize=MIN(pointsize[POINT_IND_JSTAR]*(model_scale/POINT_SCALE), 10.0f);
      [renderEncoder setVertexBytes:&starSize length:sizeof(float) atIndex:3 ];
      // tell the render context we want to draw our primitives
      [renderEncoder drawPrimitives:MTLPrimitiveTypePoint vertexStart:0 vertexCount:jb->numsystems ];
#endif
      
      [renderEncoder setRenderPipelineState:_pipelineState[MTL_PIPE_SPHERE_SIMPLE]];
      [renderEncoder setCullMode:MTLCullModeNone];
      // Draw each star individually...
      for (int i=0; i<jb->numsystems; i++) {

        //  set vertex buffer for each journey star
        [renderEncoder setVertexBuffer:_sphere_pb_vertexBuffer offset:0 atIndex:0 ];                               // Verticies of the sphere
        [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];      // Constants
        [renderEncoder setVertexBytes:&colours[COLOUR_IND_JSTAR] length:sizeof(float4) atIndex:2 ];                // Colour
        [renderEncoder setVertexBytes:&_star_decay length:sizeof(float) atIndex:3 ];                               // Decay
        [renderEncoder setVertexBytes:&jb->systems[i].posx length:sizeof(float3) atIndex:4 ];                      // Offset
        //[renderEncoder setVertexBuffer:&jb->systems[i].posx offset:0 atIndex:4 ];

        //NSLog(@"%s: render system %d (%8.4f %8.4f %8.4f)", __FUNCTION__, i, jb->systems[i].posx, jb->systems[i].posy, jb->systems[i].posz);
        // tell the render context we want to draw our primitives
        [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                  indexCount:3*20
                                   indexType:MTLIndexTypeUInt16
                                 indexBuffer:_sphere_pb_indexBuffer
                           indexBufferOffset:0
                               instanceCount:1];
        
#if 0
        //[renderEncoder setRenderPipelineState:_pipelineState[MTL_PIPE_SIMPLELINE]];

        [renderEncoder setVertexBuffer:_sphere_pb_vertexBuffer offset:0 atIndex:0 ];
        [renderEncoder setVertexBuffer:_dynamicConstantBuffer[_constantDataBufferIndex] offset:0 atIndex:1 ];
        [renderEncoder setVertexBytes:&colours[COLOUR_IND_AXES_SAG] length:sizeof(float4) atIndex:2 ];
        [renderEncoder setVertexBytes:&_star_decay length:sizeof(float) atIndex:3 ];
        [renderEncoder setVertexBytes:&jb->systems[i].posx length:sizeof(float3) atIndex:4 ];
        //[renderEncoder setVertexBuffer:&jb->systems[i].posx offset:0 atIndex:4 ];
        [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeLine
                                  indexCount:3*20
                                   indexType:MTLIndexTypeUInt16
                                 indexBuffer:_sphere_pb_indexBuffer
                           indexBufferOffset:0
                               instanceCount:1];
#endif
      }
      jb=jb->next;
    }

    [renderEncoder popDebugGroup];

  }
    
    
  if(enabled[FEATURE_STATIONS]) {
    //renderEncoder=[commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [renderEncoder pushDebugGroup:@"Stations"];

    [renderEncoder setDepthStencilState:_depthState];
    [renderEncoder setRenderPipelineState:_pipelineState[MTL_PIPE_STATION]];
    
    station_block_t *sb=thisGalaxy->first_station_block;
    while(sb!=NULL) {
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

      sb=sb->next;
    }
    
    [renderEncoder popDebugGroup];
    
  }
  
  [renderEncoder endEncoding];

  // schedule a present once rendering to the framebuffer is complete
  [commandBuffer presentDrawable:view.currentDrawable];
  
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
    
  _redrawPending=FALSE;

}

- (void)reshape:(ThreeDMapView *)view {
  // when reshape is called, update the view and projection matricies since this means the view orientation or size changed
  float aspect = fabs(view.bounds.size.width / view.bounds.size.height);
  _projectionMatrix = perspective_fov(kFOVY, aspect, 0.1f, 100.0f);
  _viewMatrix = lookAt(kEye, kCentre, kUp);
  
#if 1
  NSLog(@"%s: kUp        (%8.4f %8.4f %8.4f)", __FUNCTION__, kUp.x, kUp.y, kUp.z);
  NSLog(@"%s: kEye       (%8.4f %8.4f %8.4f)", __FUNCTION__, kEye.x, kEye.y, kEye.z);
  NSLog(@"%s: kCentre    (%8.4f %8.4f %8.4f)", __FUNCTION__, kCentre.x, kCentre.y, kCentre.z);
  NSLog(@"%s: kEyeOffset [%8.4f %8.4f %8.4f]", __FUNCTION__, kEyeOffset.x, kEyeOffset.y, kEyeOffset.z);

#endif
  
  _redrawPending=TRUE;
}

#pragma mark Update

// called every frame
- (void)updateConstantBuffer {
  
  //float4x4 baseModelViewMatrix = translate(0.0f, 0.0f, 0.0f) * rotate(_rotation, 0.0f, 0.0f, 0.0f);
  float4x4 baseModelViewMatrix = translate(0.0f, 0.0f, 0.0f) ;
  baseModelViewMatrix = _viewMatrix * baseModelViewMatrix;
  
  //constants_t *constant_buffer = (constants_t *)[_dynamicConstantBuffer[_constantDataBufferIndex] contents];
  
  //simd::float4x4 modelViewMatrix = AAPL::translate(0.0f, 0.0f, 1.5f) * AAPL::rotate(_rotation, 0.0f, 1.0f, 0.0f);
  //simd::float4x4 modelViewMatrix = AAPL::translate(kCentre[0], kCentre[1], kCentre[2]) * AAPL::rotate(0.0f, 0.0f, 1.0f, 0.0f) * scale(model_scale, model_scale, model_scale) * AAPL::translate(-kCentre[0], -kCentre[1], -kCentre[2]);
  simd::float4x4 modelViewMatrix = baseModelViewMatrix * scale(model_scale, model_scale, model_scale);   //* modelViewMatrix;

  //int i=0;
  
  for(int i=0; i<kInFlightCommandBuffers; i++) {
    constants_t *constant_buffer = (constants_t *)[_dynamicConstantBuffer[i] contents];
 
    constant_buffer->normal_matrix = inverse(transpose(modelViewMatrix));
    constant_buffer->modelview_projection_matrix = _projectionMatrix * modelViewMatrix;
    constant_buffer->kCentre=kCentre;
    constant_buffer->kEye=kEye;
  }
  
}

// just use this to update app globals
- (void)update:(ThreeDMapViewController *)controller {
  //  _rotation += controller.timeSinceLastDraw * 1.0f;
  

  
}

- (void)viewController:(ThreeDMapViewController *)controller willPause:(BOOL)pause {
  // timer is suspended/resumed
  // Can do any non-rendering related background work here when suspended
  NSLog(@"%s: willPause is %d", __FUNCTION__, pause);

}

//
//
- (void)rotateView:(float)x y:(float)y z:(float)z {
  //NSLog(@"%s: (%8.4f %8.4f %8.4f)", __FUNCTION__, x, y, z);



  // Invert the y rotation...
  //y*=-1.0f;
  _rotate_x+=x;
  _rotate_y+=y;
  _rotate_z+=z;

#if 1
  //NSLog(@"%s: Rotate     (%8.4f %8.4f %8.4f) now (%8.4f %8.4f %8.4f)", __FUNCTION__, x, y, z, _rotate_x, _rotate_y, _rotate_z);
  NSLog(@"%s: B4 Increment  (%8.4f %8.4f %8.4f)", __FUNCTION__, x, y, z);
  NSLog(@"%s: B4 Rotate     (%8.4f %8.4f %8.4f)", __FUNCTION__, _rotate_x, _rotate_y, _rotate_z);
  NSLog(@"%s: B4 kUp        (%8.4f %8.4f %8.4f)", __FUNCTION__, kUp.x, kUp.y, kUp.z);
  NSLog(@"%s: B4 kEye       (%8.4f %8.4f %8.4f)", __FUNCTION__, kEye.x, kEye.y, kEye.z);
  NSLog(@"%s: B4 kCentre    (%8.4f %8.4f %8.4f)", __FUNCTION__, kCentre.x, kCentre.y, kCentre.z);
  NSLog(@"%s: B4 kEyeOffset [%8.4f %8.4f %8.4f]", __FUNCTION__, kEyeOffset.x, kEyeOffset.y, kEyeOffset.z);
#endif
  
  float dx=kEye.x-kCentre.x;
  float dy=kEye.y-kCentre.y;
  float dz=kEye.z-kCentre.z;
  
  NSLog(@"%s: dx dy dz [%8.4f %8.4f %8.4f]", __FUNCTION__, dx, dy, dz);
  
  float hcube=dx*dx+dy*dy+dz*dz;
  float h=sqrtf(hcube);

  NSLog(@"%s: hcube %8.4f h %8.4f", __FUNCTION__, hcube, h);

  float normx=acosf(dx/h);
  float normy=acosf(dy/h);
  float normz=acosf(dz/h);

  NSLog(@"%s: normx %8.4f normy %8.4f normz %8.4f", __FUNCTION__, normx, normy, normz);

  simd::float4x4 normrot=AAPL::rotate(normx, normy, normz);
  simd::float4x4 revrot=AAPL::rotate(-normx, -normy, -normz);
  
  
  simd::float4 mOffset={kEyeOffset.x, kEyeOffset.y, kEyeOffset.z, 1.0f};
  simd::float4 effOffset=mOffset*normrot*AAPL::rotate(_rotate_x, _rotate_y, _rotate_z)*revrot;
  
  kCentre.x=effOffset.x;
  kCentre.y=effOffset.y;
  kCentre.z=effOffset.z;
  
#if 1
  //NSLog(@"%s: Rotate     (%8.4f %8.4f %8.4f) now (%8.4f %8.4f %8.4f)", __FUNCTION__, x, y, z, _rotate_x, _rotate_y, _rotate_z);
  NSLog(@"%s: AF Increment  (%8.4f %8.4f %8.4f)", __FUNCTION__, x, y, z);
  NSLog(@"%s: AF Rotate     (%8.4f %8.4f %8.4f)", __FUNCTION__, _rotate_x, _rotate_y, _rotate_z);
  NSLog(@"%s: AF kUp        (%8.4f %8.4f %8.4f)", __FUNCTION__, kUp.x, kUp.y, kUp.z);
  NSLog(@"%s: AF kEye       (%8.4f %8.4f %8.4f)", __FUNCTION__, kEye.x, kEye.y, kEye.z);
  NSLog(@"%s: AF kCentre    (%8.4f %8.4f %8.4f)", __FUNCTION__, kCentre.x, kCentre.y, kCentre.z);
  NSLog(@"%s: AF kEyeOffset [%8.4f %8.4f %8.4f]", __FUNCTION__, kEyeOffset.x, kEyeOffset.y, kEyeOffset.z);
#endif
  
#if 0
  //simd::float4x4 rotateMatrix=AAPL::rotate(_rotate_x, _rotate_y, _rotate_z);
  simd::float4x4 rotateMatrix=AAPL::rotate(x, y, z);

  simd::float4 mEye={kEye.x-kCentre.x, kEye.y-kCentre.y, kEye.z-kCentre.z, 1.0f};
  simd::float4 mEyeEffective=mEye*rotateMatrix;

  // The Up direction is simply rotatated... No translation required.
  simd::float4 mUp={kUp.x, kUp.y, kUp.z, 1.0f};
  simd::float4 mUpEffective=mUp*rotateMatrix;
  
 
  kEye.x=mEyeEffective.x+kCentre.x;
  kEye.y=mEyeEffective.y+kCentre.y;
  kEye.z=mEyeEffective.z+kCentre.z;
  
  kUp.x=mUpEffective.x;
  kUp.y=mUpEffective.y;
  kUp.z=mUpEffective.z;
#endif
  
  _viewMatrix = lookAt(kEye, kCentre, kUp);

#if 1
  NSLog(@"%s: rotated kUp        (%8.4f %8.4f %8.4f)", __FUNCTION__, kUp.x, kUp.y, kUp.z);
  NSLog(@"%s: rotated kEye       (%8.4f %8.4f %8.4f)", __FUNCTION__, kEye.x, kEye.y, kEye.z);
  NSLog(@"%s: rotated kCentre    (%8.4f %8.4f %8.4f)", __FUNCTION__, kCentre.x, kCentre.y, kCentre.z);
  NSLog(@"%s: rotated kEyeOffset [%8.4f %8.4f %8.4f]", __FUNCTION__, kEyeOffset.x, kEyeOffset.y, kEyeOffset.z);
#endif
  
  _redrawPending=TRUE;

}

//
// rotateSelf
// rotate the centre around our eyepoint
// centre * translate_eyepos * rotate * -translate_eyepos
- (void)rotateSelf:(float)x y:(float)y z:(float)z {
  //NSLog(@"%s: (%8.4f %8.4f %8.4f)", __FUNCTION__, x, y, z);
  
#if 1
  NSLog(@"%s: original Rotate     (%8.4f %8.4f %8.4f)", __FUNCTION__, x, y, z);
  NSLog(@"%s: original kUp        (%8.4f %8.4f %8.4f)", __FUNCTION__, kUp.x, kUp.y, kUp.z);
  NSLog(@"%s: original kCentre    (%8.4f %8.4f %8.4f)", __FUNCTION__, kCentre.x, kCentre.y, kCentre.z);
  NSLog(@"%s: original kEyeOffset [%8.4f %8.4f %8.4f]", __FUNCTION__, kEyeOffset.x, kEyeOffset.y, kEyeOffset.z);
  NSLog(@"%s: original kEye       (%8.4f %8.4f %8.4f)", __FUNCTION__, kEye.x, kEye.y, kEye.z);

#endif

#if 1
  //simd::float4x4 transformMatrix=AAPL::translate(kEye.x, kEye.y, kEye.z) * AAPL::rotate(-x, -y, -z) * AAPL::translate(-kEye.x, -kEye.y, -kEye.z);
  //simd::float4x4 transformMatrix=AAPL::rotate(x, y, z);
  simd::float4 mCentre={kCentre.x-kEye.x, kCentre.y-kEye.y, kCentre.z-kEye.z, 1.0f};
  simd::float4 mCtrEffective=mCentre*AAPL::rotate(x, y, z);
  
  NSLog(@"%s: mCentre             (%8.4f %8.4f %8.4f)", __FUNCTION__, mCentre.x, mCentre.y, mCentre.z);
  NSLog(@"%s: mCtrEffective       (%8.4f %8.4f %8.4f)", __FUNCTION__, mCtrEffective.x, mCtrEffective.y, mCtrEffective.z);

  // The Up direction is simply rotatated... No translation required.
  //simd::float4 mUp={kUp.x, kUp.y, kUp.z, 1.0f};
  //simd::float4 mUpEffective=mUp*rotateMatrix;
  
  kCentre.x=mCtrEffective.x+kEye.x;
  kCentre.y=mCtrEffective.y+kEye.y;
  kCentre.z=mCtrEffective.z+kEye.z;
  
  //kUp.x=mUpEffective.x;
  //kUp.y=mUpEffective.y;
  //kUp.z=mUpEffective.z;
  
  
  kEyeOffset.x=kEye.x-kCentre.x;
  kEyeOffset.y=kEye.y-kCentre.y;
  kEyeOffset.z=kEye.z-kCentre.z;
  
  // eye = centre + offset
#endif
  
  _viewMatrix = lookAt(kEye, kCentre, kUp);

#if 1
  NSLog(@"%s: rotated  kUp        (%8.4f %8.4f %8.4f)", __FUNCTION__, kUp.x, kUp.y, kUp.z);
  NSLog(@"%s: rotated  kCentre    (%8.4f %8.4f %8.4f)", __FUNCTION__, kCentre.x, kCentre.y, kCentre.z);
  NSLog(@"%s: rotated  kEyeOffset [%8.4f %8.4f %8.4f]", __FUNCTION__, kEyeOffset.x, kEyeOffset.y, kEyeOffset.z);
  NSLog(@"%s: rotated  kEye       (%8.4f %8.4f %8.4f)", __FUNCTION__, kEye.x, kEye.y, kEye.z);
#endif
  
  
  _redrawPending=TRUE;

}

- (void)setFeatureEnable:(int)feature enable:(BOOL)enable {
  if(feature>=MAX_FEATURES) {
    NSLog(@"%s: feature %d (%s)", __FUNCTION__, feature, "INVALID");
    return;
  }
  NSLog(@"%s: feature %d (%s)", __FUNCTION__, feature, features[feature]);
  enabled[feature]=enable;
  
  _redrawPending=TRUE;

}

- (void)toggleFeature:(int)feature {
  if(feature>=MAX_FEATURES) {
    NSLog(@"%s: feature %d (%s)", __FUNCTION__, feature, "INVALID");
    return;
  }
  NSLog(@"%s: feature %d (%s)", __FUNCTION__, feature, features[feature]);
  enabled[feature]=!enabled[feature];
  
  _redrawPending=TRUE;

}

- (void)zoom:(float)scale {
  model_scale*=scale;
  
  //[self updateConstantBuffer];
  
  _redrawPending=TRUE;

}

- (void) moveToward:(float3)destination scale:(float)scale {
  NSLog(@"%s: MOVETO (%8.4f %8.4f %8.4f) @ %8.4f from (%8.4f %8.4f %8.4f)", __FUNCTION__, destination.x, destination.y, destination.z, scale, kEye.x, kEye.y, kEye.z);

  float3 step=(kEye-destination)*scale;
  NSLog(@"%s: STEP   (%8.4f %8.4f %8.4f)", __FUNCTION__, step.x, step.y, step.z);
  
  
  kEye.x-=step.x;
  kEye.y-=step.y;
  kEye.z-=step.z;

  kCentre.x-=step.x;
  kCentre.y-=step.y;
  kCentre.z-=step.z;
  
  NSLog(@"%s: EYE@  (%8.4f %8.4f %8.4f)", __FUNCTION__, kEye.x, kEye.y, kEye.z);
  NSLog(@"%s: CEN@  (%8.4f %8.4f %8.4f)", __FUNCTION__, kCentre.x, kCentre.y, kCentre.z);
  _viewMatrix = lookAt(kEye, kCentre, kUp);

  _redrawPending=TRUE;

}

- (void)setUpdate:(BOOL)pending {
  NSLog(@"%s: %d", __FUNCTION__, pending);

  _redrawPending=pending;
}
  
- (BOOL)keyDown:(NSString *)characters keycode:(uint)keyCode{
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
  if ([characters isEqual:@"p"]) {
    // Toggle the stations...
    [self toggleFeature:FEATURE_GALACTIC_PLANE];
    return TRUE;
  }
  if ([characters isEqual:@"["]) {
    [self moveToward:kCentre scale:0.05];
    return TRUE;
  }
  if ([characters isEqual:@"]"]) {
    [self moveToward:kCentre scale:-0.05];
    return TRUE;
  }
  if ([characters isEqual:@","]) {
    [self rotateView:0.0f y:1.0f z:0.0f];
    return TRUE;
  }
  if ([characters isEqual:@"."]) {
    [self rotateView:0.0f y:-1.0f z:0.0f];
    return TRUE;
  }
  if ([characters isEqual:@"h"]) {
    // Toggle the star distance intensity
    if(_star_decay<0.01f) {
      _star_decay=DECAY_DEFAULT;
    } else {
      _star_decay=0.0f;
    }
    NSLog(@"%s: _star_decay now %8.4f", __FUNCTION__, _star_decay);
    _redrawPending=TRUE;
    return TRUE;
  }
  switch(keyCode) {
    case 123 : // LEFT cursor
      [self rotateSelf:0.0f y:1.0f z:0.0f];
      return TRUE;
    case 124 : // RIGHT cursor
      [self rotateSelf:0.0f y:-1.0f z:0.0f];
      return TRUE;
    case 125 : //
      [self rotateSelf:1.0f y:0.0f z:0.0f];
      return TRUE;
    case 126 : //
      [self rotateSelf:-1.0f y:0.0f z:0.0f];
      return TRUE;
  }
  return FALSE;
}

@end

