#include "GoLiveApi.hpp"

#include <utility/system-info.hpp>
#include <utility/MultitrackVideoError.hpp>
#include <utility/RemoteTextThread.hpp>

#include <OBSApp.hpp>
#include <obs.hpp>

#include <nlohmann/json.hpp>

#include <QMessageBox>

using json = nlohmann::json;

Qt::ConnectionType BlockingConnectionTypeFor(QObject *object);

void censorRecurse(obs_data_t *);
void censorRecurseArray(obs_data_array_t *);

void censorRecurse(json &data)
{
	if (!data.is_structured())
		return;

	auto it = data.find("authentication");
	if (it != data.end() && it->is_string()) {
		*it = "CENSORED";
	}

	for (auto &child : data) {
		censorRecurse(child);
	}
}

void censorRecurseArray(obs_data_array_t *array)
{
	const size_t sz = obs_data_array_count(array);
	for (size_t i = 0; i < sz; i++) {
		obs_data_t *item = obs_data_array_item(array, i);
		censorRecurse(item);
		obs_data_release(item);
	}
}

void censorRecurse(obs_data_t *data)
{
	// if we found what we came to censor, censor it
	const char *a = obs_data_get_string(data, "authentication");
	if (a && *a) {
		obs_data_set_string(data, "authentication", "CENSORED");
	}

	// recurse to child objects and arrays
	obs_data_item_t *item = obs_data_first(data);
	for (; item != NULL; obs_data_item_next(&item)) {
		enum obs_data_type typ = obs_data_item_gettype(item);

		if (typ == OBS_DATA_OBJECT) {
			obs_data_t *child_data = obs_data_item_get_obj(item);
			censorRecurse(child_data);
			obs_data_release(child_data);
		} else if (typ == OBS_DATA_ARRAY) {
			obs_data_array_t *child_array = obs_data_item_get_array(item);
			censorRecurseArray(child_array);
			obs_data_array_release(child_array);
		}
	}
}

QString censoredJson(obs_data_t *data, bool pretty)
{
	if (!data) {
		return "";
	}

	// Ugly clone via JSON write/read
	const char *j = obs_data_get_json(data);
	obs_data_t *clone = obs_data_create_from_json(j);

	// Censor our copy
	censorRecurse(clone);

	// Turn our copy into JSON
	QString s = pretty ? obs_data_get_json_pretty(clone) : obs_data_get_json(clone);

	// Eliminate our copy
	obs_data_release(clone);

	return s;
}

QString censoredJson(json data, bool pretty)
{
	censorRecurse(data);

	return QString::fromStdString(data.dump(pretty ? 4 : -1));
}

void HandleGoLiveApiErrors(QWidget *parent, const json &raw_json, const GoLiveApi::Config &config)
{
	using GoLiveApi::StatusResult;

	if (!config.status)
		return;

	auto &status = *config.status;
	if (status.result == StatusResult::Success)
		return;

	auto warn_continue = [&](QString message) {
		bool ret = false;
		QMetaObject::invokeMethod(
			parent,
			[=] {
				QMessageBox mb(parent);
				mb.setIcon(QMessageBox::Warning);
				mb.setWindowTitle(QTStr("ConfigDownload.WarningMessageTitle"));
				mb.setTextFormat(Qt::RichText);
				mb.setText(message + QTStr("FailedToStartStream.WarningRetry"));
				mb.setStandardButtons(QMessageBox::StandardButton::Yes |
						      QMessageBox::StandardButton::No);
				return mb.exec() == QMessageBox::StandardButton::No;
			},
			BlockingConnectionTypeFor(parent), &ret);
		if (ret)
			throw MultitrackVideoError::cancel();
	};

	auto missing_html = [] {
		return QTStr("FailedToStartStream.StatusMissingHTML").toStdString();
	};

	if (status.result == StatusResult::Unknown) {
		return warn_continue(QTStr("FailedToStartStream.WarningUnknownStatus")
					     .arg(raw_json["status"]["result"].dump().c_str()));

	} else if (status.result == StatusResult::Warning) {
		if (config.encoder_configurations.empty()) {
			throw MultitrackVideoError::warning(status.html_en_us.value_or(missing_html()).c_str());
		}

		return warn_continue(status.html_en_us.value_or(missing_html()).c_str());
	} else if (status.result == StatusResult::Error) {
		throw MultitrackVideoError::critical(status.html_en_us.value_or(missing_html()).c_str());
	}
}

