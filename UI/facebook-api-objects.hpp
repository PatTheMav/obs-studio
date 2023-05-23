#pragma once

#include <QString>
#include <vector>

#define _DEBUG 1

/* ------------------------------------------------------------------------- */
#define FACEBOOK_BASE_URL "https://www.facebook.com"
#define FACEBOOK_DASHBOARD_URL FACEBOOK_BASE_URL "/live/producer?ref=OBS"
#define FACEBOOK_API_VERSION "/v12.0"

#define FACEBOOK_LOGIN_URL \
	FACEBOOK_BASE_URL  \
	FACEBOOK_API_VERSION "/dialog/oauth"

#define FACEBOOK_BASE_API "https://graph.facebook.com"
#define FACEBOOK_API_URL FACEBOOK_BASE_API FACEBOOK_API_VERSION

#define FACEBOOK_TOKEN_URL FACEBOOK_API_URL "/oauth/access_token"

#define FACEBOOK_USER_URL FACEBOOK_API_URL "/me"
#define FACEBOOK_USER_PERMISSIONS FACEBOOK_USER_URL "/permissions"
#define FACEBOOK_USER_LIVE_VIDEOS FACEBOOK_API_URL "/%1/live_videos"

#define FACEBOOK_PERMISSION_PUBLISH_VIDEO "publish_video"

#define FACEBOOK_SCOPE_VERSION 1
#define FACEBOOK_API_STATE_LENGTH 32

#define FACEBOOK_SECTION_NAME "Facebook Live"
#define FACEBOOK_USER_ID "UserId"
#define FACEBOOK_USER_NAME "UserName"

#define FACEBOOK_POPUP_BASE FACEBOOK_BASE_URL "/live/producer/dashboard"
#define FACEBOOK_COMMENTS_POPUP_URL FACEBOOK_POPUP_BASE "/%1/COMMENTS"
#define FACEBOOK_COMMENTS_PLACEHOLDER_URL \
	"https://obsproject.com/placeholders/youtube-chat"
#define FACEBOOK_HEALTH_POPUP_URL FACEBOOK_POPUP_BASE "/%1/STREAM_HEALTH"
#define FACEBOOK_HEALTH_PLACEHOLDER_URL \
	"https://obsproject.com/placeholders/youtube-chat"
#define FACEBOOK_STATS_POPUP_URL FACEBOOK_POPUP_BASE "/%1/STREAM_STATS"
#define FACEBOOK_STATS_PLACEHOLDER_URL \
	"https://obsproject.com/placeholders/youtube-chat"
#define FACEBOOK_ALERTS_POPUP_URL FACEBOOK_POPUP_BASE "/%1/ALERTS"
#define FACEBOOK_ALERTS_PLACEHOLDER_URL \
	"https://obsproject.com/placeholders/youtube-chat"

static const char allowedChars[] =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
static const int allowedCount = static_cast<int>(sizeof(allowedChars) - 1);
/* ------------------------------------------------------------------------- */

/* Device Login */
struct DeviceLogin {
	QString code;
	QString user_code;
	QString verification_uri;
	uint16_t expires_in;
	uint8_t interval;
};

struct LoginStatus {
	QString access_token;
	uint32_t expires_in;
	uint32_t error;
};

/* User info
https://developers.facebook.com/docs/graph-api/reference/user/
*/
struct User {
	QString id;
	QString name;
};

/* Video Copyright info
https://developers.facebook.com/docs/graph-api/reference/video-copyright/
*/
struct LiveVideoAdBreakConfig {
	uint16_t default_ad_break_duration;
	uint16_t failure_reason_polling_interval;
	uint16_t first_break_eligible_secs;
	QString guide_url;
	bool is_eligible_to_onboard;
	bool is_enabled;
	QString onboarding_url;
	uint16_t preparing_duration;
	uint16_t time_between_ad_breaks_secs;
	uint16_t viewer_count_threshold;
};

