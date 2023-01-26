# OBS CMake build number module

# Define build number cache file
set(_BUILD_NUMBER_CACHE
    "${CMAKE_SOURCE_DIR}/cmake/.CMakeBuildNumber"
    CACHE INTERNAL "OBS build number cache file")

# Read build number from cache file or manual override
if(NOT DEFINED OBS_BUILD_NUMBER AND EXISTS "${_BUILD_NUMBER_CACHE}")
  file(READ "${_BUILD_NUMBER_CACHE}" OBS_BUILD_NUMBER)
  math(EXPR OBS_BUILD_NUMBER "${OBS_BUILD_NUMBER}+1")
elseif(NOT DEFINED OBS_BUILD_NUMBER)
  set(OBS_BUILD_NUMBER "1")
endif()
file(WRITE "${_BUILD_NUMBER_CACHE}" "${OBS_BUILD_NUMBER}")