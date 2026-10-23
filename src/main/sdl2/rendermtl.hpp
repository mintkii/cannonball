//
//  rendermetal.hpp
//  CannonBall
//
//  Created by Kii on 2025-05-13.
//
#pragma once

#include "renderbase.hpp"
#include <SDL2/SDL.h>

// Defined in rendermtl.mm
struct MetalState;

class Render : public RenderBase
{
public:
    Render();
    ~Render();
    bool init(int src_width, int src_height,
              int scale,
              int video_mode,
              int scanlines);
    void disable();
    bool start_frame();
    bool finalize_frame();
    void draw_frame(uint16_t* pixels);
    bool supports_vsync();

private:
    bool init_metal();
    bool create_pipeline_state();
    bool create_samplers();
    bool create_textures();

    SDL_Window*  window;
    SDL_MetalView metal_view;
    MetalState*  mtl;

    float scanline_alpha;
};
