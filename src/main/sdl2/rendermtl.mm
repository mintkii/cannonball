//
//  rendermetal.mm
//  CannonBall
//
//  Created by Kii on 2025-05-13.
//
#include "rendermtl.hpp"
#include "frontend/config.hpp"
#include <iostream>

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

// Required for getting native window handle from SDL
#include <SDL2/SDL_syswm.h>


// TODO: move to separate file?
const char* SHADER_SOURCE = R"(
#include <metal_stdlib>
using namespace metal;

struct VertexOut
{
    float4 position [[position]];
    float2 texCoord;
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
                              texture2d<float> screenTexture [[texture(0)]],
                              texture2d<float> scanlineTexture [[texture(1)]],
                              constant float &scanlineAlpha [[buffer(1)]])
{
    // nearest neighbour
    constexpr sampler s(mag_filter::nearest, min_filter::nearest, address::clamp_to_edge);
    constexpr sampler s_scan(mag_filter::linear, min_filter::linear, address::repeat);


    float4 screenColor = screenTexture.sample(s, in.texCoord);

    if (scanlineAlpha > 0.0)
    {
        float2 scan_coord = float2(in.texCoord.x, in.position.y / 2.0);
        float4 scanlineColor = scanlineTexture.sample(s_scan, scan_coord);
                
        screenColor = mix(screenColor, scanlineColor, scanlineAlpha);
    }
    
    return screenColor;
}
)";

Render::Render() : window(nullptr), native_window(nullptr), scanline_alpha(0.0f), enable_scanlines(false)
{
    mtl_device = nil;
    mtl_queue = nil;
    mtl_pipeline_state = nil;
    mtl_screen_texture = nil;
    mtl_scanline_texture = nil;
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
    this->enable_scanlines = scanlines && (scale != 1 || video_mode != video_settings_t::MODE_WINDOW);
    
    if (!RenderBase::sdl_screen_size()) return false;
    
    int flags = SDL_WINDOW_METAL;
    
    // TODO: These don't actually work correctly.
    if (video_mode == video_settings_t::MODE_FULL)
    {
        uint32_t w = (scn_width << 16) / src_width;
        uint32_t h = (scn_height << 16) / src_height;
        dst_width = (src_width * std::min(w, h)) >> 16;
        dst_height = (src_height * std::min(w, h)) >> 16;
        flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
        SDL_ShowCursor(false);
    }
    else if (video_mode == video_settings_t::MODE_STRETCH)
    {
        dst_width = scn_width;
        dst_height = scn_height;
        flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
        SDL_ShowCursor(false);
    }
    else
    {
        scn_width = dst_width = src_width * scale;
        scn_height = dst_height = src_height * scale;
        SDL_ShowCursor(true);
    }
    
    if (video_mode != video_settings_t::MODE_STRETCH)
    {
        screen_xoff = (scn_width - dst_width) / 2;
        screen_yoff = (scn_height - dst_height) / 2;
    }
    else
    {
        screen_xoff = 0;
        screen_yoff = 0;
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
    // Get a valid Metal device
    mtl_device = MTLCreateSystemDefaultDevice();
    if (!mtl_device)
    {
        std::cerr << "Metal is not supported on this device." << std::endl;
        return false;
    }
    
    // Setup CAMetalLayer on the SDL window
    SDL_SysWMinfo wmInfo;
    SDL_VERSION(&wmInfo.version);
    SDL_GetWindowWMInfo(window, &wmInfo);
    
    native_window = (__bridge void*)wmInfo.info.cocoa.window;
    NSWindow* ns_win = (__bridge NSWindow*)native_window;
    
    CAMetalLayer* metal_layer = [CAMetalLayer layer];
    metal_layer.device = mtl_device;
    metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metal_layer.framebufferOnly = YES;
    metal_layer.drawableSize = CGSizeMake(scn_width, scn_height);
    
    ns_win.contentView.layer = metal_layer;
    ns_win.contentView.wantsLayer = YES;
    
    mtl_queue = [mtl_device newCommandQueue];
    if (!mtl_queue) return false;
    
    if (!create_pipeline_state()) return false;
    
    if (!create_textures()) return false;
    
    return true;
}

void Render::disable()
{
    // Release Metal objects
    mtl_pipeline_state = nil;
    mtl_queue = nil;
    mtl_screen_texture = nil;
    mtl_scanline_texture = nil;
    mtl_device = nil;
    
    if (window)
    {
        SDL_DestroyWindow(window);
        window = nullptr;
        native_window = nullptr;
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
    
    id<MTLLibrary> library = [mtl_device newLibraryWithSource:[NSString stringWithUTF8String:SHADER_SOURCE] options:nil error:&error];
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
    
    mtl_pipeline_state = [mtl_device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!mtl_pipeline_state)
    {
        std::cerr << "Failed to create Metal pipeline: " << [[error localizedDescription] UTF8String] << std::endl;
        return false;
    }
    return true;
}

bool Render::create_textures()
{
    // Main screen texture
    MTLTextureDescriptor* screen_desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                           width:src_width
                                                                                          height:src_height
                                                                                       mipmapped:NO];
    screen_desc.usage = MTLTextureUsageShaderRead;
    mtl_screen_texture = [mtl_device newTextureWithDescriptor:screen_desc];
    if (!mtl_screen_texture) return false;
    
    // Scanline texture
    MTLTextureDescriptor* scanline_desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                             width:1
                                                                                            height:2
                                                                                         mipmapped:NO];
    scanline_desc.usage = MTLTextureUsageShaderRead;
    mtl_scanline_texture = [mtl_device newTextureWithDescriptor:scanline_desc];
    if (!mtl_scanline_texture) return false;
    
    // Pixel data for the scanline texture
    uint32_t scanline_pixels[] = { 0x00000000, 0xff000000 };
    MTLRegion region = {{0, 0, 0}, {1, 2, 1}};
    [mtl_scanline_texture replaceRegion:region mipmapLevel:0 withBytes:scanline_pixels bytesPerRow:4];
    
    if (enable_scanlines)
    {
        scanline_alpha = ((scanlines - 1) * 255) / 100.0f / 255.0f;
    }
    
    return true;
}

