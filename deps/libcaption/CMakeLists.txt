cmake_minimum_required(VERSION 3.22...3.27)

add_library(caption OBJECT)
add_library(OBS::caption ALIAS caption)

target_sources(
  caption
  PRIVATE # cmake-format: sortable
          caption/cea708.h
          caption/eia608.h
          caption/eia608_charmap.h
          caption/mpeg.h
          caption/scc.h
          caption/utf8.h
          src/caption.c
          src/cea708.c
          src/eia608.c
          src/eia608_charmap.c
          src/eia608_from_utf8.c
          src/mpeg.c
          src/scc.c
          src/srt.c
          src/utf8.c
          src/vtt.c
          src/xds.c
  PUBLIC caption/caption.h)

target_include_directories(
  caption
  PRIVATE caption
  PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")

target_compile_definitions(caption PRIVATE __STDC_CONSTANT_MACROS $<$<PLATFORM_ID:Windows>:_CRT_SECURE_NO_WARNINGS>)

target_compile_options(
  caption
  PRIVATE $<$<PLATFORM_ID:Windows>:/wd4267> $<$<CXX_COMPILER_ID:Clang,AppleClang,GNU>:-Wno-unused-but-set-parameter>
          $<$<CXX_COMPILER_ID:Clang,AppleClang,GNU>:-Wno-strict-prototypes>
          $<$<CXX_COMPILER_ID:Clang,AppleClang>:-Wno-comma>)

set_target_properties(caption PROPERTIES FOLDER deps POSITION_INDEPENDENT_CODE TRUE)
