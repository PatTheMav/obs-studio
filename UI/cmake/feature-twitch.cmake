if(NOT OAUTH_BASE_URL)
  set(OAUTH_BASE_URL
      "https://auth.obsproject.com/"
      CACHE STRING "Default OAuth base URL")

  mark_as_advanced(OAUTH_BASE_URL)
endif()

if(TWITCH_CLIENTID
   AND TWITCH_HASH
   AND TARGET OBS::browser-panels)
  target_sources(obs-studio PRIVATE auth-twitch.cpp auth-twitch.hpp)
  target_enable_feature(obs-studio "Twitch API connection" TWITCH_ENABLED)
else()
  target_disable_feature(obs-studio "Twitch API connection")
  set(TWITCH_CLIENTID "")
  set(TWITCH_HASH "0")
endif()
