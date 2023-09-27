#include "simulcast-settings-window.h"
#include "simulcast-dock-widget.h"

#include <QAction>
#include <QCheckBox>
#include <QDesktopServices>
#include <QDialogButtonBox>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QMainWindow>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QSpacerItem>
#include <QString>
#include <QVBoxLayout>

#include <obs-frontend-api.h>
#include <obs-module.h>

void register_settings_window(SimulcastDockWidget *dock,
			      obs_data_t *settings_config)
{
	auto action =
		static_cast<QAction *>(obs_frontend_add_tools_menu_qaction(
			obs_module_text("Settings.MenuName")));

	QMainWindow *window = (QMainWindow *)obs_frontend_get_main_window();

	obs_frontend_push_ui_translation(obs_module_get_string);
	auto settings =
		new SimulcastSettingsWindow(dock, window, settings_config);
	obs_frontend_pop_ui_translation();

	auto cb = [dock, settings]() {
		if (!settings->isVisible())
			settings->restoreGeometry(
				dock->SettingsWindowGeometry());
		settings->show();
		settings->setWindowState(settings->windowState() &
					 ~Qt::WindowMinimized);
		settings->activateWindow();
		settings->raise();
	};

	action->connect(action, &QAction::triggered, cb);

	dock->SetOpenSettingsAction(action);
}

SimulcastSettingsWindow::SimulcastSettingsWindow(SimulcastDockWidget *dock,
						 QWidget *parent,
						 obs_data_t *settings_config)
	: QDialog(parent),
	  dock_(dock)
{
	setWindowTitle(obs_module_text("Settings.WindowTitle"));

	auto get_stream_key_url =
		obs_data_has_user_value(settings_config, "get_stream_key_url")
			? QString{obs_data_get_string(settings_config,
						      "get_stream_key_url")}
			: QString{};

	auto window_layout = new QVBoxLayout(this);
	auto form_layout = new QFormLayout;

	if (obs_data_get_bool(settings_config, "override_rtmp_url"))
		rtmp_url_ = new QLineEdit;

	auto stream_key_edit_layout = new QHBoxLayout;
	stream_key_edit_ = new QLineEdit;
	stream_key_show_button_ = new QPushButton;
	auto get_stream_key_button =
		get_stream_key_url.isEmpty()
			? nullptr
			: new QPushButton(
				  obs_frontend_get_locale_string(
					  "Basic.AutoConfig.StreamPage.GetStreamKey"),
				  this);

	telemetry_checkbox_ =
		new QCheckBox(obs_module_text("Settings.EnableTelemetry"));

#ifdef ENABLE_CUSTOM_TWITCH_CONFIG
	use_server_config_ =
		new QCheckBox(obs_module_text("Settings.UseServerConfig"));
	custom_config_ = new QPlainTextEdit;
	auto custom_config_label =
		new QLabel(obs_module_text("Settings.CustomConfig"));
#endif

	// Allow button box to move to bottom of window, even when the window is resized
	auto stretch_spacer = new QSpacerItem(1, 1, QSizePolicy::Minimum,
					      QSizePolicy::MinimumExpanding);

	button_box_ = new QDialogButtonBox(
		QDialogButtonBox::Apply | QDialogButtonBox::Cancel |
		QDialogButtonBox::Ok | QDialogButtonBox::Reset);

	stream_key_edit_layout->addWidget(stream_key_edit_);
	stream_key_edit_layout->addWidget(stream_key_show_button_);
	if (get_stream_key_button) {
		stream_key_edit_layout->addWidget(get_stream_key_button);
	}

	if (rtmp_url_)
		form_layout->addRow(obs_module_text("Settings.RTMPURL"),
				    rtmp_url_);

	form_layout->addRow(obs_module_text("Settings.StreamKey"),
			    stream_key_edit_layout);
	form_layout->addRow("", telemetry_checkbox_);
#ifdef ENABLE_CUSTOM_TWITCH_CONFIG
	form_layout->addRow("", use_server_config_);
	form_layout->addRow(custom_config_label, custom_config_);
#endif
	form_layout->addItem(stretch_spacer);
	form_layout->addRow(button_box_);

	window_layout->addLayout(form_layout, 1);

	if (rtmp_url_)
		connect(rtmp_url_, &QLineEdit::textEdited,
			[=](const QString & /*text*/) {
				SetApplyEnabled(true);
			});

	connect(stream_key_edit_, &QLineEdit::textEdited,
		[=](const QString & /* text */) { SetApplyEnabled(true); });
	connect(stream_key_show_button_, &QPushButton::clicked,
		[=](bool /*toggled*/) {
			auto showing = stream_key_edit_->echoMode() ==
				       QLineEdit::Password;
			stream_key_edit_->setEchoMode(
				showing ? QLineEdit::Normal
					: QLineEdit::Password);
			stream_key_show_button_->setText(
				obs_frontend_get_locale_string(
					showing ? "Hide" : "Show"));
		});
	if (get_stream_key_button) {
		connect(get_stream_key_button, &QPushButton::clicked,
			[=](bool /*toggled*/) {
				QDesktopServices::openUrl(
					QUrl(get_stream_key_url));
			});
	}
	connect(telemetry_checkbox_, &QCheckBox::stateChanged,
		[=](int /*state*/) { SetApplyEnabled(true); });
#ifdef ENABLE_CUSTOM_TWITCH_CONFIG
	connect(use_server_config_, &QCheckBox::stateChanged,
		[=](int /*state*/) {
			SetApplyEnabled(true);
			custom_config_->setEnabled(
				!use_server_config_->isChecked());
			custom_config_label->setEnabled(
				!use_server_config_->isChecked());
		});
	connect(custom_config_, &QPlainTextEdit::textChanged,
		[=] { SetApplyEnabled(true); });
#endif
	connect(button_box_, &QDialogButtonBox::clicked,
		[=](QAbstractButton *button) { this->ButtonPressed(button); });

	connect(dock_, &SimulcastDockWidget::ProfileChanged,
		[=] { ResetSettings(); });

	connect(&dock_->Output(), &SimulcastOutput::StreamStarted, this,
		[=] { stream_key_edit_->setEnabled(false); });

	connect(&dock_->Output(), &SimulcastOutput::StreamStopped, this,
		[=] { stream_key_edit_->setEnabled(true); });

	ResetWindow();
	ResetSettings();
}

