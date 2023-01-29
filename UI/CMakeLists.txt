cmake_minimum_required(VERSION 3.22...3.25)

legacy_check()

add_subdirectory(obs-frontend-api)

option(ENABLE_UI "Enable building with UI (requires Qt)" ON)

if(NOT ENABLE_UI)
  target_disable_feature(obs "User interface")
  return()
else()
  target_enable_feature(obs "User interface")
endif()

find_package(FFmpeg REQUIRED COMPONENTS avcodec avutil avformat)
find_package(CURL REQUIRED)

if(NOT TARGET OBS::libff-util)
  add_subdirectory("${CMAKE_SOURCE_DIR}/deps/libff"
                   "${CMAKE_BINARY_DIR}/deps/libff")
endif()

if(NOT TARGET OBS::json11)
  add_subdirectory("${CMAKE_SOURCE_DIR}/deps/json11"
                   "${CMAKE_BINARY_DIR}/deps/json11")
endif()

add_executable(obs-studio)
add_executable(OBS::studio ALIAS obs-studio)

target_link_libraries(
  obs-studio
  PRIVATE CURL::libcurl
          FFmpeg::avcodec
          FFmpeg::avutil
          FFmpeg::avformat
          OBS::libobs
          OBS::frontend-api
          OBS::libff-util
          OBS::json11)

target_compile_features(obs-studio PRIVATE cxx_std_17)

include(cmake/ui-qt.cmake)
include(cmake/ui-elements.cmake)
include(cmake/ui-windows.cmake)
include(cmake/feature-importers.cmake)
include(cmake/feature-browserpanels.cmake)
include(cmake/feature-twitch.cmake)
include(cmake/feature-restream.cmake)
include(cmake/feature-youtube.cmake)
include(cmake/feature-whatsnew.cmake)

add_subdirectory(frontend-plugins)

configure_file(ui-config.h.in ui-config.h)

target_sources(
  obs-studio
  PRIVATE auth-oauth.cpp
          auth-oauth.hpp
          auth-listener.cpp
          auth-listener.hpp
          obf.c
          obf.h
          obs-app.cpp
          obs-app.hpp
          obs-proxy-style.cpp
          obs-proxy-style.hpp
          api-interface.cpp
          auth-base.cpp
          auth-base.hpp
          crash-report.cpp
          crash-report.hpp
          display-helpers.hpp
          platform.hpp
          qt-display.cpp
          qt-display.hpp
          qt-wrappers.cpp
          qt-wrappers.hpp
          ui-validation.cpp
          ui-validation.hpp
          multiview.cpp
          multiview.hpp
          ui-config.h)

if(OS_WINDOWS)
  include(cmake/os-windows.cmake)
elseif(OS_MACOS)
  include(cmake/os-macos.cmake)
elseif(OS_LINUX)
  include(cmake/os-linux.cmake)
elseif(OS_FREEBSD)
  include(cmake/os-freebsd.cmake)
endif()

foreach(graphics_library IN ITEMS opengl metal d3d11)
  string(TOUPPER ${graphics_library} graphics_library_U)
  if(TARGET OBS::libobs-${graphics_library})
    target_compile_definitions(
      obs-studio
      PRIVATE
        DL_${graphics_library_U}="$<TARGET_FILE_NAME:OBS::libobs-${graphics_library}>"
    )
  else()
    target_compile_definitions(obs-studio PRIVATE DL_${graphics_library_U}="")
  endif()
endforeach()

set_target_properties_obs(obs-studio PROPERTIES FOLDER frontend OUTPUT_NAME obs)
