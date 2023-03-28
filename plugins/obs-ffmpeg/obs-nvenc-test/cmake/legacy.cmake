project(obs-nvenc-test)

add_executable(obs-nvenc-test)
target_sources(obs-nvenc-test PRIVATE jim-nvenc-test.c ../jim-nvenc-ver.h)
target_link_libraries(obs-nvenc-test d3d11 dxgi dxguid)
target_include_directories(obs-nvenc-test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/.."
                                                  "${CMAKE_CURRENT_SOURCE_DIR}/../external")
target_compile_definitions(obs-nvenc-test PRIVATE OBS_LEGACY)

set_target_properties(obs-nvenc-test PROPERTIES FOLDER "plugins/obs-ffmpeg")

setup_binary_target(obs-nvenc-test)