void SimulcastSettingsWindow::ButtonPressed(QAbstractButton *button)
{
	if (button == button_box_->button(QDialogButtonBox::Cancel)) {
		ResetWindow();
		ResetSettings();
		hide();
		return;
	}

	if (button == button_box_->button(QDialogButtonBox::Reset)) {
		ResetSettings();
		SetApplyEnabled(false);
		return;
	}

	// Handle individual settings here
	if (rtmp_url_)
		dock_->RTMPURL() = rtmp_url_->text();
	dock_->StreamKey() = stream_key_edit_->text();
	dock_->TelemetryEanbled() = telemetry_checkbox_->isChecked();
#ifdef ENABLE_CUSTOM_TWITCH_CONFIG
	dock_->UseServerConfig() = use_server_config_->isChecked();
	dock_->CustomConfig() = custom_config_->toPlainText();
#endif
	dock_->SettingsWindowGeometry() = saveGeometry();
	// Handle individual settings above

	SetApplyEnabled(false);

	dock_->SaveConfig();

	if (button == button_box_->button(QDialogButtonBox::Ok)) {
		ResetWindow();
		hide();
		return;
	}
}

void SimulcastSettingsWindow::SetApplyEnabled(bool enabled)
{
	button_box_->button(QDialogButtonBox::Apply)->setEnabled(enabled);
}

void SimulcastSettingsWindow::ResetWindow()
{
	stream_key_edit_->setEchoMode(QLineEdit::Password);
	stream_key_show_button_->setText(
		obs_frontend_get_locale_string("Show"));

	SetApplyEnabled(false);
}

void SimulcastSettingsWindow::ResetSettings()
{
	if (rtmp_url_)
		rtmp_url_->setText(dock_->RTMPURL());

	stream_key_edit_->setText(dock_->StreamKey());
	telemetry_checkbox_->setChecked(dock_->TelemetryEanbled());
#ifdef ENABLE_CUSTOM_TWITCH_CONFIG
	use_server_config_->setChecked(dock_->UseServerConfig());
	custom_config_->setPlainText(dock_->CustomConfig());
#endif

	SetApplyEnabled(false);
}