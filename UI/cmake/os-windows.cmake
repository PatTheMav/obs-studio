if(NOT TARGET OBS::blake2)
  add_subdirectory("${CMAKE_SOURCE_DIR}/deps/blake2"
                   "${CMAKE_BINARY_DIR}/deps/blake2")
endif()

if(NOT TARGET OBS::w32-pthreads)
  add_subdirectory("${CMAKE_SOURCE_DIR}/deps/w32-pthreads"
                   "${CMAKE_BINARY_DIR}/deps/w32-pthreads")
endif()

configure_file(cmake/windows/obs.rc.in obs.rc)

target_sources(
  obs-studio
  PRIVATE cmake/windows/obs.manifest
          platform-windows.cpp
          obs.rc
          win-update/update-window.cpp
          win-update/update-window.hpp
          win-update/win-update.cpp
          win-update/win-update.hpp
          win-update/win-update-helpers.cpp
          win-update/win-update-helpers.hpp)

target_link_libraries(obs-studio PRIVATE crypt32 OBS::blake2 OBS::w32-pthreads)
target_link_options(obs-studio PRIVATE /IGNORE:4098 /IGNORE:4099)

add_library(obs-update-helpers INTERFACE EXCLUDE_FROM_ALL)
add_library(OBS::update-helpers ALIAS obs-update-helpers)

target_sources(obs-update-helpers INTERFACE win-update/win-update-helpers.cpp
                                            win-update/win-update-helpers.hpp)
target_include_directories(obs-update-helpers
                           INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/win-update")

add_subdirectory(win-update/updater)

set_property(DIRECTORY ${CMAKE_SOURCE_DIR} PROPERTY VS_STARTUP_PROJECT
                                                    obs-studio)
set_target_properties(
  obs-studio
  PROPERTIES
    WIN32_EXECUTABLE TRUE
    VS_DEBUGGER_COMMAND
    "${CMAKE_BINARY_DIR}/rundir/$<CONFIG>/$<$<BOOL:${OBS_WINDOWS_LEGACY_DIRS}>:bin/>obs.exe"
    VS_DEBUGGER_WORKING_DIRECTORY
    "${CMAKE_BINARY_DIR}/rundir/$<CONFIG>$<$<BOOL:${OBS_WINDOWS_LEGACY_DIRS}>:/bin>"
)
