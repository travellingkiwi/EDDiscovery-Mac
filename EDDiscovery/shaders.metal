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
  packed_float4 colour;
} journey_vertex_t;

struct ColorInOut {
  float4 position [[position]];
  half4 color;
};

// vertex shader function
vertex ColorInOut journey_vertex(device journey_vertex_t* vertex_array [[ buffer(0) ]],
                                  constant AAPL::constants_t& constants [[ buffer(1) ]],
                                  unsigned int vid [[ vertex_id ]]) {
  ColorInOut out;
  
  float4 in_position = float4(float3(vertex_array[vid].position), 1.0);
  out.position = constants.modelview_projection_matrix * in_position;
  
  out.color = half4(vertex_array[vid].colour);
  //out.color = half4(constants.ambient_color + constants.diffuse_color);

  return out;
}

// fragment shader function
fragment half4 journey_fragment(ColorInOut in [[stage_in]]) {
  return in.color;
};

// vertex shader function
vertex ColorInOut journey_star_vertex(device journey_vertex_t* vertex_array [[ buffer(0) ]],
                                 constant AAPL::constants_t& constants [[ buffer(1) ]],
                                 unsigned int vid [[ vertex_id ]]) {
  ColorInOut out;
  
  float4 in_position = float4(float3(vertex_array[vid].position), 1.0);
  out.position = constants.modelview_projection_matrix * in_position;
  
  out.color =  half4(vertex_array[vid].colour);
  
  return out;
}

// fragment shader function
fragment half4 journey_star_fragment(ColorInOut in [[stage_in]]) {
  return in.color;
}
