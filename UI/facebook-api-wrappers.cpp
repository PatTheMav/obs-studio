#include "facebook-api-wrappers.hpp"

#include "auth-facebook.hpp"
#include "obs-app.hpp"
#include "qt-wrappers.hpp"
#include "remote-text.hpp"
#include "ui-config.h"
#include "obf.h"

bool IsFacebookService(const std::string &service)
{
	return service == facebookDef.service;
}

FacebookApiWrappers::FacebookApiWrappers(const Def &d) : FacebookAuth(d) {}

bool FacebookApiWrappers::TrySendGraphRequest(const char *url,
					      const char *content_type,
					      std::string request_type,
					      const char *data,
					      json11::Json &json_out,
					      long *error_code, int data_size)
{
#ifdef _DEBUG
	if (url)
		blog(LOG_WARNING, "Facebook Graph API request URL %s", url);
	if (data)
		blog(LOG_WARNING, "Facebook Graph API request DATA %s", data);
#endif

	long httpStatusCode = 0;
	std::string output;
	std::string error;
	// Increase timeout by the time it takes to transfer `data_size` at 1 Mbps
	int timeout = 5 + data_size / 125000;
	bool success = GetRemoteFile(url, output, error, &httpStatusCode,
				     content_type, request_type, data, {},
				     nullptr, timeout, false, data_size);

	if (error_code)
		*error_code = httpStatusCode;

	if (!success || output.empty()) {
		if (!error.empty())
			blog(LOG_WARNING, "Facebook API request failed: %s",
			     error.c_str());
		return false;
	}

	json_out = Json::parse(output, error);
	if (!error.empty()) {
		return false;
	}

#ifdef _DEBUG
	blog(LOG_WARNING, "Facebook device answer: %s",
	     json_out.dump().c_str());
#endif

	return httpStatusCode < 400;
}

bool FacebookApiWrappers::SendGraphRequest(
	const char *url, const char *content_type, std::string request_type,
	const char *data, json11::Json &json_out, int data_size)
{
	long error_code;
	bool success = TrySendGraphRequest(url, content_type, request_type,
					   data, json_out, &error_code,
					   data_size);

	if (error_code == 401) {
		// Attempt to update access token and try again
		if (!UpdateAccessToken())
			return false;
		success = TrySendGraphRequest(url, content_type, request_type,
					      data, json_out, &error_code,
					      data_size);
	}

	if (json_out.object_items().find("error") !=
	    json_out.object_items().end()) {
		blog(LOG_ERROR,
		     "Facebook API error:\n\tHTTP status: %ld\n\tURL: %s\n\tJSON: %s",
		     error_code, url, json_out.dump().c_str());

		/*lastError = json_out;
		lastErrorReason =
			QString(json_out["error"]["errors"][0]["reason"]
					.string_value()
					.c_str());
		lastErrorMessage = QString(
			json_out["error"]["message"].string_value().c_str());*/

		// The existence of an error implies non-success even
		// if the HTTP status code disagrees.
		success = false;
	}

	return success;
}

bool FacebookApiWrappers::UpdateAccessToken()
{
	/*if (refresh_token.empty()) {
		return false;
	}

	std::string clientid = YOUTUBE_CLIENTID;
	std::string secret = YOUTUBE_SECRET;
	deobfuscate_str(&clientid[0], YOUTUBE_CLIENTID_HASH);
	deobfuscate_str(&secret[0], YOUTUBE_SECRET_HASH);

	std::string r_token =
		QUrl::toPercentEncoding(refresh_token.c_str()).toStdString();
	const QString url = YOUTUBE_LIVE_TOKEN_URL;
	const QString data_template = "client_id=%1"
				      "&client_secret=%2"
				      "&refresh_token=%3"
				      "&grant_type=refresh_token";
	const QString data = data_template.arg(QString(clientid.c_str()),
					       QString(secret.c_str()),
					       QString(r_token.c_str()));
	Json json_out;
	bool success = TryInsertCommand(QT_TO_UTF8(url),
					"application/x-www-form-urlencoded", "",
					QT_TO_UTF8(data), json_out);

	if (!success || json_out.object_items().find("error") !=
				json_out.object_items().end())
		return false;
	token = json_out["access_token"].string_value();
	return token.empty() ? false : true;*/
	return false;
}

bool FacebookApiWrappers::GetUserInfo(User &user)
{
	const QString url = FACEBOOK_USER_URL;
	QString data_template = "fields=id,name"
				"&access_token=%1";
	QString data = data_template.arg(QString(token.c_str()));

	Json json_out;
	if (!SendGraphRequest(QT_TO_UTF8(url), "application/json", "GET",
			      QT_TO_UTF8(data), json_out)) {
		return false;
	}

	user.id = QString(json_out["id"].string_value().c_str());
	user.name = QString(json_out["name"].string_value().c_str());

	return true;
}

bool FacebookApiWrappers::GoLiveNow(LiveVideo &lv, QString &userid)
{
	QString url_template = FACEBOOK_USER_LIVE_VIDEOS;
	QString url = url_template.arg(userid);
	QString data_template =
		"status=LIVE_NOW&title=OBS_VIDEO_TEST"
		"&description=OBS_DESCRIPTION_TEST&access_token=%1";
	QString data = data_template.arg(QString(token.c_str()));

	Json json_out;
	if (!SendGraphRequest(QT_TO_UTF8(url), "application/json", "POST",
			      QT_TO_UTF8(data), json_out)) {
		return false;
	}

	data_template = "fields=video,id,secure_stream_url"
			"&access_token=%1";
	data = data_template.arg(QString(token.c_str()));
	if (!SendGraphRequest(QT_TO_UTF8(url), "application/json", "POST",
			      QT_TO_UTF8(data), json_out)) {
		return false;
	}

	lv.id = QString(json_out["id"].string_value().c_str());
	lv.stream_url =
		QString(json_out["secure_stream_url"].string_value().c_str());
	lv.video.id = QString(json_out["video"]["id"].string_value().c_str());

#ifdef _DEBUG
	blog(LOG_WARNING, "TOKEN %s", token.c_str());
	blog(LOG_WARNING, "VIDEO ID %s", lv.id.toUtf8().constData());
#endif
	return true;
}

bool FacebookApiWrappers::EndLive(QString &liveVideoId)
{
	QString url_template = "%1/%2";
	QString url = url_template.arg(FACEBOOK_API_URL, liveVideoId);
	QString data_template = "end_live_video=true&access_token=%1";
	QString data = data_template.arg(QString(token.c_str()));

	Json json_out;
	if (!SendGraphRequest(QT_TO_UTF8(url), "application/json", "POST",
			      QT_TO_UTF8(data), json_out)) {
		return false;
	}

	return true;
}
