if(NOT OAUTH_BASE_URL)
  set(OAUTH_BASE_URL
      "https://auth.obsproject.com/"
      CACHE STRING "Default OAuth base URL")

  mark_as_advanced(OAUTH_BASE_URL)
endif()

if(YOUTUBE_CLIENTID
   AND YOUTUBE_SECRET
   AND YOUTUBE_CLIENTID_HASH
   AND YOUTUBE_SECRET_HASH
   AND TARGET OBS::browser-panels)
  target_sources(
    obs-studio
    PRIVATE auth-youtube.cpp auth-youtube.hpp youtube-api-wrappers.cpp
            youtube-api-wrappers.hpp window-youtube-actions.cpp
            window-youtube-actions.hpp)

  target_enable_feature(obs-studio "YouTube API connection" YOUTUBE_ENABLED)
else()
  target_disable_feature(obs-studio "YouTube API connection")
  set(YOUTUBE_SECRET_HASH 0)
  set(YOUTUBE_CLIENTID_HASH 0)
endif()