bool Render::start_frame() { return true; }
bool Render::finalize_frame() { return true; }
bool Render::supports_vsync() { return true; /* VSync is default behavior for CAMetalLayer */ }

void Render::draw_frame(uint16_t* pixels)
{
    // Game doesn't render alpha pixels, but for rendering, we need to account for that.
    // So all this does is force a full alpha channel.
    uint32_t* spix = screen_pixels;
    for (int i = 0; i < (src_width * src_height); i++)
    {
        // Take the RGB color and use a bitwise OR to set its alpha bits.
        *(spix++) = rgb[*(pixels++)] | 0xFF000000;
    }
    
    // Update texture
    MTLRegion region = {{0, 0, 0}, { (NSUInteger)src_width, (NSUInteger)src_height, 1 }};
    [mtl_screen_texture replaceRegion:region mipmapLevel:0 withBytes:screen_pixels bytesPerRow:src_width * 4];
    
    CAMetalLayer* metal_layer = (CAMetalLayer*)((__bridge NSWindow*)native_window).contentView.layer;
    id<CAMetalDrawable> drawable = [metal_layer nextDrawable];
    if (!drawable) return;
    
    // Render pass descriptor
    MTLRenderPassDescriptor* pass_desc = [MTLRenderPassDescriptor renderPassDescriptor];
    pass_desc.colorAttachments[0].texture = drawable.texture;
    pass_desc.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass_desc.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass_desc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    
    id<MTLCommandBuffer> command_buffer = [mtl_queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [command_buffer renderCommandEncoderWithDescriptor:pass_desc];
    
    // drawing commands
    [encoder setRenderPipelineState:mtl_pipeline_state];
    [encoder setFragmentTexture:mtl_screen_texture atIndex:0];
    [encoder setFragmentTexture:mtl_scanline_texture atIndex:1];
    [encoder setFragmentBytes:&scanline_alpha length:sizeof(float) atIndex:1];
    
    // screen quad
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    
    [encoder endEncoding];
    [command_buffer presentDrawable:drawable];
    [command_buffer commit];
}
