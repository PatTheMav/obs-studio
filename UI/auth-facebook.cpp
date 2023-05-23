#include "auth-facebook.hpp"

#include <QThread>
#include <vector>
#include <QDesktopServices>
#include <QUrl>
#if (QT_VERSION >= QT_VERSION_CHECK(5, 10, 0))
#include <QRandomGenerator>
#endif

#include "remote-text.hpp"
#include <obs-app.hpp>
#include <qt-wrappers.hpp>
#include "ui-config.h"
#include "facebook-api-wrappers.hpp"
#include "window-basic-main.hpp"
#include "obf.h"

#include "window-dock-browser.hpp"

static inline void OpenBrowser(const QString auth_uri)
{
	QUrl url(auth_uri, QUrl::StrictMode);
	QDesktopServices::openUrl(url);
}

static std::shared_ptr<FacebookApiWrappers> CreateFacebookAuth()
{
	return std::make_shared<FacebookApiWrappers>(facebookDef);
}

static void DeleteCookies()
{
	if (panel_cookies)
		panel_cookies->DeleteCookies("twitch.tv", std::string());
}

void RegisterFacebookAuth()
{
	OAuth::RegisterOAuth(facebookDef, CreateFacebookAuth,
			     FacebookAuth::Login, DeleteCookies);
}

FacebookAuth::FacebookAuth(const Def &d) : OAuthStreamKey(d) {}

void FacebookAuth::SaveInternal()
{
	OBSBasic *main = OBSBasic::Get();
	config_set_string(main->Config(), FACEBOOK_SECTION_NAME, "DockState",
			  main->saveState().toBase64().constData());

	config_set_string(main->Config(), FACEBOOK_SECTION_NAME, "Token",
			  token.c_str());
	config_set_uint(main->Config(), FACEBOOK_SECTION_NAME, "ExpireTime",
			expire_time);
	config_set_int(main->Config(), FACEBOOK_SECTION_NAME, "ScopeVer",
		       currentScopeVer);
}

static inline std::string get_config_str(OBSBasic *main, const char *section,
					 const char *name)
{
	const char *val = config_get_string(main->Config(), section, name);
	return val ? val : "";
}

bool FacebookAuth::LoadInternal()
{
	OBSBasic *main = OBSBasic::Get();

	token = get_config_str(main, FACEBOOK_SECTION_NAME, "Token");
	expire_time = config_get_uint(main->Config(), FACEBOOK_SECTION_NAME,
				      "ExpireTime");
	currentScopeVer = (int)config_get_int(
		main->Config(), FACEBOOK_SECTION_NAME, "ScopeVer");

	firstLoad = false;

	return !token.empty();
}

void FacebookAuth::SetDocksLiveVideoId(QString &liveVideoId)
{
	QString commentsUrl =
		QString(FACEBOOK_COMMENTS_POPUP_URL).arg(liveVideoId);
	QString healthUrl = QString(FACEBOOK_HEALTH_POPUP_URL).arg(liveVideoId);
	QString statsUrl = QString(FACEBOOK_STATS_POPUP_URL).arg(liveVideoId);
	QString alertsUrl = QString(FACEBOOK_ALERTS_POPUP_URL).arg(liveVideoId);

	if (comments && comments->cefWidget) {
		comments->cefWidget->setURL(commentsUrl.toStdString());
	}
	if (health && health->cefWidget) {
		health->cefWidget->setURL(healthUrl.toStdString());
	}
	if (stats && stats->cefWidget) {
		stats->cefWidget->setURL(statsUrl.toStdString());
	}
	if (alerts && alerts->cefWidget) {
		alerts->cefWidget->setURL(alertsUrl.toStdString());
	}
}

void FacebookAuth::ResetDocks()
{
	if (comments && comments->cefWidget) {
		comments->cefWidget->setURL(FACEBOOK_COMMENTS_PLACEHOLDER_URL);
	}
	if (health && health->cefWidget) {
		health->cefWidget->setURL(FACEBOOK_HEALTH_PLACEHOLDER_URL);
	}
	if (stats && stats->cefWidget) {
		stats->cefWidget->setURL(FACEBOOK_STATS_PLACEHOLDER_URL);
	}
	if (alerts && alerts->cefWidget) {
		alerts->cefWidget->setURL(FACEBOOK_ALERTS_PLACEHOLDER_URL);
	}
}

