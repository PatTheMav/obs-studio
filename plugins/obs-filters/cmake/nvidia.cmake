if(OS_WINDOWS)
  option(ENABLE_NVAFX
         "Enable building with NVIDIA Audio Effects SDK (requires redistributable to be installed)"
         ON)
  option(ENABLE_NVVFX
         "Enable building with NVIDIA Video Effects SDK (requires redistributable to be installed)"
         ON)
endif()

if(ENABLE_NVAFX)
  target_enable_feature(obs-filters "NVIDIA Audio FX support" LIBNVAFX_ENABLED HAS_NOISEREDUCTION)
else()
  target_disable_feature(obs-filters "NVIDIA Audio FX support")
endif()

if(ENABLE_NVVFX)
  target_enable_feature(obs-filters "NVIDIA Video FX support" LIBNVVFX_ENABLED)
  target_sources(obs-filters PRIVATE nvidia-greenscreen-filter.c)
else()
  target_disable_feature(obs-filters "NVIDIA Video FX support")
endif()
