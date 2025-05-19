cmake_minimum_required(VERSION 3.28...3.30)

add_library(libobs-metal SHARED)
add_library(OBS::libobs-metal ALIAS libobs-metal)

target_sources(
  libobs-metal
  PRIVATE
    libobs-metal-Bridging-Header.h
    metal-subsystem.swift
    MetalDevice.swift
    MetalTexture.swift
    MetalRenderState.swift
    MetalBuffer.swift
    MetalShader.swift
    MetalShader+Extensions.swift
    OBSShader.swift
    metal-stagesurf.swift
    metal-texture2d.swift
    metal-texture3d.swift
    metal-indexbuffer.swift
    metal-vertexbuffer.swift
    metal-samplerstate.swift
    metal-zstencilbuffer.swift
    metal-swapchain.swift
    metal-shader.swift
    metal-unimplemented.swift
    OBSSwapChain.swift
    libobs+Extensions.swift
    Sequence+Hashable.swift
    MTLPixelFormat+Extensions.swift
    MTLTextureType+Extensions.swift
    MTLCullMode+Extensions.swift
    MTLViewport+Extensions.swift
    MTLTexture+Extensions.swift
)

target_link_libraries(libobs-metal PRIVATE OBS::libobs)

target_enable_feature(libobs "Metal renderer")

set_property(SOURCE OBSMetalRenderer.swift APPEND PROPERTY COMPILE_FLAGS -emit-objc-header)

set_target_properties_obs(
    libobs-metal
    PROPERTIES FOLDER core
               VERSION 0
               PREFIX ""
)

set_target_xcode_properties(
    libobs-metal
    PROPERTIES SWIFT_VERSION 6.0
               CLANG_ENABLE_OBJC_ARC YES
               CLANG_WARN_SUSPICIOUS_IMPLICIT_CONVERSION YES
               GCC_WARN_SHADOW YES
               CLANG_ENABLE_MODULES YES
               CLANG_MODULES_AUTOLINK YES
               GCC_STRICT_ALIASING YES
               DEFINES_MODULE YES
               SWIFT_OBJC_BRIDGING_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/libobs-metal-Bridging-Header.h"
)
