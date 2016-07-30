/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Metal Renderer for Metal Basic 3D. Acts as the update and render delegate for the view controller and performs rendering. In MetalBasic3D, the renderer draws N cubes, whos color values change every update.
 */

#import "ThreeDMapView.h"
#import "ThreeDMapViewController.h"

#import <simd/simd.h>
#import <Metal/Metal.h>

@interface ThreeDMapRenderer : NSObject <ThreeDMapViewControllerDelegate, ThreeDMapViewDelegate>

#define SYSTEMS_PER_BLOCK 1000000
#define JUMPS_PER_BLOCK 1000

// enum to denote the type of star
typedef NS_ENUM(NSInteger, system_type) {
  system_type_empty,                                        // Special case.. Record is unused...
  system_type_m,
  system_type_t,
};

// Optimised for Metal...
// A star system.. Just position and colour...
typedef struct PosVertex {
  float  posx;
  float  posy;
  float  posz;
} PosVertex_t;

typedef struct JourneyVertex {
  float  posx;
  float  posy;
  float  posz;
  packed_float4  colour;
} JourneyVertex_t;

// The galaxy is made up of lots of these...
typedef struct galaxy_block_struct {
  int numsystems;
  PosVertex_t systems[SYSTEMS_PER_BLOCK];
  
  struct galaxy_block_struct *prev;
  struct galaxy_block_struct *next;
  
} galaxy_block_t;

// A journey is made up of lots of these...
typedef struct journey_block_struct {
  int numsystems;
  JourneyVertex_t systems[JUMPS_PER_BLOCK];
  
  struct journey_block_struct *prev;
  struct journey_block_struct *next;
  
} journey_block_t;


typedef struct galaxy_struct {
  //modelview_projection_matrix;
  // The main data
  galaxy_block_t *first_galaxy_block;
  galaxy_block_t *last_galaxy_block;

  int num_journey_blocks;
  
  journey_block_t *first_journey_block;
  journey_block_t *last_journey_block;

} galaxy_t;


// load all assets before triggering rendering
- (void)configure:(ThreeDMapView *)view galaxy:(galaxy_t *)galaxy;
- (void)setVertexBuffer:(galaxy_t *)galaxy;

@end
