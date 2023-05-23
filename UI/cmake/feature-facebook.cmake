if(FACEBOOK_CLIENTID
   AND FACEBOOK_SECRET
   AND FACEBOOK_CLIENTID_HASH GREATER_EQUAL 0
   AND FACEBOOK_SECRET_HASH GREATER_EQUAL 0)
  target_sources(
    obs-studio
    PRIVATE auth-facebook.cpp
            auth-facebook.hpp
            window-facebook-actions.cpp
            window-facebook-actions.hpp
            facebook-api-objects.hpp
            facebook-api-wrappers.cpp
            facebook-api-wrappers.hpp)

  target_enable_feature(obs-studio "YouTube API connection" FACEBOOK_ENABLED)
else()
  target_disable_feature(obs-studio "YouTube API connection")
  set(FACEBOOK_SECRET_HASH 0)
  set(FACEBOOK_CLIENTID_HASH 0)
endif()
