#pragma once

#include "auth-facebook.hpp"

#include <json11.hpp>
#include <QString>

using json11::Json;

bool IsFacebookService(const std::string &service);

class FacebookApiWrappers : public FacebookAuth {
	Q_OBJECT

	bool TrySendGraphRequest(const char *url, const char *content_type,
				 std::string request_type, const char *data,
				 json11::Json &ret, long *error_code = nullptr,
				 int data_size = 0);
	bool UpdateAccessToken();
	bool SendGraphRequest(const char *url, const char *content_type,
			      std::string request_type, const char *data,
			      json11::Json &ret, int data_size = 0);

public:
	FacebookApiWrappers(const Def &d);

	bool GetUserInfo(User &user);

	bool GoLiveNow(LiveVideo &lv, QString &userid);
	bool EndLive(QString &liveVideoId);
	/*
private:
	int lastError;
	QString lastErrorMessage;
	QString lastErrorReason;*/
};
