cmake_minimum_required(VERSION 3.24...3.25)

add_library(mac-virtualcam MODULE)
add_library(OBS::virtualcam ALIAS mac-virtualcam)

target_sources(mac-virtualcam PRIVATE Defines.h plugin-main.mm OBSDALMachServer.mm OBSDALMachServer.h)

if(NOT XCODE)
  target_compile_options(mac-virtualcam PRIVATE -fobjc-arc -fobjc-weak)
endif()

# cmake-format: off
target_link_libraries(
  mac-virtualcam
  PRIVATE OBS::mach-protocol
          OBS::libobs
          OBS::frontend-api
          "$<LINK_LIBRARY:FRAMEWORK,AppKit.framework>"
          "$<LINK_LIBRARY:FRAMEWORK,CoreVideo.framework>"
          "$<LINK_LIBRARY:FRAMEWORK,IOSurface.framework>")

set_target_properties_obs(
  mac-virtualcam
  PROPERTIES FOLDER plugins
             PREFIX ""
             LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/../../"
             XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
             XCODE_ATTRIBUTE_CLANG_WARN_SUSPICIOUS_IMPLICIT_CONVERSION YES
             XCODE_ATTRIBUTE_GCC_WARN_SHADOW YES)
# cmake-format: on