static const char *fbchat_script = "\
const obsCSS = document.createElement('style');\
obsCSS.innerHTML = \"#panel-pages.yt-live-chat-renderer {display: none;}\
yt-live-chat-viewer-engagement-message-renderer {display: none;}\";\
document.querySelector('head').appendChild(obsCSS);";

void FacebookAuth::LoadUI()
{
	if (uiLoaded)
		return;

	if (!cef)
		return;

	OBSBasic::InitBrowserPanelSafeBlock();
	OBSBasic *main = OBSBasic::Get();

	QCefWidget *browser;
	std::string url;
	std::string script;

	QSize size = main->frameSize();
	QPoint pos = main->pos();

	/* ----------------------------------- */

	comments.reset(new BrowserDock());
	comments->setObjectName("fbComments");
	comments->resize(300, 600);
	comments->setMinimumSize(200, 300);
	comments->setWindowTitle(QTStr("Facebook.Docks.Comments"));
	comments->setAllowedAreas(Qt::AllDockWidgetAreas);

	browser = cef->create_widget(comments.data(),
				     FACEBOOK_COMMENTS_PLACEHOLDER_URL,
				     panel_cookies);
	browser->setStartupScript(fbchat_script);
	comments->SetWidget(browser);

	main->addDockWidget(Qt::RightDockWidgetArea, comments.data());
	commentsMenu.reset(main->AddDockWidget(comments.data()));

	/* ----------------------------------- */

	health.reset(new BrowserDock());
	health->setObjectName("fbHealth");
	health->resize(300, 600);
	health->setMinimumSize(200, 300);
	health->setWindowTitle(QTStr("Facebook.Docks.Health"));
	health->setAllowedAreas(Qt::AllDockWidgetAreas);

	browser = cef->create_widget(
		health.data(), FACEBOOK_HEALTH_PLACEHOLDER_URL, panel_cookies);
	browser->setStartupScript(fbchat_script);
	health->SetWidget(browser);

	main->addDockWidget(Qt::RightDockWidgetArea, health.data());
	healthMenu.reset(main->AddDockWidget(health.data()));

	/* ----------------------------------- */

	stats.reset(new BrowserDock());
	stats->setObjectName("fbComments");
	stats->resize(300, 600);
	stats->setMinimumSize(200, 300);
	stats->setWindowTitle(QTStr("Facebook.Docks.Stats"));
	stats->setAllowedAreas(Qt::AllDockWidgetAreas);

	browser = cef->create_widget(
		stats.data(), FACEBOOK_STATS_PLACEHOLDER_URL, panel_cookies);
	browser->setStartupScript(fbchat_script);
	stats->SetWidget(browser);

	main->addDockWidget(Qt::RightDockWidgetArea, stats.data());
	statsMenu.reset(main->AddDockWidget(stats.data()));

	/* ----------------------------------- */

	alerts.reset(new BrowserDock());
	alerts->setObjectName("fbComments");
	alerts->resize(300, 600);
	alerts->setMinimumSize(200, 300);
	alerts->setWindowTitle(QTStr("Facebook.Docks.Alerts"));
	alerts->setAllowedAreas(Qt::AllDockWidgetAreas);

	browser = cef->create_widget(
		alerts.data(), FACEBOOK_ALERTS_PLACEHOLDER_URL, panel_cookies);
	browser->setStartupScript(fbchat_script);
	alerts->SetWidget(browser);

	main->addDockWidget(Qt::RightDockWidgetArea, alerts.data());
	alertsMenu.reset(main->AddDockWidget(alerts.data()));

	/* ----------------------------------- */

	comments->setFloating(true);
	health->setFloating(true);
	stats->setFloating(true);
	alerts->setFloating(true);

	QSize statSize = stats->frameSize();

	comments->move(pos.x() + size.width() - comments->width() - 50,
		       pos.y() + 50);

	health->move(pos.x() + 50, pos.y() + 50);
	stats->move(pos.x() + size.width() / 2 - statSize.width() / 2,
		    pos.y() + size.height() / 2 - statSize.height() / 2);
	alerts->move(pos.x() + 100, pos.y() + 100);

	if (firstLoad) {
		comments->setVisible(true);
		health->setVisible(true);
		stats->setVisible(true);
		alerts->setVisible(true);
	} else {
		const char *dsStr = config_get_string(
			main->Config(), FACEBOOK_SECTION_NAME, "DockState");
		main->restoreState(QByteArray::fromBase64(QByteArray(dsStr)));
	}

	uiLoaded = true;
}