/* Content Category info */
enum ContentCategory {
	EPISODE, // "episode"
	MOVIE,   // "movie"
	WEB      // "web"
};

enum MonitoringStatus {
	NOT_EXAMINED, // "NOT_EXAMINED"
	COPYRIGHTED,  // "COPYRIGHTED"
	ERROR         // "ERROR"
};

enum MonitoringType {
	VIDEO,          // "VIDEO_ONLY"
	AUDIO,          // "AUDIO_ONLY"
	VIDEO_AND_AUDIO // "VIDEO_AND_AUDIO"
};

struct VideoCopyrightSegment {
	uint16_t duration_in_sec;
	QString media_type;
	uint16_t start_time_in_sec;
};

struct VideoCopyrightGeoGate {
	QString included_countries;
	QString excluded_countries;
};

struct CopyrightReferenceContainer {
};

struct VideoCopyrightConditionGroup {
	QString action;
	std::vector<QString> conditions;
	QString validity_status;
};

/* Video Copyright Rule info
https://developers.facebook.com/docs/graph-api/reference/video-copyright-rule/
*/
struct VideoCopyrightRule {
	QString id;
	std::vector<VideoCopyrightConditionGroup> condition_groups;
	std::vector<QString> copyrights;
	time_t created_date;
	User creator;
	bool is_in_migration;
	QString name;
};

struct VideoCopyright {
	QString id;
	ContentCategory content_category;
	QString copyright_content_id;
	User creator;
	std::vector<VideoCopyrightSegment> excluded_ownership_segments;
	bool in_conflict;
	MonitoringStatus monitoring_status;
	MonitoringType monitoring_type;
	VideoCopyrightGeoGate ownership_countries;
	CopyrightReferenceContainer reference_file;
	bool reference_file_disabled;
	bool reference_file_disabled_by_ops;
	QString reference_owner_id;
	std::vector<VideoCopyrightRule> rule_ids;
	std::vector<QString> tags;
	std::vector<QString> whitelisted_ids;
};

/* Live Video Stream Health info
Docs MISSING
*/
struct LiveVideoStreamHealth {
	uint32_t video_bitrate;
	uint16_t video_framerate;
	uint16_t video_gop_size;
	uint16_t video_height;
	uint16_t video_width;
	float_t audio_bitrate;
};

/* Live Video Input Stream info
https://developers.facebook.com/docs/graph-api/reference/live-video-input-stream/
*/
struct LiveVideoInputStream {
	QString id;
	QString dash_ingest_url;
	QString dash_preview_url;
	bool is_master;
	QString secure_stream_url;
	LiveVideoStreamHealth stream_health;
	QString stream_id;
	QString stream_url;
};

enum FBEventCategory {
	ART_EVENT,        // ART_EVENT
	BOOK_EVENT,       // BOOK_EVENT
	MOVIE_EVENT,      // MOVIE_EVENT
	FUNDRAISER,       // FUNDRAISER
	VOLUNTEERING,     // VOLUNTEERING
	FAMILY_EVENT,     // FAMILY_EVENT
	FESTIVAL_EVENT,   // FESTIVAL_EVENT
	NEIGHBORHOOD,     // NEIGHBORHOOD
	RELIGIOUS_EVENT,  // RELIGIOUS_EVENT
	SHOPPING,         // SHOPPING
	COMEDY_EVENT,     // COMEDY_EVENT
	MUSIC_EVENT,      // MUSIC_EVENT
	DANCE_EVENT,      // DANCE_EVENT
	NIGHTLIFE,        // NIGHTLIFE
	THEATER_EVENT,    // THEATER_EVENT
	DINING_EVENT,     // DINING_EVENT
	FOOD_TASTING,     // FOOD_TASTING
	CONFERENCE_EVENT, // CONFERENCE_EVENT
	MEETUP,           // MEETUP
	CLASS_EVENT,      // CLASS_EVENT
	LECTURE,          // LECTURE
	WORKSHOP,         // WORKSHOP
	FITNESS,          // FITNESS
	SPORTS_EVENT,     // SPORTS_EVENT
	OTHER_EVENT       // OTHER
};

