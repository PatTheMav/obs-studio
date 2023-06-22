#pragma once

#include "auth-facebook.hpp"

#include <json11.hpp>
#include <QString>

using json11::Json;

bool IsFacebookService(const std::string &service);

struct FacebookGroup {
	QString id;
	QString title;
};

struct FacebookPage {
	QString id;
	QString title;
};

struct FacebookStream {
	QString id;
	QString title;
	QString streamUrl;
};

struct FacebookStreamSetup {
	QString id;
	QString title;
	QString description;
	unsigned int privacy;
	unsigned int channel;
	bool isSphericalVideo;
	bool autoStop;
	QString streamUrl;
	QString secureStreamUrl;
};

class FacebookApiWrappers : public FacebookAuth {
	Q_OBJECT

	bool TrySendGraphRequest(const char *url, const char *content_type,
				 std::string request_type, const char *data,
				 json11::Json &ret, long *error_code = nullptr,
				 int data_size = 0);
	bool SendGraphRequest(const char *url, const char *content_type,
			      std::string request_type, const char *data,
			      json11::Json &ret, int data_size = 0);

public:
	FacebookApiWrappers(const Def &d);

	bool GetBroadcastList(Json &json_out, const QString &page,
			      const QString &status);
	bool GetBroadcast(const QString &id, Json &jsonResponse);

	QString GetBroadcastId();
	void SetBroadcastId(QString &broadcastId);

	bool GetUserInfo(User &user);
	bool GetUserGroups(QVector<FacebookGroup> &groupResult);
	bool GetUserPages(QVector<FacebookPage> &pageResult);

	bool CreateStream(FacebookStreamSetup &setup, const QString &userId);
	bool PublishStream(QString &liveVideoId);
	bool EndStream(QString &liveVideoId);

private:
	QString broadcastId;

	int lastError;
};
