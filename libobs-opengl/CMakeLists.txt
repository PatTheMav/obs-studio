cmake_minimum_required(VERSION 3.22...3.27)

legacy_check()

add_library(libobs-opengl SHARED)
add_library(OBS::libobs-opengl ALIAS libobs-opengl)

if(NOT TARGET OBS::glad)
  add_subdirectory("${CMAKE_SOURCE_DIR}/deps/glad" "${CMAKE_BINARY_DIR}/deps/glad")
endif()

target_sources(
  libobs-opengl
  PRIVATE # cmake-format: sortable
          $<$<AND:$<NOT:$<PLATFORM_ID:Windows,Darwin>>,$<BOOL:${ENABLE_WAYLAND}>>:gl-wayland-egl.c>
          $<$<NOT:$<PLATFORM_ID:Windows,Darwin>>:gl-egl-common.c>
          $<$<NOT:$<PLATFORM_ID:Windows,Darwin>>:gl-nix.c>
          $<$<NOT:$<PLATFORM_ID:Windows,Darwin>>:gl-x11-egl.c>
          $<$<PLATFORM_ID:Darwin>:gl-cocoa.m>
          $<$<PLATFORM_ID:Windows>:gl-windows.c>
          gl-helpers.c
          gl-helpers.h
          gl-indexbuffer.c
          gl-shader.c
          gl-shaderparser.c
          gl-shaderparser.h
          gl-stagesurf.c
          gl-subsystem.c
          gl-subsystem.h
          gl-texture2d.c
          gl-texture3d.c
          gl-texturecube.c
          gl-vertexbuffer.c
          gl-zstencil.c)

target_compile_options(libobs-opengl PRIVATE $<$<C_COMPILER_ID:AppleClang,Clang>:-Wno-strict-prototypes>)

target_compile_definitions(libobs-opengl PRIVATE $<$<PLATFORM_ID:Darwin>:GL_SILENCE_DEPRECATION>)

target_link_libraries(
  libobs-opengl
  PRIVATE OBS::libobs
          OBS::glad
          "$<$<PLATFORM_ID:Darwin>:$<LINK_LIBRARY:FRAMEWORK,Cocoa.framework>>"
          "$<$<PLATFORM_ID:Darwin>:$<LINK_LIBRARY:FRAMEWORK,IOSurface.framework>>"
          $<$<NOT:$<PLATFORM_ID:Windows,Darwin>>:xcb::xcb>
          $<$<NOT:$<PLATFORM_ID:Windows,Darwin>>:X11::x11-xcb>
          $<$<AND:$<NOT:$<PLATFORM_ID:Windows,Darwin>>,$<BOOL:${ENABLE_WAYLAND}>>:OpenGL::EGL>
          $<$<AND:$<NOT:$<PLATFORM_ID:Windows,Darwin>>,$<BOOL:${ENABLE_WAYLAND}>>:Wayland::EGL>)

if(OS_WINDOWS)
  configure_file(cmake/windows/obs-module.rc.in libobs-opengl.rc)
  target_sources(libobs-opengl PRIVATE libobs-opengl.rc)
elseif(NOT OS_MACOS)
  find_package(X11 REQUIRED)
  # cmake-format: off
  find_package(xcb REQUIRED xcb)
  # cmake-format: on
  find_package(x11-xcb REQUIRED)

  if(ENABLE_WAYLAND)
    find_package(OpenGL REQUIRED EGL)
    find_package(Wayland REQUIRED)
  endif()
endif()

target_enable_feature(libobs "OpenGL renderer")

# cmake-format: off
set_target_properties_obs(
  libobs-opengl
  PROPERTIES FOLDER core
             VERSION 0
             PREFIX ""
             SOVERSION "${OBS_VERSION_MAJOR}")
# cmake-format: on
