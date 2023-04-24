cmake_minimum_required(VERSION 3.22...3.25)

legacy_check()

find_library(COCOA Cocoa)
find_library(COREMEDIA CoreMedia)
find_library(COREMEDIAIO CoreMediaIO)
find_library(COREVIDEO CoreVideo)
find_library(IOSURFACE IOSurface)
mark_as_advanced(COCOA COREMEDIA COREMEDIAIO COREVIDEO IOSURFACE)

add_library(obs-dal-plugin MODULE)
add_library(OBS::dal-plugin ALIAS obs-dal-plugin)

target_sources(
  obs-dal-plugin
  PRIVATE OBSDALPlugIn.mm
          OBSDALPlugIn.h
          OBSDALPlugInMain.mm
          OBSDALPlugInInterface.mm
          OBSDALPlugInInterface.h
          OBSDALObjectStore.mm
          OBSDALObjectStore.h
          OBSDALDevice.mm
          OBSDALDevice.h
          OBSDALMachClient.mm
          OBSDALMachClient.h
          CMSampleBufferUtils.mm
          OBSDALStream.mm
          OBSDALStream.h
          CMSampleBufferUtils.h
          Defines.h
          Logging.h)

if(NOT XCODE)
  target_compile_options(obs-dal-plugin PRIVATE -fobjc-arc -fobjc-weak)
endif()

set(_placeholder_location "${CMAKE_CURRENT_SOURCE_DIR}/../common/data/placeholder.png")

set_property(SOURCE "${_placeholder_location}" PROPERTY MACOSX_PACKAGE_LOCATION "Resources")
source_group("Resources" FILES "${_placeholder_location}")

target_link_libraries(obs-dal-plugin PRIVATE OBS::mach-protocol ${COCOA} ${COREMEDIA} ${COREMEDIAIO} ${COREVIDEO}
                                             ${IOSURFACE})

set_target_properties_obs(
  obs-dal-plugin
  PROPERTIES OUTPUT_NAME obs-mac-virtualcam
             FOLDER plugins
             PREFIX "")

string(TIMESTAMP CURRENT_YEAR "%Y")
set_target_properties(
  obs-dal-plugin
  PROPERTIES BUNDLE TRUE
             BUNDLE_EXTENSION plugin
             MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/cmake/macos/Info.plist"
             OSX_ARCHITECTURES "x86_64;arm64;arm64e"
             LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/../../"
             XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
             XCODE_ATTRIBUTE_CLANG_WARN_SUSPICIOUS_IMPLICIT_CONVERSION YES
             XCODE_ATTRIBUTE_GCC_WARN_SHADOW YES
             XCODE_ATTRIBUTE_PRODUCT_NAME obs-mac-virtualcam
             XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER com.obsproject.obs-mac-virtualcam
             XCODE_ATTRIBUTE_CURRENT_PROJECT_VERSION ${OBS_BUILD_NUMBER}
             XCODE_ATTRIBUTE_MARKETING_VERSION ${OBS_VERSION_CANONICAL}
             XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE YES
             XCODE_ATTRIBUTE_INFOPLIST_KEY_CFBundleDisplayName obs-mac-virtualcam
             XCODE_ATTRIBUTE_INFOPLIST_KEY_NSHumanReadableCopyright "(c) 2012-${CURRENT_YEAR} Hugh Bailey")
