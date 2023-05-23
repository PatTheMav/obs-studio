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
	void new_item(const QString &title);
	void failed();
};

class OBSFacebookActions : public QDialog {
	Q_OBJECT

	std::unique_ptr<Ui::OBSFacebookActions> ui;

signals:
	void ok(const QString &id, const QString &key);

protected:
	void showEvent(QShowEvent *event);

	void ShowErrorDialog(QWidget *parent, QString text);

public:
	explicit OBSFacebookActions(QWidget *parent, Auth *auth,
				    bool broadcastReady);
	void initUIDefaults();
	virtual ~OBSFacebookActions() override;

	bool Valid() { return valid; };

private:
	void InitBroadcast();
	void ReadyBroadcast();
	void UiToLiveVideo(LiveVideo &liveVideo);
	void OpenFacebookDashboard();
	void Cancel();
	void Accept();

	bool valid = false;
	FacebookApiWrappers *apiFacebook;
	FacebookApiThread *workerThread = nullptr;
	bool broadcastReady = false;
};
