option(ENABLE_SPARKLE "Enable building with Sparkle Updater" OFF)

if(ENABLE_SPARKLE)
  find_library(SPARKLE Sparkle)
  mark_as_advanced(SPARKLE)

  target_sources(obs-studio PRIVATE sparkle-updater.mm)
  target_link_libraries(obs-studio PRIVATE ${SPARKLE})

  target_enable_feature(obs-studio "Sparkle updater" ENABLE_SPARKLE_UPDATER)
else()
  target_disable_feature(obs-studio "Sparkle updater")
endif()
