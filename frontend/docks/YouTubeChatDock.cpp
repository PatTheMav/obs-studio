#include "YouTubeChatDock.hpp"

#include <components/LineEditAutoResize.hpp>
#include <docks/YouTubeAppDock.hpp>
#include <utility/YoutubeApiWrappers.hpp>
#include <widgets/OBSBasic.hpp>

#include <qt-wrappers.hpp>

#include <QHBoxLayout>
#include <QPushButton>

#include "moc_YouTubeChatDock.cpp"

#ifdef BROWSER_AVAILABLE
YoutubeChatDock::YoutubeChatDock(const QString &title) : BrowserDock(title)
{
	lineEdit = new LineEditAutoResize();
	lineEdit->setVisible(false);
	lineEdit->setMaxLength(200);
	lineEdit->setPlaceholderText(QTStr("YouTube.Chat.Input.Placeholder"));
	sendButton = new QPushButton(QTStr("YouTube.Chat.Input.Send"));
	sendButton->setVisible(false);

	chatLayout = new QHBoxLayout();
	chatLayout->setContentsMargins(0, 0, 0, 0);
	chatLayout->addWidget(lineEdit, 1);
	chatLayout->addWidget(sendButton);

	QWidget::connect(lineEdit, &LineEditAutoResize::returnPressed, this, &YoutubeChatDock::SendChatMessage);
	QWidget::connect(sendButton, &QPushButton::pressed, this, &YoutubeChatDock::SendChatMessage);
}

void YoutubeChatDock::SetWidget(QCefWidget *widget_)
{
	QVBoxLayout *layout = new QVBoxLayout();
	layout->setContentsMargins(0, 0, 0, 0);
	layout->addWidget(widget_, 1);
	layout->addLayout(chatLayout);

	QWidget *widget = new QWidget();
	widget->setLayout(layout);
	setWidget(widget);

	cefWidget.reset(widget_);

	QWidget::connect(cefWidget.get(), &QCefWidget::urlChanged, this, &YoutubeChatDock::YoutubeCookieCheck);
}

void YoutubeChatDock::SetApiChatId(const std::string &id)
{
	this->apiChatId = id;
	QMetaObject::invokeMethod(this, "EnableChatInput", Qt::QueuedConnection, Q_ARG(bool, !id.empty()));
}

void YoutubeChatDock::YoutubeCookieCheck()
{
	QPointer<YoutubeChatDock> this_ = this;
	auto cb = [this_](bool currentlyLoggedIn) {
		bool previouslyLoggedIn = this_->isLoggedIn;
		this_->isLoggedIn = currentlyLoggedIn;
		bool loginStateChanged = (currentlyLoggedIn && !previouslyLoggedIn) ||
					 (!currentlyLoggedIn && previouslyLoggedIn);
		if (loginStateChanged) {
			QMetaObject::invokeMethod(this_, "EnableChatInput", Qt::QueuedConnection,
						  Q_ARG(bool, !currentlyLoggedIn));
			OBSBasic *main = OBSBasic::Get();
			if (main->GetYouTubeAppDock() != nullptr) {
				QMetaObject::invokeMethod(main->GetYouTubeAppDock(), "SettingsUpdated",
							  Qt::QueuedConnection, Q_ARG(bool, !currentlyLoggedIn));
			}
		}
	};
	if (panel_cookies) {
		panel_cookies->CheckForCookie("https://www.youtube.com", "SID", cb);
	}
}

void YoutubeChatDock::SendChatMessage()
{
	const QString message = lineEdit->text();
	if (message == "")
		return;

	OBSBasic *main = OBSBasic::Get();
	YoutubeApiWrappers *apiYouTube(dynamic_cast<YoutubeApiWrappers *>(main->GetAuth()));

	ExecuteFuncSafeBlock([&]() {
		lineEdit->setText("");
		lineEdit->setPlaceholderText(QTStr("YouTube.Chat.Input.Sending"));
		if (apiYouTube->SendChatMessage(apiChatId, message)) {
			os_sleep_ms(3000);
		} else {
			QString error = apiYouTube->GetLastError();
			apiYouTube->GetTranslatedError(error);
			QMetaObject::invokeMethod(this, "ShowErrorMessage", Qt::QueuedConnection,
						  Q_ARG(const QString &, error));
		}
		lineEdit->setPlaceholderText(QTStr("YouTube.Chat.Input.Placeholder"));
	});
}

void YoutubeChatDock::ShowErrorMessage(const QString &error)
{
	QMessageBox::warning(this, QTStr("YouTube.Chat.Error.Title"), QTStr("YouTube.Chat.Error.Text").arg(error));
}

void YoutubeChatDock::EnableChatInput(bool visible)
{
	bool setVisible = visible && !isLoggedIn;
	lineEdit->setVisible(setVisible);
	sendButton->setVisible(setVisible);
}
#endif
