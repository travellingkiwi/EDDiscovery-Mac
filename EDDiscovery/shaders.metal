/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 lighting shader for Basic Metal 3D
 */

#include <metal_stdlib>
#include <simd/simd.h>
#include "AAPLSharedTypes.h"

using namespace metal;

typedef struct
{
  packed_float3 position;
  packed_float3 normal;
} vertex_t;

typedef struct {
  packed_float3 position;
  //packed_float4 colour;
} journey_vertex_t;

struct ColorInOut {
  float4 position [[position]];
  float point_size [[ point_size ]];
  half4 color;
};

// vertex shader function
vertex ColorInOut simple_line_vertex(device journey_vertex_t* vertex_array [[ buffer(0) ]],
                                      constant AAPL::constants_t& constants [[ buffer(1) ]],
                                      constant float4 *colour,
                                      constant float *point_size,
                                      unsigned int vid [[ vertex_id ]]) {
  ColorInOut out;
  
  float4 in_position = float4(float3(vertex_array[vid].position), 1.0);
  out.position = constants.modelview_projection_matrix * in_position;
  out.point_size = *point_size;
  
  out.color = half4(*colour);
  //out.color = half4(constants.ambient_color + constants.diffuse_color);
  
  return out;
}

// fragment shader function
fragment half4 simple_line_frag(ColorInOut in [[stage_in]]) {
  return in.color;
};


// vertex shader function
vertex ColorInOut journey_path_vertex(device journey_vertex_t* vertex_array [[ buffer(0) ]],
                                 constant AAPL::constants_t& constants [[ buffer(1) ]],
                                 constant float4 *colour,
                                 constant float *point_size,
                                 unsigned int vid [[ vertex_id ]]) {
  ColorInOut out;
  
  float4 in_position = float4(float3(vertex_array[vid].position), 1.0);
  out.position = constants.modelview_projection_matrix * in_position;
  out.point_size = *point_size;
  
  out.color = half4(*colour);
  //out.color = half4(constants.ambient_color + constants.diffuse_color);
  
  return out;
}

// fragment shader function
fragment half4 journey_path_frag(ColorInOut in [[stage_in]]) {
  return in.color;
};

// vertex shader function
vertex ColorInOut journey_star_vertex(device journey_vertex_t* vertex_array [[ buffer(0) ]],
                                     constant AAPL::constants_t& constants [[ buffer(1) ]],
                                     constant float4 *colour,
                                     constant float *point_size,
                                     unsigned int vid [[ vertex_id ]]) {
  ColorInOut out;
  
  float4 in_position = float4(float3(vertex_array[vid].position), 1.0);
  out.position = constants.modelview_projection_matrix * in_position;
  out.point_size = *point_size;

  out.color =  half4(*colour);
  
  return out;
}

// fragment shader function
fragment half4 journey_star_frag(ColorInOut in [[stage_in]]) {
  return in.color;
}

// vertex shader function
vertex ColorInOut galaxy_star_vertex(device journey_vertex_t* vertex_array [[ buffer(0) ]],
                              constant AAPL::constants_t& constants [[ buffer(1) ]],
                              constant float4 *colour,
                              constant float *decay,
                              constant float *point_size,
                              unsigned int vid [[ vertex_id ]]) {
  ColorInOut out;
  
  // Test here for distance from centre... If we're too far away, just dont' draw it...
  float sep=distance(constants.kEye, vertex_array[vid].position);
  
  //if(sep > some_magic_distance) {
  //  discard_fragment();
  //} else {
    float4 in_position = float4(float3(vertex_array[vid].position), 1.0);
    out.position = constants.modelview_projection_matrix * in_position;
    out.point_size = *point_size;

    // The colour of a star should vary with distance. The furher away, the more diffuse it should be
    // however it should also combine wth the colours already present so two stars 'close' to each other
    // will provide for a brighter point
    // The centre position is in constants.kCentre
    if(*decay==0.0f) {
      out.color=half4(*colour);
    } else {
      out.color = half4((*colour) * float4x4(*decay/sep));
    }
  //}
  
  return out;
}

// fragment shader function
fragment half4 galaxy_star_frag(ColorInOut in [[stage_in]]) {
  return in.color;
}
