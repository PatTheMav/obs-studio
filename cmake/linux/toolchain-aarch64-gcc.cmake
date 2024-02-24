set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm64)

if(CROSS STREQUAL "")
  set(CROSS aarch64-linux-gnu-)
endif()

if(NOT CMAKE_C_COMPILER)
  set(CMAKE_C_COMPILER ${CROSS}gcc)
endif()
set(CMAKE_C_FLAGS_INIT -march=armv8-a)

if(NOT CMAKE_CXX_COMPILER)
  set(CMAKE_CXX_COMPILER ${CROSS}g++)
endif()
set(CMAKE_CXX_FLAGS_INIT -march-armv8-a)

if(NOT CMAKE_ASM_COMPILER)
  set(CMAKE_ASM_COMPILER ${CROSS}as)
endif()