/* Photo info
https://developers.facebook.com/docs/graph-api/reference/photo
*/
struct Photo {
	// POPULATE LATER
};

/* Cover Photo info
https://developers.facebook.com/docs/graph-api/reference/cover-photo/
*/
struct CoverPhoto {
	QString id;
	float_t offset_x;
	float_t offset_y;
	QString source;
};

struct ChildEvent {
	QString id;
	QString end_time;
	QString start_time;
	QString ticket_uri;
};

enum OnlineEventFormat {
	FB_LIVE,        // "fb_live"
	MESSENGER_ROOM, // "messenger_room"
	NONE,           // "none"
	OTHER,          // "other"
	THIRD_PARTY,    // "third_party"
};

enum GroupPrivacy {
	OPEN,   // OPEN (needs confirmation)
	CLOSED, // CLOSED (needs confirmation)
	SECRET  // SECRET (needs confirmation)
};

/* Group Info
https://developers.facebook.com/docs/graph-api/reference/v12.0/group
*/
struct Group {
	QString id;
	CoverPhoto cover;
	QString description;
	QString email;
	QString icon;
	uint32_t member_count;
	uint32_t member_request_count;
	QString parent;
	QString permissions;
	GroupPrivacy privacy;
	time_t updated_time;
};

/* Location info
https://developers.facebook.com/docs/graph-api/reference/location/
*/
struct Location {
	QString city;
	QString city_id;
	QString country;
	QString country_code;
	QString located_in;
	float_t latitude;
	float_t longitude;
	QString name;
	QString region;
	QString region_id;
	QString state;
	QString street;
	QString zip;
};

struct LocationGroup {
	QString id;
	Location location;
};

/* Place info
https://developers.facebook.com/docs/graph-api/reference/place/
*/
struct Place {
	QString id;
	Location location;
	QString name;
	float_t overall_rating;
};

/* Event Type info */
enum EventType {
	COMMUNITY,   // "community"
	FRIENDS,     // "friends"
	GROUP,       // "group"
	PRIVATE,     // "private"
	PUBLIC,      // "public"
	WORK_COMPANY // "work_company"
};

/* Event info
https://developers.facebook.com/docs/graph-api/reference/event/
*/
struct Event {
	QString id;
	uint32_t attending_count;
	bool can_guests_invite;
	FBEventCategory category;
	CoverPhoto cover;
	time_t created_time;
	uint32_t declined_count;
	QString description;
	bool discount_code_enabled;
	QString end_time;
	std::vector<ChildEvent> event_times;
	bool guest_list_enabled;
	uint32_t interested_count;
	bool is_canceled;
	bool is_draft;
	bool is_online;
	bool is_page_owned;
	uint32_t maybe_count;
	QString name;
	uint32_t noreply_count;
	OnlineEventFormat online_event_format;
	QString online_event_third_party_url;
	User owner; // Could be a Group or Page? Update to a Union?
	Group parent_group;
	Place place;
	QString scheduled_publish_time;
	QString start_time;
	QString ticket_uri;
	QString ticket_uri_start_sales_time;
	QString ticketing_privacy_uri;
	QString ticketing_terms_uri;
	QString timezone;
	EventType type;
	time_t updated_time;
};

/* Video Format info
https://developers.facebook.com/docs/graph-api/reference/video-format/
*/
struct VideoFormat {
	QString embed_html;
	QString filter;
	uint32_t height;
	QString picture;
	uint32_t width;
};

/* Privacy info
https://developers.facebook.com/docs/graph-api/reference/privacy/
*/
struct Privacy {
	QString allow;
	QString deny;
	QString description;
	QString friends; // This must be an ENUM but couldn't find
	QString networks;
	QString value; // This must be an ENUM but couldn't find
};

/* Backdated Time Granularity info */
enum BackdatedTimeGranularity {
	MIN,   // "min"
	HOUR,  // "hour"
	DAY,   // "day"
	MONTH, // "month"
	YEAR,  // "year"
	NONE_T // "none"
};

