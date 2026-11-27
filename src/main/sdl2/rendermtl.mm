//
//  rendermtl.mm
//  CannonBall
//
//  Created by Kii on 2025-05-13.
//
#include "rendermtl.hpp"
#include "frontend/config.hpp"
#include <iostream>
#include <algorithm>
#include <cmath>

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

// Frames the CPU may queue ahead of the GPU, each with its own screen texture
static const int MAX_FRAMES_IN_FLIGHT = 3;

struct MetalState
{
    SDL_MetalView              view;
    CAMetalLayer*              layer;
    id<MTLCommandQueue>        queue;
    id<MTLRenderPipelineState> pipeline_state;
    id<MTLSamplerState>        sampler;
    id<MTLTexture>             screen_textures[MAX_FRAMES_IN_FLIGHT];
    int                        frame_index = 0;
    float                      scanline_alpha;

    // semaphore!!!!!
    dispatch_semaphore_t       frame_semaphore = dispatch_semaphore_create(0);
};

// TODO: move to separate file?
static const char SHADER_SOURCE[] = R"(
#include <metal_stdlib>
using namespace metal;

struct VertexOut
{
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_main(uint vid [[vertex_id]])
{
    float2 uv = float2(vid >> 1, vid & 1);

    VertexOut out;
    out.position = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);
    out.texCoord = uv;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> screen [[texture(0)]],
                              sampler          smp    [[sampler(0)]],
                              constant float&  scanlineAlpha [[buffer(0)]])
{
    float3 color = screen.sample(smp, in.texCoord).rgb;

    // emulation of the OpenGL texture
    float darkness = abs(fract(in.texCoord.y * SCANLINES + 0.25) * 2.0 - 1.0);
    color *= 1.0 - darkness * scanlineAlpha;

    return float4(color, 1.0);
}
)";

bool Render::init(int src_width, int src_height, int scale, int video_mode, int scanlines)
{
    this->src_width  = src_width;
    this->src_height = src_height;
    this->video_mode = video_mode;

    // Palette is written as 0x00RRGGBB, which is BGRA8Unorm in memory.
    Rshift = 16;
    Gshift = 8;
    Bshift = 0;

    if (!RenderBase::sdl_screen_size()) return false;

    int flags = SDL_WINDOW_METAL | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_RESIZABLE;

    // Output rect is derived from the drawable size in draw_frame()
    if (video_mode == video_settings_t::MODE_WINDOW)
    {
        scn_width  = src_width  * scale;
        scn_height = src_height * scale;
        SDL_ShowCursor(true);
    }
    else
    {
        flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
        SDL_ShowCursor(false);
    }

    window = SDL_CreateWindow("CannonBall", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, scn_width, scn_height, flags);
    if (!window)
    {
        std::cerr << "SDL_CreateWindow failed: " << SDL_GetError() << std::endl;
        return false;
    }

    screen_pixels = new uint32_t[src_width * src_height];

    mtl = new MetalState();
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
        dispatch_semaphore_signal(mtl->frame_semaphore);

    const bool enable_scanlines = scanlines && (scale != 1 || video_mode != video_settings_t::MODE_WINDOW);
    mtl->scanline_alpha = enable_scanlines ? (scanlines - 1) / 100.0f : 0.0f;

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device)
    {
        std::cerr << "Metal is not supported on this device." << std::endl;
        disable();
        return false;
    }

    // SDL keeps the layer's drawableSize in sync with Retina and full-screen changes
    mtl->view  = SDL_Metal_CreateView(window);
    mtl->layer = (__bridge CAMetalLayer*)SDL_Metal_GetLayer(mtl->view);
    mtl->layer.device = device;
    mtl->layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    mtl->layer.opaque = YES;
    mtl->layer.displaySyncEnabled = config.video.vsync == 1;

    mtl->queue = [device newCommandQueue];

    // Pipeline
    NSError* error = nil;
    MTLCompileOptions* options = [MTLCompileOptions new];
    options.preprocessorMacros = @{ @"SCANLINES": @(S16_HEIGHT) }; // Even in hi-res mode

    id<MTLLibrary> library = [device newLibraryWithSource:@(SHADER_SOURCE) options:options error:&error];
    if (library)
    {
        MTLRenderPipelineDescriptor* desc = [MTLRenderPipelineDescriptor new];
        desc.vertexFunction   = [library newFunctionWithName:@"vertex_main"];
        desc.fragmentFunction = [library newFunctionWithName:@"fragment_main"];
        desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        mtl->pipeline_state = [device newRenderPipelineStateWithDescriptor:desc error:&error];
    }
    if (!mtl->pipeline_state)
    {
        std::cerr << "Failed to create Metal pipeline: " << error.localizedDescription.UTF8String << std::endl;
        disable();
        return false;
    }

    // Sampler and screen textures
    MTLSamplerDescriptor* sampler_desc = [MTLSamplerDescriptor new];
    sampler_desc.minFilter = sampler_desc.magFilter = config.video.filtering ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;
    mtl->sampler = [device newSamplerStateWithDescriptor:sampler_desc];

    MTLTextureDescriptor* texture_desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                            width:src_width
                                                                                           height:src_height
                                                                                        mipmapped:NO];
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
        mtl->screen_textures[i] = [device newTextureWithDescriptor:texture_desc];

    return true;
}

