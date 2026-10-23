//
//  rendermetal.mm
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

#include <SDL2/SDL_metal.h>

// Frames the CPU may queue ahead of the GPU, each with its own screen texture
static const int MAX_FRAMES_IN_FLIGHT = 3;

// Must match the Uniforms struct in SHADER_SOURCE.
struct Uniforms
{
    float scanline_alpha;
    float scanline_count;
};

struct MetalState
{
    id<MTLDevice>              device;
    id<MTLCommandQueue>        queue;
    id<MTLRenderPipelineState> pipeline_state;
    id<MTLSamplerState>        screen_sampler;
    id<MTLSamplerState>        scanline_sampler;
    id<MTLTexture>             screen_textures[MAX_FRAMES_IN_FLIGHT];
    id<MTLTexture>             scanline_texture;
    CAMetalLayer*              layer;
    dispatch_semaphore_t       frame_semaphore = dispatch_semaphore_create(MAX_FRAMES_IN_FLIGHT);
    int                        frame_index = 0;
};

// TODO: move to separate file?
const char* SHADER_SOURCE = R"(
#include <metal_stdlib>
using namespace metal;

struct VertexOut
{
    float4 position [[position]];
    float2 texCoord;
};

struct Uniforms
{
    float scanlineAlpha;
    float scanlineCount;
};

vertex VertexOut vertex_main(uint vid [[vertex_id]])
{
    float2 texCoords[4] = {
        float2(0.0, 1.0), // Bottom-left
        float2(0.0, 0.0), // Top-left
        float2(1.0, 1.0), // Bottom-right
        float2(1.0, 0.0)  // Top-right
    };

    // These are the hardcoded positions for the four corners in Metal's
    // normalized device coordinates [-1, 1].
    float4 positions[4] = {
        float4(-1.0, -1.0, 0.0, 1.0), // Bottom-left
        float4(-1.0,  1.0, 0.0, 1.0), // Top-left
        float4( 1.0, -1.0, 0.0, 1.0), // Bottom-right
        float4( 1.0,  1.0, 0.0, 1.0)  // Top-right
    };

    VertexOut out;
    out.position = positions[vid];
    out.texCoord = texCoords[vid];
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> screenTexture   [[texture(0)]],
                              texture2d<float> scanlineTexture [[texture(1)]],
                              sampler          screenSampler   [[sampler(0)]],
                              sampler          scanlineSampler [[sampler(1)]],
                              constant Uniforms &u             [[buffer(0)]])
{
    float3 color = screenTexture.sample(screenSampler, in.texCoord).rgb;

    if (u.scanlineAlpha > 0.0)
    {
        // Repeats once per original scanline, like the Open GL renderer
        float2 scanCoord = float2(0.5, in.texCoord.y * u.scanlineCount);
        float  darkness  = scanlineTexture.sample(scanlineSampler, scanCoord).a;

        color *= 1.0 - darkness * u.scanlineAlpha;
    }

    return float4(color, 1.0);
}
)";

Render::Render() : window(nullptr), metal_view(nullptr), mtl(nullptr), scanline_alpha(0.0f)
{
}

Render::~Render()
{
    disable();
}

bool Render::init(int src_width, int src_height, int scale, int video_mode, int scanlines)
{
    this->src_width  = src_width;
    this->src_height = src_height;
    this->video_mode = video_mode;
    this->scanlines  = scanlines;
    this->scale      = scale;

    const bool enable_scanlines = scanlines && (scale != 1 || video_mode != video_settings_t::MODE_WINDOW);
    scanline_alpha = enable_scanlines ? (((scanlines - 1) << 8) / 100) / 255.0f : 0.0f;

    // Palette is written as 0x00RRGGBB, which is BGRA8Unorm in memory.
    Rshift = 16;
    Gshift = 8;
    Bshift = 0;

    if (!RenderBase::sdl_screen_size()) return false;

    int flags = SDL_WINDOW_METAL | SDL_WINDOW_ALLOW_HIGHDPI;

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

    // Create SDL Window
    window = SDL_CreateWindow("CannonBall", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, scn_width, scn_height, flags);
    if (!window)
    {
        std::cerr << "SDL_CreateWindow failed: " << SDL_GetError() << std::endl;
        return false;
    }

    if (screen_pixels) delete[] screen_pixels;
    screen_pixels = new uint32_t[src_width * src_height];

    if (!init_metal())
    {
        disable();
        return false;
    }

    return true;
}

bool Render::init_metal()
{
    mtl = new MetalState();

    // Get a valid Metal device
    mtl->device = MTLCreateSystemDefaultDevice();
    if (!mtl->device)
    {
        std::cerr << "Metal is not supported on this device." << std::endl;
        return false;
    }

    // SDL keeps the layer's drawableSize in sync with Retina and full-screen changes
    metal_view = SDL_Metal_CreateView(window);
    if (!metal_view)
    {
        std::cerr << "SDL_Metal_CreateView failed: " << SDL_GetError() << std::endl;
        return false;
    }

    mtl->layer = (__bridge CAMetalLayer*)SDL_Metal_GetLayer(metal_view);
    mtl->layer.device = mtl->device;
    mtl->layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    mtl->layer.framebufferOnly = YES;
    mtl->layer.opaque = YES;
    mtl->layer.displaySyncEnabled = config.video.vsync == 1;

    mtl->queue = [mtl->device newCommandQueue];
    if (!mtl->queue) return false;

    if (!create_pipeline_state()) return false;

    if (!create_samplers()) return false;

    if (!create_textures()) return false;

    return true;
}

