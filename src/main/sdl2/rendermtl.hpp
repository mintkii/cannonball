//
//  rendermtl.hpp
//  CannonBall
//
//  Created by Kii on 2025-05-13.
//
#pragma once

#include "renderbase.hpp"

// Defined in rendermtl.mm
struct MetalState;

class Render : public RenderBase
{
public:
    ~Render() override { disable(); }
    bool init(int src_width, int src_height,
              int scale,
              int video_mode,
              int scanlines) override;
    void disable() override;
    bool start_frame() override    { return true; }
    bool finalize_frame() override { return true; }
    void draw_frame(uint16_t* pixels) override;
    bool supports_vsync() override;

private:
    SDL_Window* window = nullptr;
    MetalState* mtl    = nullptr;
};