void Render::disable()
{
    if (mtl)
    {
        // Let in-flight frames finish before tearing down
        for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
            dispatch_semaphore_wait(mtl->frame_semaphore, DISPATCH_TIME_FOREVER);

        if (mtl->view) SDL_Metal_DestroyView(mtl->view);
        delete mtl;
        mtl = nullptr;
    }

    if (window)
    {
        SDL_DestroyWindow(window);
        window = nullptr;
    }

    delete[] screen_pixels;
    screen_pixels = nullptr;
}

bool Render::supports_vsync()
{
    // Only let V-Sync pace the game when the display refreshes at the game's frame rate
    SDL_DisplayMode mode;
    return SDL_GetCurrentDisplayMode(SDL_GetWindowDisplayIndex(window), &mode) == 0 &&
           std::abs(mode.refresh_rate - config.fps) <= 1;
}

void Render::draw_frame(uint16_t* pixels)
{
    if (!mtl) return;

    @autoreleasepool
    {
        // Lookup real RGB value from rgb array
        uint32_t* spix = screen_pixels;
        for (int i = 0; i < (src_width * src_height); i++)
            *(spix++) = rgb[*(pixels++)];

        dispatch_semaphore_wait(mtl->frame_semaphore, DISPATCH_TIME_FOREVER);

        id<MTLTexture> screen_texture = mtl->screen_textures[mtl->frame_index];
        mtl->frame_index = (mtl->frame_index + 1) % MAX_FRAMES_IN_FLIGHT;

        MTLRegion region = MTLRegionMake2D(0, 0, src_width, src_height);
        [screen_texture replaceRegion:region mipmapLevel:0 withBytes:screen_pixels bytesPerRow:src_width * 4];

        id<CAMetalDrawable> drawable = [mtl->layer nextDrawable];
        if (!drawable)
        {
            dispatch_semaphore_signal(mtl->frame_semaphore);
            return;
        }

        const double drawable_w = drawable.texture.width;
        const double drawable_h = drawable.texture.height;
        double out_w = drawable_w;
        double out_h = drawable_h;

        if (video_mode != video_settings_t::MODE_STRETCH)
        {
            // Maintain aspect ratio
            const double ratio = std::min(drawable_w / src_width, drawable_h / src_height);
            out_w = std::floor(src_width  * ratio);
            out_h = std::floor(src_height * ratio);
        }

        MTLViewport viewport = { std::floor((drawable_w - out_w) / 2.0), std::floor((drawable_h - out_h) / 2.0), out_w, out_h, 0.0, 1.0 };

        MTLRenderPassDescriptor* pass_desc = [MTLRenderPassDescriptor renderPassDescriptor];
        pass_desc.colorAttachments[0].texture = drawable.texture;
        pass_desc.colorAttachments[0].loadAction = MTLLoadActionClear;

        id<MTLCommandBuffer> command_buffer = [mtl->queue commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [command_buffer renderCommandEncoderWithDescriptor:pass_desc];
        [encoder setViewport:viewport];
        [encoder setRenderPipelineState:mtl->pipeline_state];
        [encoder setFragmentTexture:screen_texture atIndex:0];
        [encoder setFragmentSamplerState:mtl->sampler atIndex:0];
        [encoder setFragmentBytes:&mtl->scanline_alpha length:sizeof(float) atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [encoder endEncoding];

        dispatch_semaphore_t semaphore = mtl->frame_semaphore;
        [command_buffer addCompletedHandler:^(id<MTLCommandBuffer>) {
            dispatch_semaphore_signal(semaphore);
        }];

        [command_buffer presentDrawable:drawable];
        [command_buffer commit];
    }
}
