cmake_minimum_required(VERSION 3.22...3.27)

legacy_check()

option(ENABLE_FREETYPE "Enable FreeType text plugin" ON)

if(NOT ENABLE_FREETYPE)
  target_disable(text-freetype2)
  return()
endif()

find_package(Freetype REQUIRED)

if(OS_MACOS)
  find_package(Iconv REQUIRED)
elseif(NOT OS_WINDOWS)
  find_package(Fontconfig REQUIRED)
endif()

add_library(text-freetype2 MODULE)
add_library(OBS::text-freetype2 ALIAS text-freetype2)

target_sources(
  text-freetype2
  PRIVATE # cmake-format: sortable
          $<$<NOT:$<PLATFORM_ID:Windows,Darwin>>:find-font-unix.c>
          $<$<PLATFORM_ID:Darwin>:find-font-cocoa.m>
          $<$<PLATFORM_ID:Darwin>:find-font-iconv.c>
          $<$<PLATFORM_ID:Darwin>:find-font.c>
          $<$<PLATFORM_ID:Windows>:find-font-windows.c>
          $<$<PLATFORM_ID:Windows>:find-font.c>
          find-font.h
          obs-convenience.c
          obs-convenience.h
          text-freetype2.c
          text-freetype2.h
          text-functionality.c)

# cmake-format: off
target_link_libraries(
  text-freetype2
  PRIVATE OBS::libobs
          Freetype::Freetype
          $<$<PLATFORM_ID:Darwin>:Iconv::Iconv>
          "$<$<PLATFORM_ID:Darwin>:$<LINK_LIBRARY:FRAMEWORK,Cocoa.framework>>"
          $<$<NOT:$<PLATFORM_ID:Windows,Darwin>>:Fontconfig::Fontconfig>)
# cmake-format: on

target_link_options(text-freetype2 PRIVATE $<$<PLATFORM_ID:Windows_DISABLED>:/IGNORE:4098>
                    $<$<PLATFORM_ID:Windows_DISABLED>:/IGNORE:4099>)

if(OS_WINDOWS)
  configure_file(cmake/windows/obs-module.rc.in text-freetype2.rc)
  target_sources(text-freetype2 PRIVATE text-freetype2.rc)
endif()

# cmake-format: off
set_target_properties_obs(text-freetype2 PROPERTIES FOLDER plugins PREFIX "")
# cmake-format: on
