add_custom_command(
  TARGET obs-virtualcam
  POST_BUILD
  COMMAND "${CMAKE_COMMAND}" --build ${CMAKE_SOURCE_DIR}/build_x86 --config $<CONFIG> -t obs-virtualcam
  COMMENT "Build 32bit obs-virtualcam")
