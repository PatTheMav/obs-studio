cmake_minimum_required(VERSION 3.22...3.25)

add_library(libobs-metal SHARED)
add_library(OBS::libobs-metal ALIAS libobs-metal)

target_sources(
    libobs-metal
    PRIVATE
        libobs-metal-Bridging-Header.h
        metal-subsystem.swift
        OBSBlendState.swift
        OBSIndexBuffer.swift
        OBSMetalDevice.swift
        OBSResourceCollection.swift
        OBSSamplerState.swift
        OBSShader.swift
        OBSStageSurface.swift
        OBSSwapChain.swift
        OBSTexture.swift
        OBSVertexBuffer.swift
        OBSZStencilBuffer.swift
        OBSShaderParser.swift
        libobs+Extensions.swift
        Sequence+Hashable.swift
)

target_link_libraries(libobs-metal PRIVATE OBS::libobs)

target_enable_feature(libobs "Metal renderer")

set_property(
    SOURCE OBSMetalRenderer.swift
    APPEND
    PROPERTY COMPILE_FLAGS -emit-objc-header
)

# cmake-format: off
set_target_properties_obs(
    libobs-metal
    PROPERTIES FOLDER core
               VERSION 0
               PREFIX ""
)

set_target_xcode_properties(
    libobs-metal
    PROPERTIES SWIFT_VERSION 5.0
               CLANG_ENABLE_OBJC_ARC YES
               CLANG_WARN_SUSPICIOUS_IMPLICIT_CONVERSION YES
               GCC_WARN_SHADOW YES
               CLANG_ENABLE_MODULES YES
               CLANG_MODULES_AUTOLINK YES
               GCC_STRICT_ALIASING YES
               DEFINES_MODULE YES
               SWIFT_OBJC_BRIDGING_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/libobs-metal-Bridging-Header.h"
)
# cmake-format: on
