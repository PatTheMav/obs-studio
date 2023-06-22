#include "window-basic-main.hpp"
#include "window-facebook-actions.hpp"

#include "obs-app.hpp"
#include "qt-wrappers.hpp"
#include "facebook-api-wrappers.hpp"

#include <QDateTime>
#include <QDesktopServices>

const char *FACEBOOK_DATETIME_FORMAT = "yyyy-MM-dd'T'hh:mm:ss'Z'";

OBSFacebookActions::OBSFacebookActions(QWidget *parent, Auth *auth,
				       bool broadcastReady)
	: QDialog(parent),
	  ui(new Ui::OBSFacebookActions),
	  apiFacebook(dynamic_cast<FacebookApiWrappers *>(auth)),
	  workerThread(new FacebookApiThread(apiFacebook)),
	  broadcastReady(broadcastReady)
{
	setWindowFlags(windowFlags() & ~Qt::WindowContextHelpButtonHint);
	ui->setupUi(this);

	const char *userName = config_get_string(OBSBasic::Get()->Config(),
						 "Facebook Live", "UserName");
	this->setWindowTitle(
		QTStr("Facebook.Actions.WindowTitle").arg(userName));

	ui->privacyBox->addItem(QTStr("Facebook.Actions.Audience.Private"),
				FACEBOOK_PRIVATE);
	ui->privacyBox->addItem(QTStr("Facebook.Actions.Audience.Friends"),
				FACEBOOK_FRIENDS);
	ui->privacyBox->addItem(QTStr("Facebook.Actions.Audience.Public"),
				FACEBOOK_PUBLIC);

	ui->channelBox->addItem(QTStr("Facebook.Actions.Channel.Timeline"),
				FACEBOOK_TIMELINE);
	ui->channelBox->addItem(QTStr("Facebook.Actions.Channel.Group"),
				FACEBOOK_GROUP);
	ui->channelBox->addItem(QTStr("Facebook.Actions.Channel.Page"),
				FACEBOOK_PAGE);

	int channelType = ui->channelBox->currentIndex();
	ChangeChannel(channelType);
	CheckConfiguration();

	connect(ui->title, &QLineEdit::textChanged, this,
		[&](const QString &) { this->CheckConfiguration(); });
	connect(ui->description, &QPlainTextEdit::textChanged, this,
		[&] { this->CheckConfiguration(); });
	connect(ui->privacyBox, &QComboBox::currentTextChanged, this,
		[&](const QString &) { this->CheckConfiguration(); });
	connect(ui->channelBox, &QComboBox::currentIndexChanged, this,
		&OBSFacebookActions::ChangeChannel);

	connect(ui->fbBroadcastTabWidget, &QTabWidget::currentChanged, this,
		[&](int) { this->CheckConfiguration(); });

	connect(ui->dashButton, &QPushButton::clicked, this,
		&OBSFacebookActions::OpenFacebookDashboard);
	connect(ui->liveButton, &QPushButton::clicked, this,
		&OBSFacebookActions::StartBroadcast);
	connect(ui->saveButton, &QPushButton::clicked, this,
		&OBSFacebookActions::ScheduleBroadcast);
	connect(ui->cancelButton, &QPushButton::clicked, this, [&] {
		blog(LOG_DEBUG, "Facebook Live Video creation cancelled.");
		Cancel();
	});

	if (!apiFacebook) {
#ifdef _DEBUG
		blog(LOG_DEBUG, "Facebook API auth not found.");
#endif
		Cancel();
		return;
	}

	qDeleteAll(ui->fbEventList->findChildren<QWidget *>(
		QString(), Qt::FindDirectChildrenOnly));

	QLabel *loadingLabel = new QLabel();
	loadingLabel->setTextFormat(Qt::RichText);
	loadingLabel->setAlignment(Qt::AlignHCenter);
	loadingLabel->setText(
		QString("<big>%1</big>")
			.arg(QTStr("Facebook.Actions.EventsLoading")));
	ui->fbEventlist->layout()->addWidget(loadingLabel);

	connect(workerThread, &FacebookApiThread::finished, this, [&] {
		QLayoutItem *item = ui->fbEventlist->layout()->takeAt(0);
		item->widget()->deleteLater();
	});

	connect(workerThread, &FacebookApiThread::failed, this, [&] {
		// TODO: SHOW ERROR
		QDialog::reject();
	});

	connect(workerThread, &FacebookApiThread::new_item, this,
		[&](const QString &title, const QString &broadcastId) {
			ClickableLabel *label = new ClickableLabel();
			label->setTextFormat(Qt::RichText);

			label->setText(
				QString("<big>%1</big><br/>%2")
					.arg(title,
					     QTStr("Facebook.Actions.SelectLive")));

			label->setAlignment(Qt::AlignHCenter);
			label->setMargin(4);

			connect(label, &ClickableLabel::clicked, this,
				[&, label, broadcastId]() {
					for (QWidget *i :
					     ui->fbEventlist->findChildren<
						     QWidget *>(
						     QString(),
						     Qt::FindDirectChildrenOnly)) {
						i->setProperty(
							"isSelectedEvent",
							"false");
						i->style()->unpolish(i);
						i->style()->polish(i);
					}

					label->setProperty("isSelectedEvent",
							   "true");
					label->style()->unpolish(label);
					label->style()->polish(label);

					this->selectedBroadcast = broadcastId;
					CheckConfiguration();
				});
			ui->fbEventlist->layout()->addWidget(label);

			if (selectedBroadcast == broadcastId) {
				label->clicked();
			}
		});

	workerThread->start();

	if (broadcastReady) {
		ui->fbBroadcastTabWidget->setCurrentIndex(1);
		selectedBroadcast = apiFacebook->GetBroadcastId();
	}

#ifdef __APPLE__
	this->resize(this->width() + 200, this->height() + 120);
#endif
	valid = true;
}