QString MultitrackVideoAutoConfigURL(obs_service_t *service)
{
	static const std::optional<QString> cli_url = []() -> std::optional<QString> {
		auto args = qApp->arguments();
		for (int i = 0; i < args.length() - 1; i++) {
			if (args[i] == "--config-url" && args.length() > (i + 1)) {
				return args[i + 1];
			}
		}
		return std::nullopt;
	}();

	QString url;
	if (cli_url.has_value()) {
		url = *cli_url;
	} else {
		OBSDataAutoRelease settings = obs_service_get_settings(service);
		url = obs_data_get_string(settings, "multitrack_video_configuration_url");
	}

	blog(LOG_INFO, "Go live URL: %s", url.toUtf8().constData());
	return url;
}

GoLiveApi::Config DownloadGoLiveConfig(QWidget *parent, QString url, const GoLiveApi::PostData &post_data,
				       const QString &multitrack_video_name)
{
	json post_data_json = post_data;
	blog(LOG_INFO, "Go live POST data: %s", censoredJson(post_data_json).toUtf8().constData());

	if (url.isEmpty())
		throw MultitrackVideoError::critical(QTStr("FailedToStartStream.MissingConfigURL"));

	std::string encodeConfigText;
	std::string libraryError;

	std::vector<std::string> headers;
	headers.push_back("Content-Type: application/json");
	bool encodeConfigDownloadedOk = GetRemoteFile(url.toLocal8Bit(), encodeConfigText,
						      libraryError, // out params
						      nullptr,
						      nullptr, // out params (response code and content type)
						      "POST", post_data_json.dump().c_str(), headers,
						      nullptr, // signature
						      5);      // timeout in seconds

	if (!encodeConfigDownloadedOk)
		throw MultitrackVideoError::warning(
			QTStr("FailedToStartStream.ConfigRequestFailed").arg(url, libraryError.c_str()));
	try {
		auto data = json::parse(encodeConfigText);
		blog(LOG_INFO, "Go live response data: %s", censoredJson(data, true).toUtf8().constData());
		GoLiveApi::Config config = data;
		HandleGoLiveApiErrors(parent, data, config);
		return config;

	} catch (const json::exception &e) {
		blog(LOG_INFO, "Failed to parse go live config: %s", e.what());
		throw MultitrackVideoError::warning(
			QTStr("FailedToStartStream.FallbackToDefault").arg(multitrack_video_name));
	}
}

GoLiveApi::PostData constructGoLivePost(QString streamKey, const std::optional<uint64_t> &maximum_aggregate_bitrate,
					const std::optional<uint32_t> &maximum_video_tracks, bool vod_track_enabled)
{
	GoLiveApi::PostData post_data{};
	post_data.service = "IVS";
	post_data.schema_version = "2024-06-04";
	post_data.authentication = streamKey.toStdString();

	system_info(post_data.capabilities);

	auto &client = post_data.client;

	client.name = "obs-studio";
	client.version = obs_get_version_string();

	auto add_codec = [&](const char *codec) {
		auto it = std::find(std::begin(client.supported_codecs), std::end(client.supported_codecs), codec);
		if (it != std::end(client.supported_codecs))
			return;

		client.supported_codecs.push_back(codec);
	};

	const char *encoder_id = nullptr;
	for (size_t i = 0; obs_enum_encoder_types(i, &encoder_id); i++) {
		auto codec = obs_get_encoder_codec(encoder_id);
		if (!codec)
			continue;

		if (qstricmp(codec, "h264") == 0) {
			add_codec("h264");
#ifdef ENABLE_HEVC
		} else if (qstricmp(codec, "hevc")) {
			add_codec("h265");
#endif
		} else if (qstricmp(codec, "av1")) {
			add_codec("av1");
		}
	}

	auto &preferences = post_data.preferences;
	preferences.vod_track_audio = vod_track_enabled;

	obs_video_info ovi;
	if (obs_get_video_info(&ovi)) {
		preferences.width = ovi.output_width;
		preferences.height = ovi.output_height;
		preferences.framerate.numerator = ovi.fps_num;
		preferences.framerate.denominator = ovi.fps_den;

		preferences.canvas_width = ovi.base_width;
		preferences.canvas_height = ovi.base_height;

		preferences.composition_gpu_index = ovi.adapter;
	}

	if (maximum_aggregate_bitrate.has_value())
		preferences.maximum_aggregate_bitrate = maximum_aggregate_bitrate.value();
	if (maximum_video_tracks.has_value())
		preferences.maximum_video_tracks = maximum_video_tracks.value();

	return post_data;
}