void Render::disable()
{
    if (mtl)
    {
        // Wait for in-flight frames, then restore the count, as libdispatch
        // crashes if a semaphore is free below its initial value?
        for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
            dispatch_semaphore_wait(mtl->frame_semaphore, DISPATCH_TIME_FOREVER);
        for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
            dispatch_semaphore_signal(mtl->frame_semaphore);

        delete mtl;
        mtl = nullptr;
    }

    if (metal_view)
    {
        SDL_Metal_DestroyView(metal_view);
        metal_view = nullptr;
    }

    if (window)
    {
        SDL_DestroyWindow(window);
        window = nullptr;
    }

    if (screen_pixels)
    {
        delete[] screen_pixels;
        screen_pixels = nullptr;
    }
}

bool Render::create_pipeline_state()
{
    NSError* error = nil;

    id<MTLLibrary> library = [mtl->device newLibraryWithSource:[NSString stringWithUTF8String:SHADER_SOURCE] options:nil error:&error];
    if (!library)
    {
        std::cerr << "Failed to create Metal library: " << [[error localizedDescription] UTF8String] << std::endl;
        return false;
    }

    id<MTLFunction> vertex_func = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragment_func = [library newFunctionWithName:@"fragment_main"];

    MTLRenderPipelineDescriptor* desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = vertex_func;
    desc.fragmentFunction = fragment_func;
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    mtl->pipeline_state = [mtl->device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!mtl->pipeline_state)
    {
        std::cerr << "Failed to create Metal pipeline: " << [[error localizedDescription] UTF8String] << std::endl;
        return false;
    }
    return true;
}

bool Render::create_samplers()
{
    const MTLSamplerMinMagFilter filter = config.video.filtering ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;

    MTLSamplerDescriptor* screen_desc = [MTLSamplerDescriptor new];
    screen_desc.minFilter    = filter;
    screen_desc.magFilter    = filter;
    screen_desc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    screen_desc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    mtl->screen_sampler = [mtl->device newSamplerStateWithDescriptor:screen_desc];
    if (!mtl->screen_sampler) return false;

    MTLSamplerDescriptor* scanline_desc = [MTLSamplerDescriptor new];
    scanline_desc.minFilter    = MTLSamplerMinMagFilterLinear;
    scanline_desc.magFilter    = MTLSamplerMinMagFilterLinear;
    scanline_desc.sAddressMode = MTLSamplerAddressModeRepeat;
    scanline_desc.tAddressMode = MTLSamplerAddressModeRepeat;
    mtl->scanline_sampler = [mtl->device newSamplerStateWithDescriptor:scanline_desc];
    if (!mtl->scanline_sampler) return false;

    return true;
}

bool Render::create_textures()
{
    // Main screen textures
    MTLTextureDescriptor* screen_desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                           width:src_width
                                                                                          height:src_height
                                                                                       mipmapped:NO];
    screen_desc.usage = MTLTextureUsageShaderRead;
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
    {
        mtl->screen_textures[i] = [mtl->device newTextureWithDescriptor:screen_desc];
        if (!mtl->screen_textures[i]) return false;
    }

    // Scanline texture
    MTLTextureDescriptor* scanline_desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                             width:1
                                                                                            height:2
                                                                                         mipmapped:NO];
    scanline_desc.usage = MTLTextureUsageShaderRead;
    mtl->scanline_texture = [mtl->device newTextureWithDescriptor:scanline_desc];
    if (!mtl->scanline_texture) return false;

    // Pixel data for the scanline texture
    uint32_t scanline_pixels[] = { 0x00000000, 0xff000000 };
    MTLRegion region = {{0, 0, 0}, {1, 2, 1}};
    [mtl->scanline_texture replaceRegion:region mipmapLevel:0 withBytes:scanline_pixels bytesPerRow:4];

    return true;
}

bool Render::start_frame() { return true; }
bool Render::finalize_frame() { return true; }

bool Render::supports_vsync() { return true; }

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

        MTLRegion region = {{0, 0, 0}, { (NSUInteger)src_width, (NSUInteger)src_height, 1 }};
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

        if (video_mode == video_settings_t::MODE_FULL)
        {
            // Maintain aspect ratio
            const double ratio = std::min(drawable_w / src_width, drawable_h / src_height);
            out_w = std::floor(src_width  * ratio);
            out_h = std::floor(src_height * ratio);
        }

        MTLViewport viewport;
        viewport.originX = std::floor((drawable_w - out_w) / 2.0);
        viewport.originY = std::floor((drawable_h - out_h) / 2.0);
        viewport.width   = out_w;
        viewport.height  = out_h;
        viewport.znear   = 0.0;
        viewport.zfar    = 1.0;

        Uniforms uniforms;
        uniforms.scanline_alpha = scanline_alpha;
        uniforms.scanline_count = S16_HEIGHT; // Even in hi-res mode

        // Render pass descriptor
        MTLRenderPassDescriptor* pass_desc = [MTLRenderPassDescriptor renderPassDescriptor];
        pass_desc.colorAttachments[0].texture = drawable.texture;
        pass_desc.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass_desc.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass_desc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);

        id<MTLCommandBuffer> command_buffer = [mtl->queue commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [command_buffer renderCommandEncoderWithDescriptor:pass_desc];

        // drawing commands
        [encoder setViewport:viewport];
        [encoder setRenderPipelineState:mtl->pipeline_state];
        [encoder setFragmentTexture:screen_texture atIndex:0];
        [encoder setFragmentTexture:mtl->scanline_texture atIndex:1];
        [encoder setFragmentSamplerState:mtl->screen_sampler atIndex:0];
        [encoder setFragmentSamplerState:mtl->scanline_sampler atIndex:1];
        [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];

        // screen quad
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
