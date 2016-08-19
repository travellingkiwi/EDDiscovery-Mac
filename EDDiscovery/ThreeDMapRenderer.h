//
//  ThreeDMapRenderer.h
//  EDDiscovery
//
//  3D Views by Hamish Marson <hamish@travellingkiwi.com> 10/07/2016
//  Copyright © 2016 Hamish Marson. All rights reserved.
//
//  Based on Apple MetalRenderer example

#import "ThreeDMapView.h"
#import "ThreeDMapViewController.h"

#import <simd/simd.h>
#import <Metal/Metal.h>

@interface ThreeDMapRenderer : NSObject <ThreeDMapViewControllerDelegate, ThreeDMapViewDelegate>

#define SYSTEMS_PER_BLOCK 100000
#define JUMPS_PER_BLOCK     1000
#define MAX_CLOSEST          100                            // SHow this many closest jumps... MUST be < JUMPS_PER_BLOCK

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

typedef struct SystemVertex {
  float  posx;
  float  posy;
  float  posz;
  //packed_float4  colour;
} SystemVertex_t;

typedef struct JourneyVertex {
  float  posx;
  float  posy;
  float  posz;
  //packed_float4  colour;
} JourneyVertex_t;

typedef struct StationVertex {
  float  posx;
  float  posy;
  float  posz;
  int    stype;
} StationVertex_t;

// The galaxy is made up of lots of these...
typedef struct galaxy_block_struct {
  int numsystems;
  SystemVertex_t systems[SYSTEMS_PER_BLOCK];
  
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

typedef struct station_block_struct {
  int numstations;
  StationVertex_t stations[SYSTEMS_PER_BLOCK];
  
  struct station_block_struct *prev;
  struct station_block_struct *next;
  
} station_block_t;

typedef struct text_block_struct {

  //CIImage *image;
  float    pos_x;
  float    pos_y;
  float    pos_z;
  
  struct text_block_struct *next;
  struct text_block_struct *prev;
} text_block_t;

typedef struct galaxy_struct {
  //modelview_projection_matrix;
  // The main data
  uint num_galaxy_blocks;
  uint total_systems;
  uint total_journey_points;
  uint total_stations;

  galaxy_block_t *first_galaxy_block;
  galaxy_block_t *last_galaxy_block;

  uint num_journey_blocks;

  
  journey_block_t *first_journey_block;
  journey_block_t *last_journey_block;

  SystemVertex_t   closest[MAX_CLOSEST];
  
  uint num_station_blocks;
  
  station_block_t *first_station_block;
  station_block_t *last_station_block;
  
  text_block_t *first_text_block;
  text_block_t *last_text_block;
  
} galaxy_t;

#define FEATURE_JOURNEY            0
#define FEATURE_JSTARS             1
#define FEATURE_STATIONS           2
#define MAX_FEATURES               3

// load all assets before triggering rendering
- (void)configure:(ThreeDMapView *)view galaxy:(galaxy_t *)galaxy;
//- (void)setVertexBuffer:(galaxy_t *)galaxy;
- (void)setPosition:(float)x y:(float)y z:(float)z;
- (void)setFeatureEnable:(int)feature enable:(BOOL)enable;
- (void)zoom:(float)direction;
- (BOOL)keyDown:(NSString *)characters;

@end
