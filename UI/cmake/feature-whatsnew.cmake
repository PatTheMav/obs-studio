option(ENABLE_WHATSNEW "Enable WhatsNew dialog" ON)

if(NOT TARGET OBS::blake2)
  add_subdirectory("${CMAKE_SOURCE_DIR}/deps/blake2"
                   "${CMAKE_BINARY_DIR}/deps/blake2")
endif()

if(ENABLE_WHATSNEW AND TARGET OBS::browser-panels)
  if(OS_MACOS)

    find_library(SECURITY Security)
    mark_as_advanced(SECURITY)

    target_sources(
      obs-studio
      PRIVATE nix-update/crypto-helpers.hpp
              nix-update/crypto-helpers-mac.mm
              nix-update/nix-update.cpp
              nix-update/nix-update.hpp
              nix-update/nix-update-helpers.cpp
              nix-update/nix-update-helpers.hpp)

    target_link_libraries(obs-studio PRIVATE ${SECURITY} OBS::blake2)
  elseif(OS_LINUX)
    find_package(MbedTLS REQUIRED)
    target_link_libraries(obs-studio PRIVATE MbedTLS::MbedTLS OBS::blake2)

    target_sources(
      obs-studio
      PRIVATE nix-update/crypto-helpers.hpp
              nix-update/crypto-helpers-mbedtls.cpp
              nix-update/nix-update.cpp
              nix-update/nix-update.hpp
              nix-update/nix-update-helpers.cpp
              nix-update/nix-update-helpers.hpp)
  endif()

  target_enable_feature(obs-studio "What's New panel" WHATSNEW_ENABLED)
endif()