/* Video Status info */
enum VideoStatus {
	LIVE_NOW,              // "LIVE_NOW"
	SCHEDULED_CANCELED,    // "SCHEDULED_CANCELED"
	SCHEDULED_LIVE,        // "SCHEDULED_LIVE"
	SCHEDULED_UNPUBLISHED, // "SCHEDULED_UNPUBLISHED"
	UNPUBLISHED            // "UNPUBLISHED"
};

/* Music Video Copyright info
DOCS MISSING
*/
struct MusicVideoCopyright {
	QString id;
	uint32_t displayed_matches_count;
	QString creation_time;
	bool in_conflict;
	QString isrc;
	VideoCopyrightRule match_rule;
	std::vector<QString> ownership_countries;
	QString reference_file_status;
	QString ridge_monitoring_status;
	std::vector<QString> tags;
	QString update_time;
	CopyrightReferenceContainer video_asset;
	std::vector<QString> whitelisted_fb_users;
	std::vector<QString> whitelisted_ig_users;
};

/* Premiere Living Room Status info
DOCS MISSING
*/
enum PremiereLivingRoomStatus {
	// ???????
};

/* Video info
https://developers.facebook.com/docs/graph-api/reference/video/
*/
struct Video {
	QString id;
	std::vector<uint32_t> ad_breaks;
	time_t backdated_time;
	BackdatedTimeGranularity backdated_time_granularity;
	ContentCategory content_category;
	std::vector<QString> content_tags;
	time_t created_time;
	std::vector<QString> custom_labels;
	QString description;
	QString embed_html;
	bool embeddable;
	Event event;
	std::vector<VideoFormat> format;
	User from; // Could be a Group or Page. Update to a Union?
	QString icon;
	bool is_crosspost_video;
	bool is_crossposting_eligible;
	bool is_episode;
	bool is_instagram_eligible;
	bool is_reference_only;
	uint32_t length;
	VideoStatus live_status;
	MusicVideoCopyright music_video_copyright;
	QString permalink_url;
	Place place;
	uint32_t post_views;
	PremiereLivingRoomStatus premiere_living_room_status;
	Privacy privacy;
	bool published;
	time_t scheduled_publish_time;
	QString source;
	VideoStatus status;
	QString title;
	QString universal_video_id;
	time_t updated_time;
	uint32_t views;
};

/* Audio Codec info */
struct AudioCodec {
	// ??????????
};

/* Video Codec info */
struct VideoCodec {
	// ??????????
};

/* Live Video Recommended Encoder Settings info
Docs MISSING
*/
struct LiveVideoRecommendedEncoderSettings {
	QString streaming_protocol;
	AudioCodec audio_codec_settings;
	VideoCodec video_codec_settings;
};

/* Targeting GeoLocation City info
Docs MISSING
*/
struct TargetingGeoLocationCity {
	QString country;
	QString distance_unit;
	QString key;
	QString name;
	uint16_t radius;
	QString region;
	QString region_id;
};

/* Targeting Geo Location Custom Location info
Docs MISSING
*/
struct TargetingGeoLocationCustomLocation {
	QString address_string;
	QString country;
	QString country_group;
	QString custom_type;
	QString distance_unit;
	QString key;
	float_t latitude;
	float_t longitude;
	uint32_t max_population;
	uint32_t min_population;
	QString name;
	QString primary_city_id;
	float_t radius;
	QString region_id;
};

/* Targeting Geo Location Electoral District info
Docs MISSING
*/
struct TargetingGeoLocationElectoralDistrict {
	QString country;
	QString electoral_district;
	QString key;
	QString name;
};

/* Targeting Geo Location Market info
Docs MISSING
*/
struct TargetingGeoLocationMarket {
	QString country;
	QString key;
	QString market_type;
	QString name;
};

