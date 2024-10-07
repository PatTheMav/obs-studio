#pragma once

#include "models/multitrack-video.hpp"

class QString;
class QWidget;

/**
 * Returns the input serialized to JSON, but any non-empty "authorization"
 * properties have their values replaced by "CENSORED".
 */
QString censoredJson(obs_data_t *data, bool pretty = false);
QString censoredJson(nlohmann::json data, bool pretty = false);

/** Returns either GO_LIVE_API_PRODUCTION_URL or a command line override. */
QString MultitrackVideoAutoConfigURL(obs_service_t *service);

GoLiveApi::Config DownloadGoLiveConfig(QWidget *parent, QString url, const GoLiveApi::PostData &post_data,
				       const QString &multitrack_video_name);
GoLiveApi::PostData constructGoLivePost(QString streamKey, const std::optional<uint64_t> &maximum_aggregate_bitrate,
					const std::optional<uint32_t> &maximum_video_tracks, bool vod_track_enabled);