bool FacebookAuth::RetryLogin()
{
	return Login(OBSBasic::Get(), nullptr) != nullptr;
}

QString FacebookAuth::GenerateState()
{
#if (QT_VERSION >= QT_VERSION_CHECK(5, 10, 0))
	char state[FACEBOOK_API_STATE_LENGTH + 1];
	QRandomGenerator *rng = QRandomGenerator::system();
	int i;

	for (i = 0; i < FACEBOOK_API_STATE_LENGTH; i++)
		state[i] = allowedChars[rng->bounded(0, allowedCount)];
	state[i] = 0;

	return state;
#else
	std::uniform_int_distribution<> distr(0, allowedCount);
	std::string result;
	result.reserve(FACEBOOK_API_STATE_LENGTH);
	std::generate_n(std::back_inserter(result), FACEBOOK_API_STATE_LENGTH,
			[&] {
				return static_cast<char>(
					allowedChars[distr(randomSeed)]);
			});
	return result.c_str();
#endif
}

std::shared_ptr<Auth> FacebookAuth::WebviewLoginFlow(QWidget *parent)
{
#ifdef _DEBUG
	blog(LOG_WARNING, "Login Webview Started.");
#endif
	const auto auth = CreateFacebookAuth();

	QString redirect_uri =
		//QString("http://localhost:%1").arg(server.GetPort());
		QString("https://www.facebook.com/connect/login_success.html");

	std::string clientid = FACEBOOK_CLIENTID;
	std::string secret = FACEBOOK_SECRET;
	deobfuscate_str(&clientid[0], FACEBOOK_CLIENTID_HASH);
	deobfuscate_str(&secret[0], FACEBOOK_SECRET_HASH);

	QString state = auth->GenerateState();

	QString url_template;
	url_template += "%1";
	url_template += "?response_type=code";
	url_template += "&client_id=%2";
	url_template += "&redirect_uri=%3";
	url_template += "&state=%4";
	url_template += "&scope=%5";
	QString url = url_template.arg(FACEBOOK_LOGIN_URL, clientid.c_str(),
				       redirect_uri, state,
				       FACEBOOK_PERMISSION_PUBLISH_VIDEO);

#ifdef _DEBUG
	blog(LOG_WARNING, QT_TO_UTF8(url));
#endif
	OAuthLogin login(parent, QT_TO_UTF8(url), false);
	if (login.exec() == QDialog::Rejected)
		return nullptr;

	if (!auth->GetToken(FACEBOOK_TOKEN_URL, clientid, secret,
			    QT_TO_UTF8(redirect_uri), FACEBOOK_SCOPE_VERSION,
			    QT_TO_UTF8(login.GetCode()), true)) {
		return nullptr;
	}

	User u;
	if (!auth->GetUserInfo(u))
		return nullptr;

	config_t *config = OBSBasic::Get()->Config();
	config_remove_value(config, FACEBOOK_SECTION_NAME, FACEBOOK_USER_ID);
	config_remove_value(config, FACEBOOK_SECTION_NAME, FACEBOOK_USER_NAME);

	config_set_string(config, FACEBOOK_SECTION_NAME, FACEBOOK_USER_ID,
			  QT_TO_UTF8(u.id));
	config_set_string(config, FACEBOOK_SECTION_NAME, FACEBOOK_USER_NAME,
			  QT_TO_UTF8(u.name));

	config_save_safe(config, "tmp", nullptr);

	return auth;
}

std::shared_ptr<Auth> FacebookAuth::Login(QWidget *parent, const std::string &)
{
	return WebviewLoginFlow(parent);
}
