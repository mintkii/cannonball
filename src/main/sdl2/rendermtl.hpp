//
//  rendermetal.hpp
//  CannonBall
//
//  Created by Kii on 2025-05-13.
//
#pragma once

#include "renderbase.hpp"
#include <SDL2/SDL.h>

#ifdef __OBJC__
@protocol MTLDevice, MTLCommandQueue, MTLRenderPipelineState, MTLBuffer, MTLTexture;
#else
typedef void* id;
#endif

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
    bool create_textures();

    SDL_Window* window;
    void* native_window;

    // Metal Objects
    id<MTLDevice>               mtl_device;
    id<MTLCommandQueue>         mtl_queue;
    id<MTLRenderPipelineState>  mtl_pipeline_state;
    id<MTLTexture>              mtl_screen_texture;
    id<MTLTexture>              mtl_scanline_texture;

    float scanline_alpha;

    bool enable_scanlines;
};