void OBSFacebookActions::CheckConfiguration()
{
	int tabIndex = ui->fbBroadcastTabWidget->currentIndex();

	if (tabIndex == 0) {
		bool hasText = !ui->title->text().isEmpty();
		bool hasDescription = !ui->description->toPlainText().isEmpty();
		bool hasAudience = !ui->privacyBox->currentText().isEmpty();
		bool pass = hasText && hasDescription && hasAudience;

		if (!hasText) {
			ui->titleLabel->setStyleSheet("QLabel { color: red; }");
		} else {
			ui->titleLabel->setStyleSheet("QLabel {}");
		}

		if (!hasDescription) {
			ui->descriptionLabel->setStyleSheet(
				"QLabel { color: red; }");
		} else {
			ui->descriptionLabel->setStyleSheet("QLabel {}");
		}

		ui->liveButton->setEnabled(pass);

		ui->liveButton->setText(QTStr("Facebook.Actions.GoLive"));
		ui->dashButton->setVisible(false);
	} else {
		bool pass = !selectedBroadcast.isEmpty();
		ui->liveButton->setEnabled(pass);
		ui->saveButton->setEnabled(pass);

		ui->liveButton->setText(
			QTStr("Facebook.Actions.ChooseAndGoLive"));
		ui->saveButton->setText(
			QTStr("Facebook.Actions.ChooseBroadcast"));

		ui->dashButton->setVisible(true);
	}
}

