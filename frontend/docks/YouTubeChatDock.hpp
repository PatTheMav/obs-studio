#pragma once

#ifdef BROWSER_AVAILABLE
#include "BrowserDock.hpp"

class LineEditAutoResize;
class QPushButton;
class QHBoxLayout;

class YoutubeChatDock : public BrowserDock {
	Q_OBJECT

private:
	std::string apiChatId;
	bool isLoggedIn;
	LineEditAutoResize *lineEdit;
	QPushButton *sendButton;
	QHBoxLayout *chatLayout;

public:
	YoutubeChatDock(const QString &title);
	void SetWidget(QCefWidget *widget_);
	void SetApiChatId(const std::string &id);

private slots:
	void YoutubeCookieCheck();
	void SendChatMessage();
	void ShowErrorMessage(const QString &error);
	void EnableChatInput(bool visible);
};
#endif
