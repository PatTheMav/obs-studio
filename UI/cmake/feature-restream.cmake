if(NOT OAUTH_BASE_URL)
  set(OAUTH_BASE_URL
      "https://auth.obsproject.com/"
      CACHE STRING "Default OAuth base URL")

  mark_as_advanced(OAUTH_BASE_URL)
endif()

if(RESTREAM_CLIENTID
   AND RESTREAM_HASH
   AND TARGET OBS::browser-panels)
  target_sources(obs-studio PRIVATE auth-restream.cpp auth-restream.hpp)
  target_enable_feature(obs-studio "Restream API connection" RESTREAM_ENABLED)
else()
  target_disable_feature(obs-studio "Restream API connection")
  set(RESTREAM_CLIENTID "")
  set(RESTREAM_HASH "0")
endif()
