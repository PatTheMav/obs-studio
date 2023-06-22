#pragma once

#include <QDialog>
#include <QString>
#include <QThread>

#include "ui_OBSFacebookActions.h"
#include "facebook-api-wrappers.hpp"

class FacebookApiThread : public QThread {
	Q_OBJECT
public:
	FacebookApiThread(FacebookApiWrappers *apiFacebook)
		: QThread(), apiFacebook(apiFacebook)
	{
	}

	void stop() { pending = false; }

protected:
	FacebookApiWrappers *apiFacebook;
	bool pending = true;

public slots:
	void run() override;
signals:
	void ready();
	void new_item(const QString &title, const QString &broadcastId);
	void failed();
};

class OBSFacebookActions : public QDialog {
	Q_OBJECT

	std::unique_ptr<Ui::OBSFacebookActions> ui;

signals:
	void ok(const QString &streamId, const QString &streamUrl,
		bool autoStop, bool startNow);

protected:
	//	void showEvent(QShowEvent *event) override;

	//	void ShowErrorDialog(QWidget *parent, QString text);

public:
	// OLD
	explicit OBSFacebookActions(QWidget *parent, Auth *auth,
				    bool broadcastReady);
	//	void initUIDefaults();
	virtual ~OBSFacebookActions() override;

	bool Valid() { return valid; };

private:
	void CheckConfiguration();
	void ChangeChannel(int index);

	void StartBroadcast();
	void ScheduleBroadcast();
	bool CreateEvent(FacebookApiWrappers *api, FacebookStream &stream);
	bool SelectEvent(FacebookApiWrappers *api, FacebookStream &stream);

	QString selectedBroadcast;
	bool valid = false;
	bool broadcastReady = false;
	bool autoStop;

	FacebookApiWrappers *apiFacebook;
	FacebookApiThread *workerThread = nullptr;

	// OLD
	//	void ReadyBroadcast();
	//	void UiToLiveVideo(LiveVideo &liveVideo);
	void OpenFacebookDashboard();
	void Cancel();
	void Accept();
};