/* Targeting Geo Location Geo Entities info
Docs MISSING
*/
struct TargetingGeoLocationGeoEntities {
	QString country;
	QString key;
	QString name;
	QString region;
	QString region_id;
};

/* TargetingGeoLocationLocationCluster info
Docs MISSING
*/
struct TargetingGeoLocationLocationCluster {
	QString key;
};

/* TargetingGeoLocationLocationExpansion info
Docs MISSING
*/
struct TargetingGeoLocationLocationExpansion {
	bool allowed;
};

/* TargetingGeoLocationPlace info
Docs MISSING
*/
struct TargetingGeoLocationPlace {
	QString country;
	QString distance_unit;
	QString key;
	float_t latitude;
	float_t longitude;
	QString name;
	QString primary_city_id;
	float_t radius;
	QString region_id;
};

/* TargetingGeoLocationPoliticalDistrict info
Docs MISSING
*/
struct TargetingGeoLocationPoliticalDistrict {
	QString country;
	QString key;
	QString name;
	QString political_district;
};

/* TargetingGeoLocationRegion info
Docs MISSING
*/
struct TargetingGeoLocationRegion {
	QString country;
	QString key;
	QString name;
};

/* TargetingGeoLocationZip info
Docs MISSING
*/
struct TargetingGeoLocationZip {
	QString country;
	QString key;
	QString name;
	QString primary_city_id;
	QString region_id;
};

/* Targeting Geo Location info
Docs MISSING
*/
struct TargetingGeoLocation {
	std::vector<TargetingGeoLocationCity> cities;
	std::vector<QString> countries;
	std::vector<QString> country_groups;
	std::vector<TargetingGeoLocationCustomLocation> custom_locations;
	std::vector<TargetingGeoLocationElectoralDistrict> electoral_districts;
	std::vector<TargetingGeoLocationMarket> geo_markets;
	std::vector<TargetingGeoLocationGeoEntities> large_geo_areas;
	std::vector<TargetingGeoLocationLocationCluster> location_cluster_ids;
	TargetingGeoLocationLocationExpansion location_expansion;
	std::vector<QString> location_types;
	std::vector<TargetingGeoLocationGeoEntities> medium_geo_areas;
	std::vector<TargetingGeoLocationGeoEntities> metro_areas;
	std::vector<TargetingGeoLocationGeoEntities> neighborhoods;
	std::vector<TargetingGeoLocationPlace> places;
	std::vector<TargetingGeoLocationPoliticalDistrict> political_districts;
	std::vector<TargetingGeoLocationRegion> regions;
	std::vector<TargetingGeoLocationGeoEntities> small_geo_areas;
	std::vector<TargetingGeoLocationGeoEntities> subcities;
	std::vector<TargetingGeoLocationGeoEntities> subneighborhoods;
	std::vector<TargetingGeoLocationZip> zips;
};

/* Live Video Targeting info
Docs MISSING
*/
struct LiveVideoTargeting {
	uint8_t age_max;
	uint8_t age_min;
	std::vector<QString> excluded_countries;
	TargetingGeoLocation geo_locations;
};

/* Live Video info
https://developers.facebook.com/docs/graph-api/reference/live-video/
*/
struct LiveVideo {
	QString id;
	LiveVideoAdBreakConfig ad_break_config;
	QString ad_break_failure_reason;
	QString broadcast_start_time;
	VideoCopyright copyright;
	time_t creation_time;
	QString dash_ingest_url;
	QString dash_preview_url;
	QString description;
	QString embed_html; // Object?
	User from;          // Could be a Group or Page. Update to a Union?
	std::vector<LiveVideoInputStream> ingest_streams;
	bool is_manual_mode;
	bool is_reference_only;
	uint32_t live_views;
	QString overlay_url;
	QString permalink_url;
	time_t planned_start_time;
	LiveVideoRecommendedEncoderSettings recommended_encoder_settings;
	uint32_t seconds_left;
	QString secure_stream_url;
	VideoStatus status;
	QString stream_url;
	LiveVideoTargeting targeting;
	QString title;
	Video video;
};
