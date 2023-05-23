#include "window-basic-main.hpp"
#include "window-facebook-actions.hpp"

#include "obs-app.hpp"
#include "qt-wrappers.hpp"
#include "facebook-api-wrappers.hpp"

#include <QDateTime>
#include <QDesktopServices>

const QString SchedulDateAndTimeFormat = "yyyy-MM-dd'T'hh:mm:ss'Z'";
const QString RepresentSchedulDateAndTimeFormat = "dddd, MMMM d, yyyy h:m";

OBSFacebookActions::OBSFacebookActions(QWidget *parent, Auth *auth,
				       bool broadcastReady)
	: QDialog(parent),
	  ui(new Ui::OBSFacebookActions),
	  apiFacebook(dynamic_cast<FacebookApiWrappers *>(auth)),
	  workerThread(new FacebookApiThread(apiFacebook)),
	  broadcastReady(broadcastReady)
{
	if (!apiFacebook) {
		blog(LOG_DEBUG, "Facebook API auth NOT found.");
		Cancel();
		return;
	}

	setWindowFlags(windowFlags() & ~Qt::WindowContextHelpButtonHint);
	ui->setupUi(this);

	initUIDefaults();

	connect(ui->okButton, &QPushButton::clicked, this,
		&OBSFacebookActions::InitBroadcast);
	connect(ui->saveButton, &QPushButton::clicked, this,
		&OBSFacebookActions::ReadyBroadcast);
	connect(ui->pushButton, &QPushButton::clicked, this,
		&OBSFacebookActions::OpenFacebookDashboard);
	connect(ui->cancelButton, &QPushButton::clicked, this, [&]() {
		blog(LOG_DEBUG,
		     FACEBOOK_SECTION_NAME " broadcast creation cancelled.");
		// Close the dialog.
		Cancel();
	});

#ifdef __APPLE__
	// MacOS theming issues
	this->resize(this->width() + 200, this->height() + 120);
#endif
	valid = true;
}

void OBSFacebookActions::initUIDefaults()
{
	const char *name = config_get_string(OBSBasic::Get()->Config(),
					     FACEBOOK_SECTION_NAME,
					     FACEBOOK_USER_NAME);
	const char *id = config_get_string(OBSBasic::Get()->Config(),
					   FACEBOOK_SECTION_NAME,
					   FACEBOOK_USER_ID);

	this->setWindowTitle(QTStr("Facebook.Actions.WindowTitle").arg(name));

	ui->whereToPost->addItem(QTStr("Facebook.Actions.WhereToPost.User"),
				 "user");
	ui->whereToPost->addItem(QTStr("Facebook.Actions.WhereToPost.Page"),
				 "page");
	ui->whereToPost->addItem(QTStr("Facebook.Actions.WhereToPost.Group"),
				 "group");

	ui->whereToPostType->addItem(name, id);

	ui->whenLive->addItem(QTStr("Facebook.Actions.WhenLive.Now"), "now");
	ui->whenLive->addItem(QTStr("Facebook.Actions.WhenLive.Later"),
			      "later");

	ui->whenLiveDate->setDateTime(QDateTime::currentDateTime());
	//ui->whenLiveDate->setMinimumDateTime(now.addSecs(600));
	//ui->whenLiveDate->setMaximumDateTime(now.addDays(1));
	ui->whenLiveDate->setDisplayFormat(
		QLocale().dateTimeFormat(QLocale::ShortFormat));

	ui->audience->addItem(QTStr("Facebook.Actions.SelectAudience.Public"),
			      "public");
	ui->audience->addItem(QTStr("Facebook.Actions.SelectAudience.Friends"),
			      "friends");
	ui->audience->addItem(QTStr("Facebook.Actions.SelectAudience.OnlyMe"),
			      "onlyme");

	ui->streamLatency->addItem(
		QTStr("Facebook.StreamSetup.Latency.Settings.StreamLatency.Auto"),
		"auto");
	ui->streamLatency->addItem(
		QTStr("Facebook.StreamSetup.Latency.Settings.StreamLatency.Normal"),
		"normal");
	ui->streamLatency->addItem(
		QTStr("Facebook.StreamSetup.Latency.Settings.StreamLatency.LowLatency"),
		"low");
}

void OBSFacebookActions::showEvent(QShowEvent *event)
{
	QDialog::showEvent(event);
}

OBSFacebookActions::~OBSFacebookActions()
{
	workerThread->stop();
	workerThread->wait();

	delete workerThread;
}

void FacebookApiThread::run()
{
	if (!pending)
		return;

	emit ready();
}

void OBSFacebookActions::ShowErrorDialog(QWidget *parent, QString text)
{
	QMessageBox dlg(parent);
	dlg.setWindowFlags(dlg.windowFlags() & ~Qt::WindowCloseButtonHint);
	dlg.setWindowTitle(QTStr("Facebook.Actions.Error.Title"));
	dlg.setText(text);
	dlg.setTextFormat(Qt::RichText);
	dlg.setIcon(QMessageBox::Warning);
	dlg.setStandardButtons(QMessageBox::StandardButton::Ok);
	dlg.exec();
}

void OBSFacebookActions::InitBroadcast()
{
	blog(LOG_WARNING, "InitBroadcast");

	QString id = ui->whereToPostType->currentData().toString();
	LiveVideo lv;
	if (apiFacebook->GoLiveNow(lv, id)) {
		blog(LOG_WARNING, "DEU BOM");
		apiFacebook->SetDocksLiveVideoId(lv.video.id);
		emit ok(lv.id, lv.stream_url);
		Accept();
	} else {
		blog(LOG_WARNING, "DEU RUIM");
		apiFacebook->ResetDocks();
	}
}

void OBSFacebookActions::ReadyBroadcast()
{
	blog(LOG_WARNING, "ReadyBroadcast");
}

void OBSFacebookActions::UiToLiveVideo(LiveVideo &liveVideo)
{
	// do smth
}

void OBSFacebookActions::OpenFacebookDashboard()
{
	QDesktopServices::openUrl(QString(FACEBOOK_DASHBOARD_URL));
}

void OBSFacebookActions::Cancel()
{
	workerThread->stop();
	reject();
}

void OBSFacebookActions::Accept()
{
	workerThread->stop();
	accept();
}
