#pragma once

#include "auth-oauth.hpp"
#include "facebook-api-objects.hpp"

class BrowserDock;

inline const Auth::Def facebookDef = {
	"Facebook Live", Auth::Type::OAuth_LinkedAccount, true, true};

class FacebookAuth : public OAuthStreamKey {
	Q_OBJECT

	QSharedPointer<BrowserDock> comments;
	QSharedPointer<BrowserDock> health;
	QSharedPointer<BrowserDock> stats;
	QSharedPointer<BrowserDock> alerts;
	QSharedPointer<QAction> commentsMenu;
	QSharedPointer<QAction> healthMenu;
	QSharedPointer<QAction> statsMenu;
	QSharedPointer<QAction> alertsMenu;
	bool uiLoaded = false;

	virtual bool RetryLogin() override;
	virtual void SaveInternal() override;
	virtual bool LoadInternal() override;
	virtual void LoadUI() override;

	QString GenerateState();

	static std::shared_ptr<Auth> DeviceLoginFlow(QWidget *parent);
	static std::shared_ptr<Auth> WebviewLoginFlow(QWidget *parent);

public:
	FacebookAuth(const Def &d);

	void SetDocksLiveVideoId(QString &liveVideoId);
	void ResetDocks();

	static std::shared_ptr<Auth> Login(QWidget *parent,
					   const std::string &service_name);
};