void OBSFacebookActions::ChangeChannel(int index)
{
	switch (index) {
	case FACEBOOK_GROUP: {
		QVector<FacebookGroup> groupList;

		if (!apiFacebook->GetUserGroups(groupList)) {
#ifdef _DEBUG
			const char *userName =
				config_get_string(OBSBasic::Get()->Config(),
						  "Facebook Live", "UserName");
			blog(LOG_DEBUG,
			     "User %s is not a member of any Facebook group.",
			     userName);
#endif
			ui->groupLabel->setStyleSheet("QLabel { color: red; }");
		} else {
			for (auto &facebookGroup : groupList) {
				ui->groupBox->addItem(facebookGroup.title,
						      facebookGroup.id);
			}
			ui->groupLabel->setStyleSheet("QLabel {}");
		}
		ui->groupBox->setVisible(true);
		ui->groupLabel->setVisible(true);

		ui->privacyBox->setVisible(false);
		ui->privacyLabel->setVisible(false);
		ui->pageLabel->setVisible(false);
		ui->pageBox->setVisible(false);
	} break;
	case FACEBOOK_PAGE: {
		QVector<FacebookPage> pageList;

		if (!apiFacebook->GetUserPages(pageList)) {
#ifdef _DEBUG
			const char *userName =
				config_get_string(OBSBasic::Get()->Config(),
						  "Facebook Live", "UserName");
			blog(LOG_DEBUG,
			     "User %s is not a member of any Facebook Page",
			     userName);
#endif
			ui->pageLabel->setStyleSheet("QLabel { color: red; }");
		} else {
			for (auto &facebookPage : pageList) {
				ui->pageBox->addItem(facebookPage.title,
						     facebookPage.id);
			}
			ui->pageLabel->setStyleSheet("QLabel {}");
		}

		ui->pageLabel->setVisible(true);
		ui->pageBox->setVisible(true);

		ui->privacyBox->setVisible(false);
		ui->privacyLabel->setVisible(false);
		ui->groupBox->setVisible(false);
		ui->groupLabel->setVisible(false);
	} break;
	default: {
		ui->privacyBox->setVisible(true);
		ui->privacyLabel->setVisible(true);

		ui->groupBox->setVisible(false);
		ui->groupLabel->setVisible(false);
		ui->pageLabel->setVisible(false);
		ui->pageBox->setVisible(false);

	} break;
	}
}

void OBSFacebookActions::StartBroadcast()
{
	FacebookStream stream;
	QMessageBox messageBox(this);

	messageBox.setWindowFlags(messageBox.windowFlags() &
				  ~Qt::WindowCloseButtonHint);
	messageBox.setWindowTitle(
		QTStr("Facebook.Actions.Notifications.Start.Title"));
	messageBox.setText(QTStr("Facebook.Actions.Notifications.Start.Text"));
	messageBox.setStandardButtons(QMessageBox::StandardButtons());

	bool success = false;
	auto action = [&]() {
		if (ui->fbBroadcastTabWidget->currentIndex() == 0) {
			success = this->CreateEvent(apiFacebook, stream);
		} else {
			success = this->SelectEvent(apiFacebook, stream);
		}

		QMetaObject::invokeMethod(&messageBox, "accept",
					  Qt::QueuedConnection);
	};

	QScopedPointer<QThread> thread(CreateQThread(action));
	thread->start();
	messageBox.exec();
	thread->wait();

	if (success) {
		if (ui->fbBroadcastTabWidget->currentIndex() == 0) {
#ifdef _DEBUG
			blog(LOG_DEBUG, "Facebook Live Video created: %s",
			     QT_TO_UTF8(stream.title));
#endif
			emit ok(QT_TO_UTF8(stream.id),
				QT_TO_UTF8(stream.streamUrl), true, true);
			Accept();
		} else {
#ifdef _DEBUG
			blog(LOG_DEBUG, "Facebook Live Video selected: %s",
			     QT_TO_UTF8(stream.title));
#endif
			emit ok(QT_TO_UTF8(stream.id),
				QT_TO_UTF8(stream.streamUrl), false, true);
			Accept();
		}

	} else {
		// TODO: IMPLEMENT ERROR DIALOG
		;
	}
}

void OBSFacebookActions::ScheduleBroadcast()
{
	FacebookStream stream;
	QMessageBox messageBox(this);

	messageBox.setWindowFlags(messageBox.windowFlags() &
				  ~Qt::WindowCloseButtonHint);
	messageBox.setWindowTitle(
		QTStr("Facebook.Actions.Notifications.Schedule.Title"));
	messageBox.setText(
		QTStr("Facebook.Actions.Notifications.Schedule.Text"));
	messageBox.setStandardButtons(QMessageBox::StandardButtons());

	bool success = false;
	auto action = [&]() {
		if (ui->fbBroadcastTabWidget->currentIndex() == 0) {
			success = this->CreateEvent(apiFacebook, stream);
		} else {
			success = this->SelectEvent(apiFacebook, stream);
		}

		QMetaObject::invokeMethod(&messageBox, "accept",
					  Qt::QueuedConnection);
	};

	QScopedPointer<QThread> thread(CreateQThread(action));
	thread->start();
	messageBox.exec();
	thread->wait();

	if (success) {
		emit ok(QT_TO_UTF8(stream.id), QT_TO_UTF8(stream.streamUrl),
			autoStop, false);
		Accept();
	} else {
		// TODO: HANDLE ERROR
		;
	}
}

