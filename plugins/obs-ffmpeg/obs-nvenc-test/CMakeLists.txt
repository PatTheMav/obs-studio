cmake_minimum_required(VERSION 3.22...3.25)

legacy_check()

add_executable(obs-nvenc-test)
add_executable(OBS::nvenc-test ALIAS obs-nvenc-test)

target_sources(obs-nvenc-test PRIVATE jim-nvenc-test.c)
target_link_libraries(obs-nvenc-test PRIVATE OBS::nvenc-headers d3d11 dxgi dxguid)

# cmake-format: off
set_target_properties_obs(obs-nvenc-test PROPERTIES FOLDER plugins/obs-ffmpeg)
# cmake-format: on
