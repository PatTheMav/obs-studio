if(OS_WINDOWS)
  add_library(obs-obfuscate INTERFACE EXCLUDE_FROM_ALL)
  add_library(OBS::obfuscate ALIAS obs-obfuscate)
  target_sources(obs-obfuscate INTERFACE util/windows/obfuscate.c
                                         util/windows/obfuscate.h)
  target_include_directories(obs-obfuscate
                             INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")

  add_library(obs-comutils INTERFACE EXCLUDE_FROM_ALL)
  add_library(OBS::COMutils ALIAS obs-comutils)
  target_sources(obs-comutils INTERFACE util/windows/ComPtr.hpp)
  target_include_directories(obs-comutils
                             INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")

  add_library(obs-winhandle INTERFACE EXCLUDE_FROM_ALL)
  add_library(OBS::winhandle ALIAS obs-winhandle)
  target_sources(obs-winhandle INTERFACE util/windows/WinHandle.hpp)
  target_include_directories(obs-winhandle
                             INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")
endif()