bool OBSFacebookActions::CreateEvent(FacebookApiWrappers *api,
				     FacebookStream &stream)
{
	FacebookApiWrappers *apiFacebook = api;
	FacebookStreamSetup setup = {
		nullptr,
		ui->title->text(),
		ui->description->toPlainText().left(5000),
		ui->privacyBox->currentData().toUInt(),
		ui->channelBox->currentData().toUInt(),
		ui->checkSphericalVideo->isChecked(),
		false,
		nullptr,
		nullptr,
	};

	setup.autoStop = true;
	autoStop = setup.autoStop;

	QString userId;

	switch (ui->channelBox->currentData().toUInt()) {
	case FACEBOOK_GROUP:
		userId = ui->groupBox->currentText();
		break;

	case FACEBOOK_PAGE:
		userId = ui->groupBox->currentText();
		break;
	default:
		userId = QString("me");
		break;
	}

	if (!apiFacebook->CreateStream(setup, userId)) {
#ifdef _DEBUG
		blog(LOG_DEBUG, "Create Stream unsuccessful.");
#endif
		return false;
	}

	stream.id = setup.id;
	stream.streamUrl = setup.secureStreamUrl;

	return true;
}

bool OBSFacebookActions::SelectEvent(FacebookApiWrappers *api,
				     FacebookStream &stream)
{
	FacebookApiWrappers *apiFacebook = api;

	Json jsonResponse;

	if (!apiFacebook->GetBroadcast(selectedBroadcast, jsonResponse)) {
#ifdef _DEBUG
		blog(LOG_DEBUG, "Unable to found broadcast with id %s",
		     QT_TO_UTF8(selectedBroadcast));
#endif
		return false;
	}

	QString streamId = QString(jsonResponse["id"].string_value().c_str());
	stream.id = streamId;

	if (!stream.id.isEmpty()) {
		QString streamTitle =
			QString(jsonResponse["title"].string_value().c_str());
		stream.title = streamTitle;
		QString streamUrl = QString(jsonResponse["secure_stream_url"]
						    .string_value()
						    .c_str());
		stream.streamUrl = streamUrl;

		autoStop = false;
		apiFacebook->SetBroadcastId(selectedBroadcast);
	} else {
#ifdef _DEBUG
		blog(LOG_DEBUG,
		     "Empty Live Video ID received from Facebook Graph API.");
#endif
		return false;
	}

	return true;
}

void OBSFacebookActions::OpenFacebookDashboard()
{
	QDesktopServices::openUrl(QString(FACEBOOK_DASHBOARD_URL));
}

void OBSFacebookActions::Accept()
{
	workerThread->stop();
	accept();
}

void OBSFacebookActions::Cancel()
{
	workerThread->stop();
	reject();
}

OBSFacebookActions::~OBSFacebookActions()
{
	workerThread->stop();
	workerThread->wait();

	delete workerThread;
}

#pragma mark - FacebookApiThread

void FacebookApiThread::run()
{
	if (!pending)
		return;

	Json broadcastList;

	for (QString broadcastStatus : {"LIVE"}) {
		if (!apiFacebook->GetBroadcastList(broadcastList, "",
						   broadcastStatus)) {
			emit failed();
			return;
		}

		while (pending) {
			auto broadcastItems =
				broadcastList["data"].array_items();

			for (auto broadcast : broadcastItems) {
				QString title = QString::fromStdString(
					broadcast["title"].string_value());
				QString broadcastId = QString::fromStdString(
					broadcast["id"].string_value());

				emit new_item(title, broadcastId);
			}

			auto nextPageUrl =
				broadcastList["paging"]["next"].string_value();

			if (nextPageUrl.empty() || broadcastItems.empty()) {
				break;
			} else {
				if (!pending) {
					return;
				}

				if (!apiFacebook->GetBroadcastList(
					    broadcastList,
					    QString::fromStdString(nextPageUrl),
					    broadcastStatus)) {
					emit failed();
					return;
				}
			}
		}
	}

	emit ready();
}
