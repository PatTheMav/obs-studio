#include "facebook-api-wrappers.hpp"

#include "auth-facebook.hpp"
#include "obs-app.hpp"
#include "qt-wrappers.hpp"
#include "remote-text.hpp"
#include "ui-config.h"
#include "obf.h"

#include <QDateTime>

const char *FACEBOOK_GRAPH_OBJECT_URL =
	"https://graph.facebook.com/v17.0/%1?access_token=%2";
const char *FACEBOOK_GROUP_MEMBER_URL =
	"https://graph.facebook.com/v17.0/me/groups/?access_token=%1";
const char *FACEBOOK_BROADCAST_LIST_URL =
	"https://graph.facebook.com/v17.0/me/live_videos?access_token=%1&source=owner";
const char *FACEBOOK_CREATE_BROADCAST_URL =
	"https://graph.facebook.com/v17.0/%1/live_videos?access_token=%2";

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
	if (url) {
		blog(LOG_DEBUG, "Facebook Graph API request URL %s", url);
	}

	if (data) {
		blog(LOG_DEBUG, "Facebook Graph API request DATA %s", data);
	}
#endif

	long httpStatusCode = 0;
	std::string output;
	std::string error;
	// Increase timeout by the time it takes to transfer `data_size` at 1 Mbps
	int timeout = 10 + data_size / 125000;
	bool success = GetRemoteFile(url, output, error, &httpStatusCode,
				     content_type, request_type, data, {},
				     nullptr, timeout, false, data_size);

	if (error_code) {
		*error_code = httpStatusCode;
	}

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
	blog(LOG_DEBUG, "Facebook device answer: %s", json_out.dump().c_str());
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
		success = false;
	}

	return success;
}

#pragma mark - API Functions

bool FacebookApiWrappers::GetBroadcastList(Json &jsonResponse,
					   const QString &page,
					   const QString &status)
{
	QString url;
	if (!page.isEmpty()) {
		url = page;
	} else {
		url = QString(FACEBOOK_BROADCAST_LIST_URL)
			      .arg(QString(token.c_str()));

		if (!status.isEmpty()) {
			url += "&broadcast_status[]=" + status.toUtf8();
		}
	}

	if (!SendGraphRequest(QT_TO_UTF8(url), "application/json", "GET",
			      nullptr, jsonResponse)) {
		return false;
	} else {
		return true;
	}
}

bool FacebookApiWrappers::GetBroadcast(const QString &id, Json &jsonResponse)
{
	QString url = QString(FACEBOOK_GRAPH_OBJECT_URL)
			      .arg(id)
			      .arg(QString(token.c_str()));

	if (!SendGraphRequest(QT_TO_UTF8(url), "application/JSON", "GET",
			      nullptr, jsonResponse)) {
		return false;
	} else {
		return true;
	}
}

QString FacebookApiWrappers::GetBroadcastId()
{
	return this->broadcastId;
}

void FacebookApiWrappers::SetBroadcastId(QString &broadcastId)
{
	this->broadcastId = broadcastId;
}

bool FacebookApiWrappers::GetUserInfo(User &user)
{
	const QString url = FACEBOOK_USER_URL;
	QString data_template = "fields=id,name&access_token=%1";
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

bool FacebookApiWrappers::GetUserGroups(QVector<FacebookGroup> &groupResult)
{
	QString url =
		QString(FACEBOOK_GROUP_MEMBER_URL).arg(QString(token.c_str()));

	Json jsonResponse;
	if (!SendGraphRequest(QT_TO_UTF8(url), "application/json", "GET",
			      nullptr, jsonResponse)) {
		return false;
	}

	groupResult = {};

	for (auto &groupElement : jsonResponse["data"].array_items()) {
		const char *emailData =
			groupElement["email"].string_value().c_str();

		if (strlen(emailData) > 0) {
			groupResult.push_back(
				{groupElement["id"].string_value().c_str(),
				 groupElement["name"].string_value().c_str()});
		}
	}

	return groupResult.isEmpty() ? false : true;
}

bool FacebookApiWrappers::GetUserPages(QVector<FacebookPage> &pageResult)
{
	pageResult = {};

	return pageResult.isEmpty() ? false : true;
}

bool FacebookApiWrappers::CreateStream(FacebookStreamSetup &setup,
				       const QString &userId)
{
	QString statusFlag;

	Json privacyData;

	switch (setup.privacy) {
	case FACEBOOK_PUBLIC:
		privacyData = Json::object{{"value", "EVERYONE"}};
		break;
	case FACEBOOK_FRIENDS:
		privacyData = Json::object{{"value", "ALL_FRIENDS"}};
		break;
	default:
		privacyData =
			Json::object{{"value", "CUSTOM"}, {"friends", "SELF"}};
		break;
	}

	const Json data = Json::object{{
		{"title", QT_TO_UTF8(setup.title)},
		{"description", QT_TO_UTF8(setup.description)},
		{"is_spherical", setup.isSphericalVideo},
		{"privacy", privacyData},
		{"status", QT_TO_UTF8(statusFlag)},
		{"stop_on_delete_stream", false},
	}};

	QString baseUrl = QString(FACEBOOK_CREATE_BROADCAST_URL)
				  .arg(userId)
				  .arg(QString(token.c_str()));

	QString url = baseUrl + "&fields=id,stream_url,secure_stream_url";

	Json jsonResponse;
	if (!SendGraphRequest(QT_TO_UTF8(url), "application/json", "POST",
			      data.dump().c_str(), jsonResponse)) {
		return false;
	}

	setup.id = QString(jsonResponse["id"].string_value().c_str());
	setup.streamUrl =
		QString(jsonResponse["stream_url"].string_value().c_str());
	setup.secureStreamUrl = QString(
		jsonResponse["secure_stream_url"].string_value().c_str());

	return setup.id.isEmpty() ? false : true;
}

bool FacebookApiWrappers::EndStream(QString &liveVideoId)
{
	QString url = QString(FACEBOOK_GRAPH_OBJECT_URL)
			      .arg(liveVideoId)
			      .arg(token.c_str());
	QString data = "end_live_video=true";

	Json jsonResponse;
	if (!SendGraphRequest(QT_TO_UTF8(url), "application/json", "POST",
			      QT_TO_UTF8(data), jsonResponse)) {
		// TODO: HANDLE ERROR
		return false;
	}

	return true;
}
