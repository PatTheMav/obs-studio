/******************************************************************************
 Copyright (C) 2023 by Lain Bailey <lain@obsproject.com>
 
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 2 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
 ******************************************************************************/

#pragma once

#include "ui_OBSBasic.h"

#include "OBSMainWindow.hpp"
#include <oauth/Auth.hpp>
#include <utility/platform.hpp>
#include <utility/undo_stack.hpp>
#include <utility/BasicOutputHandler.hpp>
#include <utility/VCamConfig.hpp>
#include <OBSApp.hpp>

#include <obs-frontend-internal.hpp>

#include <obs.hpp>
Q_DECLARE_METATYPE(OBSScene);
Q_DECLARE_METATYPE(OBSSceneItem);
Q_DECLARE_METATYPE(OBSSource);

#include <graphics/matrix4.h>
#include <util/platform.h>
#include <util/util.hpp>
#include <util/threading.h>

#include <QSystemTrayIcon>

#include <deque>

#define SIMPLE_ENCODER_X264 "x264"
#define SIMPLE_ENCODER_X264_LOWCPU "x264_lowcpu"
#define SIMPLE_ENCODER_QSV "qsv"
#define SIMPLE_ENCODER_QSV_AV1 "qsv_av1"
#define SIMPLE_ENCODER_NVENC "nvenc"
#define SIMPLE_ENCODER_NVENC_AV1 "nvenc_av1"
#define SIMPLE_ENCODER_NVENC_HEVC "nvenc_hevc"
#define SIMPLE_ENCODER_AMD "amd"
#define SIMPLE_ENCODER_AMD_HEVC "amd_hevc"
#define SIMPLE_ENCODER_AMD_AV1 "amd_av1"
#define SIMPLE_ENCODER_APPLE_H264 "apple_h264"
#define SIMPLE_ENCODER_APPLE_HEVC "apple_hevc"

#define DESKTOP_AUDIO_1 Str("DesktopAudioDevice1")
#define DESKTOP_AUDIO_2 Str("DesktopAudioDevice2")
#define AUX_AUDIO_1 Str("AuxAudioDevice1")
#define AUX_AUDIO_2 Str("AuxAudioDevice2")
#define AUX_AUDIO_3 Str("AuxAudioDevice3")
#define AUX_AUDIO_4 Str("AuxAudioDevice4")

#define PREVIEW_EDGE_SIZE 10

#define T_BAR_PRECISION 1024
#define T_BAR_PRECISION_F ((float)T_BAR_PRECISION)
#define T_BAR_CLAMP (T_BAR_PRECISION / 10)

#define STARTUP_SEPARATOR "==== Startup complete ==============================================="
#define SHUTDOWN_SEPARATOR "==== Shutting down =================================================="

extern volatile bool recording_paused;

class ColorSelect;
class OBSAbout;
class OBSBasicAdvAudio;
class OBSBasicFilters;
class OBSBasicInteraction;
class OBSBasicProperties;
class OBSBasicTransform;
class OBSLogViewer;
class OBSMissingFiles;
class OBSProjector;
class VolControl;
#ifdef YOUTUBE_ENABLED
class YouTubeAppDock;
#endif
class QMessageBox;
class QWidgetAction;
struct QuickTransition;

enum class ProjectorType;
enum class QtDataRole {
	OBSRef = Qt::UserRole,
	OBSSignals,
};

struct SavedProjectorInfo {
	ProjectorType type;
	int monitor;
	std::string geometry;
	std::string name;
	bool alwaysOnTop;
	bool alwaysOnTopOverridden;
};

struct SourceCopyInfo {
	OBSWeakSource weak_source;
	bool visible;
	obs_sceneitem_crop crop;
	obs_transform_info transform;
	obs_blending_method blend_method;
	obs_blending_type blend_mode;
};

struct OBSProfile {
	std::string name;
	std::string directoryName;
	std::filesystem::path path;
	std::filesystem::path profileFile;
};

struct OBSSceneCollection {
	std::string name;
	std::string fileName;
	std::filesystem::path collectionFile;
};

struct OBSPromptResult {
	bool success;
	std::string promptValue;
	bool optionValue;
};

struct OBSPromptRequest {
	std::string title;
	std::string prompt;
	std::string promptValue;
	bool withOption;
	std::string optionPrompt;
	bool optionValue;
};

using OBSPromptCallback = std::function<bool(const OBSPromptResult &result)>;

using OBSProfileCache = std::map<std::string, OBSProfile>;
using OBSSceneCollectionCache = std::map<std::string, OBSSceneCollection>;

static inline void LogFilter(obs_source_t *, obs_source_t *filter, void *v_val)
{
	const char *name = obs_source_get_name(filter);
	const char *id = obs_source_get_id(filter);
	int val = (int)(intptr_t)v_val;
	std::string indent;

	for (int i = 0; i < val; i++)
		indent += "    ";

	blog(LOG_INFO, "%s- filter: '%s' (%s)", indent.c_str(), name, id);
}

static void GetItemBox(obs_sceneitem_t *item, vec3 &tl, vec3 &br)
{
	matrix4 boxTransform;
	obs_sceneitem_get_box_transform(item, &boxTransform);

	vec3_set(&tl, M_INFINITE, M_INFINITE, 0.0f);
	vec3_set(&br, -M_INFINITE, -M_INFINITE, 0.0f);

	auto GetMinPos = [&](float x, float y) {
		vec3 pos;
		vec3_set(&pos, x, y, 0.0f);
		vec3_transform(&pos, &pos, &boxTransform);
		vec3_min(&tl, &tl, &pos);
		vec3_max(&br, &br, &pos);
	};

	GetMinPos(0.0f, 0.0f);
	GetMinPos(1.0f, 0.0f);
	GetMinPos(0.0f, 1.0f);
	GetMinPos(1.0f, 1.0f);
}

static vec3 GetItemTL(obs_sceneitem_t *item)
{
	vec3 tl, br;
	GetItemBox(item, tl, br);
	return tl;
}

static void SetItemTL(obs_sceneitem_t *item, const vec3 &tl)
{
	vec3 newTL;
	vec2 pos;

	obs_sceneitem_get_pos(item, &pos);
	newTL = GetItemTL(item);
	pos.x += tl.x - newTL.x;
	pos.y += tl.y - newTL.y;
	obs_sceneitem_set_pos(item, &pos);
}

static inline bool SourceMixerHidden(obs_source_t *source)
{
	OBSDataAutoRelease priv_settings = obs_source_get_private_settings(source);
	bool hidden = obs_data_get_bool(priv_settings, "mixer_hidden");

	return hidden;
}

static inline void SetSourceMixerHidden(obs_source_t *source, bool hidden)
{
	OBSDataAutoRelease priv_settings = obs_source_get_private_settings(source);
	obs_data_set_bool(priv_settings, "mixer_hidden", hidden);
}

static inline OBSSource GetTransitionComboItem(QComboBox *combo, int idx)
{
	return combo->itemData(idx).value<OBSSource>();
}

static inline bool SourceVolumeLocked(obs_source_t *source)
{
	OBSDataAutoRelease priv_settings = obs_source_get_private_settings(source);
	bool lock = obs_data_get_bool(priv_settings, "volume_locked");

	return lock;
}

#ifdef _WIN32
static inline void UpdateProcessPriority()
{
	const char *priority = config_get_string(App()->GetAppConfig(), "General", "ProcessPriority");
	if (priority && strcmp(priority, "Normal") != 0)
		SetProcessPriority(priority);
}

static inline void ClearProcessPriority()
{
	const char *priority = config_get_string(App()->GetAppConfig(), "General", "ProcessPriority");
	if (priority && strcmp(priority, "Normal") != 0)
		SetProcessPriority("Normal");
}
#else
#define UpdateProcessPriority() \
	do {                    \
	} while (false)
#define ClearProcessPriority() \
	do {                   \
	} while (false)
#endif

static inline QColor color_from_int(long long val)
{
	return QColor(val & 0xff, (val >> 8) & 0xff, (val >> 16) & 0xff, (val >> 24) & 0xff);
}

template<typename T> static T GetOBSRef(QListWidgetItem *item)
{
	return item->data(static_cast<int>(QtDataRole::OBSRef)).value<T>();
}

template<typename T> static void SetOBSRef(QListWidgetItem *item, T &&val)
{
	item->setData(static_cast<int>(QtDataRole::OBSRef), QVariant::fromValue(val));
}

class OBSBasic : public OBSMainWindow {
	Q_OBJECT

	Q_PROPERTY(QIcon imageIcon READ GetImageIcon WRITE SetImageIcon DESIGNABLE true)
	Q_PROPERTY(QIcon colorIcon READ GetColorIcon WRITE SetColorIcon DESIGNABLE true)
	Q_PROPERTY(QIcon slideshowIcon READ GetSlideshowIcon WRITE SetSlideshowIcon DESIGNABLE true)
	Q_PROPERTY(QIcon audioInputIcon READ GetAudioInputIcon WRITE SetAudioInputIcon DESIGNABLE true)
	Q_PROPERTY(QIcon audioOutputIcon READ GetAudioOutputIcon WRITE SetAudioOutputIcon DESIGNABLE true)
	Q_PROPERTY(QIcon desktopCapIcon READ GetDesktopCapIcon WRITE SetDesktopCapIcon DESIGNABLE true)
	Q_PROPERTY(QIcon windowCapIcon READ GetWindowCapIcon WRITE SetWindowCapIcon DESIGNABLE true)
	Q_PROPERTY(QIcon gameCapIcon READ GetGameCapIcon WRITE SetGameCapIcon DESIGNABLE true)
	Q_PROPERTY(QIcon cameraIcon READ GetCameraIcon WRITE SetCameraIcon DESIGNABLE true)
	Q_PROPERTY(QIcon textIcon READ GetTextIcon WRITE SetTextIcon DESIGNABLE true)
	Q_PROPERTY(QIcon mediaIcon READ GetMediaIcon WRITE SetMediaIcon DESIGNABLE true)
	Q_PROPERTY(QIcon browserIcon READ GetBrowserIcon WRITE SetBrowserIcon DESIGNABLE true)
	Q_PROPERTY(QIcon groupIcon READ GetGroupIcon WRITE SetGroupIcon DESIGNABLE true)
	Q_PROPERTY(QIcon sceneIcon READ GetSceneIcon WRITE SetSceneIcon DESIGNABLE true)
	Q_PROPERTY(QIcon defaultIcon READ GetDefaultIcon WRITE SetDefaultIcon DESIGNABLE true)
	Q_PROPERTY(QIcon audioProcessOutputIcon READ GetAudioProcessOutputIcon WRITE SetAudioProcessOutputIcon
			   DESIGNABLE true)

	// TODO: Make affected member variables and methods either public or wrap in public getter functions
	friend struct BasicOutputHandler;
	friend struct OBSStudioAPI;

	friend class Auth;
	friend class AutoConfig;
	friend class AutoConfigStreamPage;
	friend class ExtraBrowsersModel;
	friend class OBSAbout;
	friend class OBSBasicPreview;
	friend class OBSBasicSettings;
	friend class OBSBasicSourceSelect;
	friend class OBSBasicStatusBar;
	friend class OBSProjector;
	friend class OBSYoutubeActions;
	friend class ScreenshotObj;

	enum class CenterType {
		Scene,
		Vertical,
		Horizontal,
	};

	enum DropType {
		DropType_RawText,
		DropType_Text,
		DropType_Image,
		DropType_Media,
		DropType_Html,
		DropType_Url,
	};

	enum ContextBarSize { ContextBarSize_Minimized, ContextBarSize_Reduced, ContextBarSize_Normal };

	enum class MoveDir { Up, Down, Left, Right };

	/* --------------------------
     * MARK: - General
     * --------------------------
     */
private:
	std::vector<OBSSignal> signalHandlers;
	std::unique_ptr<Ui::OBSBasic> ui;
	ConfigFile activeConfiguration;

	QScopedPointer<QThread> patronJsonThread;
	std::string patronJson;

	QScopedPointer<QThread> logUploadThread;

	obs_frontend_callbacks *api = nullptr;

	bool loaded = false;
	bool closing = false;

	void InitOBSCallbacks();

	void OnFirstLoad();
	bool InitBasicConfig();
	bool InitBasicConfigDefaults();
	void InitBasicConfigDefaults2();

	void ClearContextBar();
	void ClearVolumeControls();
	void CloseDialogs();

	void GetFPSCommon(uint32_t &num, uint32_t &den) const;
	void GetFPSInteger(uint32_t &num, uint32_t &den) const;
	void GetFPSFraction(uint32_t &num, uint32_t &den) const;
	void GetFPSNanoseconds(uint32_t &num, uint32_t &den) const;
	void GetConfigFPS(uint32_t &num, uint32_t &den) const;

	void EnumDialogs();
	void SetDisplayAffinity(QWindow *window);

	OBSPromptResult PromptForName(const OBSPromptRequest &request, const OBSPromptCallback &callback);

	// TODO: Unused thread pointer, remove.
	QScopedPointer<QThread> devicePropertiesThread;
	// TODO: Remove, orphaned variable
	bool copyVisible = true;

protected:
	virtual void closeEvent(QCloseEvent *event) override;
	virtual bool nativeEvent(const QByteArray &eventType, void *message, qintptr *result) override;
	virtual void changeEvent(QEvent *event) override;

public:
	undo_stack undo_s;

	explicit OBSBasic(QWidget *parent = 0);
	virtual ~OBSBasic();

	virtual void OBSInit() override;

	static OBSBasic *Get();

	virtual config_t *Config() const override;

	void OnEvent(enum obs_frontend_event event);

	inline bool Closing() { return closing; }

	void UpdateTitleBar();

	int ResetVideo();
	bool ResetAudio();

	void CreatePropertiesWindow(obs_source_t *source);

	void CreateSceneUndoRedoAction(const QString &action_name, OBSData undo_data, OBSData redo_data);
public slots:
	void UpdateEditMenu();

	void UpdatePatronJson(const QString &text, const QString &error);

	/* --------------------------
     * MARK: - OAuth
     * --------------------------
     */
private:
	std::shared_ptr<Auth> auth;

public:
	inline Auth *GetAuth() { return auth.get(); }

	/* --------------------------
     * MARK: - OBSBasic+Browser
     * --------------------------
     */
private:
	QPointer<QWidget> extraBrowsers;

	QList<std::shared_ptr<QDockWidget>> extraBrowserDocks;

	QPointer<QAction> extraBrowserMenuDocksSeparator;

	QStringList extraBrowserDockNames;
	QStringList extraBrowserDockTargets;

#ifdef BROWSER_AVAILABLE
	void ManageExtraBrowserDocks();
	void AddExtraBrowserDock(const QString &title, const QString &url, const QString &uuid, bool firstCreate);
	void LoadExtraBrowserDocks();
	void SaveExtraBrowserDocks();
	void ClearExtraBrowserDocks();
#endif
public:
	static void InitBrowserPanelSafeBlock();

	/* --------------------------
     * MARK: - OBSBasic+Clipboard
     * --------------------------
     */
private:
	std::deque<SourceCopyInfo> clipboard;

	OBSWeakSourceAutoRelease copySourceTransition;
	OBSWeakSourceAutoRelease copyFiltersSource;
	obs_transform_info copiedTransformInfo;
	obs_sceneitem_crop copiedCropInfo;

	int copySourceTransitionDuration;

	bool hasCopiedTransform = false;

	void PasteShowHideTransition(obs_sceneitem_t *item, bool show, obs_source_t *tr, int duration);

public:
	OBSWeakSource copyFilter;

	void CreateFilterPasteUndoRedoAction(const QString &text, obs_source_t *source, obs_data_array_t *undo_array,
					     obs_data_array_t *redo_array);

private slots:
	void AudioMixerCopyFilters();
	void AudioMixerPasteFilters();

	void SourcePasteFilters(OBSSource source, OBSSource dstSource);

	void SceneCopyFilters();
	void ScenePasteFilters();

	void on_actionCopySource_triggered();
	void on_actionPasteRef_triggered();
	void on_actionPasteDup_triggered();

	void on_actionCopyFilters_triggered();
	void on_actionPasteFilters_triggered();

	void on_actionCopyTransform_triggered();
	void on_actionPasteTransform_triggered();

	/* --------------------------
     * MARK: - OBSBasic+ContextToolbar
     * --------------------------
     */
private:
	ContextBarSize contextBarSize = ContextBarSize_Normal;

	void SourceToolBarActionsSetEnabled();
	void copyActionsDynamicProperties();

private slots:
	void ShowContextBar();
	void HideContextBar();
	void UpdateContextBarVisibility();

	void on_toggleContextBar_toggled(bool visible);

public slots:
	void UpdateContextBar(bool force = false);
	void UpdateContextBarDeferred(bool force = false);

	/* --------------------------
     * MARK: - OBSBasic+Docks
     * --------------------------
     */
private:
	QPointer<OBSDock> controlsDock;
	QPointer<QDockWidget> statsDock;

	QList<std::shared_ptr<QDockWidget>> extraDocks;
	QStringList extraDockNames;

	QList<QPointer<QDockWidget>> oldExtraDocks;
	QStringList oldExtraDockNames;

	QList<QPointer<QDockWidget>> extraCustomDocks;
	QStringList extraCustomDockNames;

	QByteArray startingDockLayout;

public:
	QAction *AddDockWidget(QDockWidget *dock);
	void AddDockWidget(QDockWidget *dock, Qt::DockWidgetArea area, bool extraBrowser = false);
	void AddCustomDockWidget(QDockWidget *dock);

	void RemoveDockWidget(const QString &name);

	bool IsDockObjectNameUsed(const QString &name);

private slots:
	void RepairCustomExtraDockName();
	void RepairOldExtraDockName();

	void on_resetDocks_triggered(bool force = false);
	void on_lockDocks_toggled(bool lock);
	void on_sideDocks_toggled(bool side);

	/* --------------------------
     * MARK: - OBSBasic+Dropfiles
     * --------------------------
     */
private:
	void AddDropSource(const char *file, DropType image);
	void AddDropURL(const char *url, QString &name, obs_data_t *settings, const obs_video_info &ovi);

	void ConfirmDropUrl(const QString &url);

	void dragEnterEvent(QDragEnterEvent *event) override;
	void dragLeaveEvent(QDragLeaveEvent *event) override;
	void dragMoveEvent(QDragMoveEvent *event) override;
	void dropEvent(QDropEvent *event) override;

	/* --------------------------
     * MARK: - OBSBasic+Hotkeys
     * --------------------------
     */
private:
	obs_hotkey_id statsHotkey = 0;
	obs_hotkey_pair_id togglePreviewHotkeys;
	obs_hotkey_pair_id contextBarHotkeys;

	QPointer<QObject> shortcutFilter;

	void InitHotkeys();
	void CreateHotkeys();
	void ClearHotkeys();

	static void HotkeyTriggered(void *data, obs_hotkey_id id, bool pressed);
private slots:
	void ProcessHotkey(obs_hotkey_id id, bool pressed);
	void ResetStatsHotkey();

	/* --------------------------
     * MARK: - OBSBasic+Icons
     * --------------------------
     */
private:
	QIcon imageIcon;
	QIcon colorIcon;
	QIcon slideshowIcon;
	QIcon audioInputIcon;
	QIcon audioOutputIcon;
	QIcon desktopCapIcon;
	QIcon windowCapIcon;
	QIcon gameCapIcon;
	QIcon cameraIcon;
	QIcon textIcon;
	QIcon mediaIcon;
	QIcon browserIcon;
	QIcon groupIcon;
	QIcon sceneIcon;
	QIcon defaultIcon;
	QIcon audioProcessOutputIcon;

	QIcon GetImageIcon() const;
	QIcon GetColorIcon() const;
	QIcon GetSlideshowIcon() const;
	QIcon GetAudioInputIcon() const;
	QIcon GetAudioOutputIcon() const;
	QIcon GetDesktopCapIcon() const;
	QIcon GetWindowCapIcon() const;
	QIcon GetGameCapIcon() const;
	QIcon GetCameraIcon() const;
	QIcon GetTextIcon() const;
	QIcon GetMediaIcon() const;
	QIcon GetBrowserIcon() const;
	QIcon GetDefaultIcon() const;
	QIcon GetAudioProcessOutputIcon() const;

private slots:
	void SetImageIcon(const QIcon &icon);
	void SetColorIcon(const QIcon &icon);
	void SetSlideshowIcon(const QIcon &icon);
	void SetAudioInputIcon(const QIcon &icon);
	void SetAudioOutputIcon(const QIcon &icon);
	void SetDesktopCapIcon(const QIcon &icon);
	void SetWindowCapIcon(const QIcon &icon);
	void SetGameCapIcon(const QIcon &icon);
	void SetCameraIcon(const QIcon &icon);
	void SetTextIcon(const QIcon &icon);
	void SetMediaIcon(const QIcon &icon);
	void SetBrowserIcon(const QIcon &icon);
	void SetGroupIcon(const QIcon &icon);
	void SetSceneIcon(const QIcon &icon);
	void SetDefaultIcon(const QIcon &icon);
	void SetAudioProcessOutputIcon(const QIcon &icon);

public:
	QIcon GetSourceIcon(const char *id) const;
	QIcon GetGroupIcon() const;
	QIcon GetSceneIcon() const;

	/* --------------------------
     * MARK: - OBSBasic+MainControls
     * --------------------------
     */
private:
	QList<QDialog *> visDialogs;
	QList<QDialog *> modalDialogs;
	QList<QMessageBox *> visMsgBoxes;
	QList<QPoint> visDlgPositions;

	QPointer<OBSBasicProperties> properties;
	QPointer<OBSBasicFilters> filters;
	QPointer<QWidget> stats;
	QPointer<QWidget> remux;
	QPointer<OBSAbout> about;
	QPointer<OBSBasicInteraction> interaction;
	QPointer<OBSBasicTransform> transformWindow;
	QPointer<OBSBasicAdvAudio> advAudioWindow;
	QPointer<ColorSelect> colorSelect;
	QPointer<QWidget> importer;
	QPointer<OBSLogViewer> logView;

	QPointer<QMenu> scaleFilteringMenu;
	QPointer<QMenu> blendingMethodMenu;
	QPointer<QMenu> blendingModeMenu;
	QPointer<QMenu> colorMenu;
	QPointer<QMenu> deinterlaceMenu;

	QPointer<QWidgetAction> colorWidgetAction;
	QPointer<QAction> showHide;
	QPointer<QAction> exit;

	void UploadLog(const char *subdir, const char *file, const bool crash);

public:
	void ResetUI();

	void CreateFiltersWindow(obs_source_t *source);
	void CreateInteractionWindow(obs_source_t *source);
	void CreateEditTransformWindow(obs_sceneitem_t *item);
private slots:
	void ToggleShowHide();
	void ToggleAlwaysOnTop();
	void SetShowing(bool showing);

	void logUploadFinished(const QString &text, const QString &error);
	void crashUploadFinished(const QString &text, const QString &error);
	void openLogDialog(const QString &text, const bool crash);
	void updateCheckFinished();

	void on_stats_triggered();
	void on_autoConfigure_triggered();
	void on_resetUI_triggered();

	void on_toggleListboxToolbars_toggled(bool visible);
	void on_toggleStatusBar_toggled(bool visible);

	void on_actionFullscreenInterface_triggered();
	void on_actionShowAbout_triggered();
	void on_actionViewCurrentLog_triggered();
	void on_actionRemux_triggered();
	void on_actionShowMacPermissions_triggered();
	void on_actionAdvAudioProperties_triggered();
	void on_actionShowLogs_triggered();
	void on_actionUploadCurrentLog_triggered();
	void on_actionUploadLastLog_triggered();
	void on_actionCheckForUpdates_triggered();
	void on_actionRepair_triggered();
	void on_actionShowWhatsNew_triggered();
	void on_actionRestartSafe_triggered();
	void on_actionShowCrashLogs_triggered();
	void on_actionUploadLastCrashLog_triggered();
	void on_actionHelpPortal_triggered();
	void on_actionWebsite_triggered();
	void on_actionDiscord_triggered();
	void on_actionReleaseNotes_triggered();
	void on_actionShowSettingsFolder_triggered();
	void on_actionShowProfileFolder_triggered();
	void on_actionAlwaysOnTop_triggered();
	void on_action_Settings_triggered();
	void on_actionMainUndo_triggered();
	void on_actionMainRedo_triggered();

	void on_OBSBasic_customContextMenuRequested(const QPoint &pos);

	/* --------------------------
     * MARK: - OBSBasic+OutputHandler
     * --------------------------
     */
private:
	std::unique_ptr<BasicOutputHandler> outputHandler;

	std::optional<std::pair<uint32_t, uint32_t>> lastOutputResolution;

	int disableOutputsRef = 0;

	inline void OnActivate(bool force = false)
	{
		if (ui->profileMenu->isEnabled() || force) {
			ui->profileMenu->setEnabled(false);
			ui->autoConfigure->setEnabled(false);
			App()->IncrementSleepInhibition();
			UpdateProcessPriority();

			struct obs_video_info ovi;
			obs_get_video_info(&ovi);
			lastOutputResolution = {ovi.base_width, ovi.base_height};

			TaskbarOverlaySetStatus(TaskbarOverlayStatusActive);
			if (trayIcon && trayIcon->isVisible()) {
#ifdef __APPLE__
				QIcon trayMask = QIcon(":/res/images/tray_active_macos.svg");
				trayMask.setIsMask(true);
				trayIcon->setIcon(QIcon::fromTheme("obs-tray", trayMask));
#else
				trayIcon->setIcon(
					QIcon::fromTheme("obs-tray-active", QIcon(":/res/images/tray_active.png")));
#endif
			}
		}
	}

	inline void OnDeactivate()
	{
		if (!outputHandler->Active() && !ui->profileMenu->isEnabled()) {
			ui->profileMenu->setEnabled(true);
			ui->autoConfigure->setEnabled(true);
			App()->DecrementSleepInhibition();
			ClearProcessPriority();

			TaskbarOverlaySetStatus(TaskbarOverlayStatusInactive);
			if (trayIcon && trayIcon->isVisible()) {
#ifdef __APPLE__
				QIcon trayIconFile = QIcon(":/res/images/obs_macos.svg");
				trayIconFile.setIsMask(true);
#else
				QIcon trayIconFile = QIcon(":/res/images/obs.png");
#endif
				trayIcon->setIcon(QIcon::fromTheme("obs-tray", trayIconFile));
			}
		} else if (outputHandler->Active() && trayIcon && trayIcon->isVisible()) {
			if (os_atomic_load_bool(&recording_paused)) {
#ifdef __APPLE__
				QIcon trayIconFile = QIcon(":/res/images/obs_paused_macos.svg");
				trayIconFile.setIsMask(true);
#else
				QIcon trayIconFile = QIcon(":/res/images/obs_paused.png");
#endif
				trayIcon->setIcon(QIcon::fromTheme("obs-tray-paused", trayIconFile));
				TaskbarOverlaySetStatus(TaskbarOverlayStatusPaused);
			} else {
#ifdef __APPLE__
				QIcon trayIconFile = QIcon(":/res/images/tray_active_macos.svg");
				trayIconFile.setIsMask(true);
#else
				QIcon trayIconFile = QIcon(":/res/images/tray_active.png");
#endif
				trayIcon->setIcon(QIcon::fromTheme("obs-tray-active", trayIconFile));
				TaskbarOverlaySetStatus(TaskbarOverlayStatusActive);
			}
		}
	}

	bool OutputPathValid();
	void OutputPathInvalidMessage();

	bool IsFFmpegOutputToURL() const;

	// TODO: Unimplemented, remove.
	void SetupEncoders();
	// TODO: Unimplemented, remove.
	void TempFileOutput(const char *path, int vBitrate, int aBitrate);
	// TODO: Unimplemented, remove.
	void TempStreamOutput(const char *url, const char *key, int vBitrate, int aBitrate);

public:
	inline void EnableOutputs(bool enable)
	{
		if (enable) {
			if (--disableOutputsRef < 0)
				disableOutputsRef = 0;
		} else {
			disableOutputsRef++;
		}
	}

	bool Active() const;
	const char *GetCurrentOutputPath();

	void ResetOutputs();

private slots:
	void ResizeOutputSizeOfSource();

	/* --------------------------
     * MARK: - OBSBasic+Preview
     * --------------------------
     */
private:
	QColor selectionColor;
	QColor cropColor;
	QColor hoverColor;

	bool previewEnabled = true;
	float previewScale = 0.0f;

	bool drawSafeAreas = false;
	bool drawSpacingHelpers = true;

	int previewX = 0;
	int previewY = 0;
	int previewCX = 0;
	int previewCY = 0;
	float dpi = 1.0;

	gs_vertbuffer_t *box = nullptr;
	gs_vertbuffer_t *boxLeft = nullptr;
	gs_vertbuffer_t *boxTop = nullptr;
	gs_vertbuffer_t *boxRight = nullptr;
	gs_vertbuffer_t *boxBottom = nullptr;
	gs_vertbuffer_t *circle = nullptr;

	gs_vertbuffer_t *actionSafeMargin = nullptr;
	gs_vertbuffer_t *graphicsSafeMargin = nullptr;
	gs_vertbuffer_t *fourByThreeSafeMargin = nullptr;
	gs_vertbuffer_t *leftLine = nullptr;
	gs_vertbuffer_t *topLine = nullptr;
	gs_vertbuffer_t *rightLine = nullptr;

	QPointer<QTimer> nudge_timer;
	bool recent_nudge = false;
	void Nudge(int dist, MoveDir dir);

	float GetDevicePixelRatio();
	QColor GetCropColor() const;
	QColor GetHoverColor() const;

	void ResizePreview(uint32_t cx, uint32_t cy);

	void UpdatePreviewSafeAreas();
	void UpdatePreviewSpacingHelpers();
	void UpdatePreviewOverflowSettings();
	void UpdatePreviewScalingMenu();
	void UpdatePreviewScrollbars();
	void UpdateProjectorHideCursor();
	void UpdateProjectorAlwaysOnTop(bool top);

	void InitPrimitives();

	void DrawBackdrop(float cx, float cy);
	static void RenderMain(void *data, uint32_t cx, uint32_t cy);

private slots:
	void EnablePreview();
	void DisablePreview();
	void ColorChange();

	void PreviewScalingModeChanged(int value);

	void on_actionLockPreview_triggered();
	void on_scalingMenu_aboutToShow();
	void on_actionScaleWindow_triggered();
	void on_actionScaleCanvas_triggered();
	void on_actionScaleOutput_triggered();

	void on_previewXScrollBar_valueChanged(int value);
	void on_previewYScrollBar_valueChanged(int value);

	void on_preview_customContextMenuRequested();
	void on_previewDisabledWidget_customContextMenuRequested();

public:
	void TogglePreview();
	void EnablePreviewDisplay(bool enable);

	QColor GetSelectionColor() const;
	inline void GetDisplayRect(int &x, int &y, int &cx, int &cy)
	{
		x = previewX;
		y = previewY;
		cx = previewCX;
		cy = previewCY;
	}

signals:
	void CanvasResized(uint32_t width, uint32_t height);
	void OutputResized(uint32_t width, uint32_t height);

	void PreviewXScrollBarMoved(int value);
	void PreviewYScrollBarMoved(int value);

	/* --------------------------
     * MARK: - OBSBasic+Profiles
     * --------------------------
     */
private:
	OBSProfileCache profiles{};

	void SetupNewProfile(const std::string &profileName, bool useWizard = false);
	void SetupDuplicateProfile(const std::string &profileName);
	void SetupRenameProfile(const std::string &profileName);

	const OBSProfile &CreateProfile(const std::string &profileName);
	void RemoveProfile(OBSProfile profile);

	void ChangeProfile();

	void RefreshProfileCache();

	void RefreshProfiles(bool refreshCache = false);

	void ActivateProfile(const OBSProfile &profile, bool reset = false);
	std::vector<std::string> GetRestartRequirements(const ConfigFile &config) const;
	void ResetProfileData();
	void CheckForSimpleModeX264Fallback();

public:
	inline const OBSProfileCache &GetProfileCache() const noexcept { return profiles; };

	const OBSProfile &GetCurrentProfile() const;

	std::optional<OBSProfile> GetProfileByName(const std::string &profileName) const;
	std::optional<OBSProfile> GetProfileByDirectoryName(const std::string &directoryName) const;

private slots:
	void on_actionNewProfile_triggered();
	void on_actionDupProfile_triggered();
	void on_actionRenameProfile_triggered();
	void on_actionRemoveProfile_triggered(bool skipConfirmation = false);
	void on_actionImportProfile_triggered();
	void on_actionExportProfile_triggered();

public slots:
	bool CreateNewProfile(const QString &name);
	bool CreateDuplicateProfile(const QString &name);
	void DeleteProfile(const QString &profileName);

	/* --------------------------
     * MARK: - OBSBasic+Projectors
     * --------------------------
     */
private:
	std::vector<SavedProjectorInfo *> savedProjectorsArray;
	std::vector<OBSProjector *> projectors;

	QPointer<QMenu> previewProjector;
	QPointer<QMenu> previewProjectorSource;
	QPointer<QMenu> previewProjectorMain;

	OBSProjector *OpenProjector(obs_source_t *source, int monitor, ProjectorType type);
	obs_data_array_t *SaveProjectors();
	void LoadSavedProjectors(obs_data_array_t *savedProjectors);
	void DeleteProjector(OBSProjector *projector);
	void ClearProjectors();

	void UpdateMultiviewProjectorMenu();

public:
	void OpenSavedProjectors();
	void OpenMultiviewProjector();
	void OpenPreviewProjector();

	static QList<QString> GetProjectorMenuMonitorsFormatted();

	/// Class method to add values from `GetProjectorMenuMonitorsFormatted` as items to a `QMenu` instance
	template<typename Receiver, typename... Args>
	static void AddProjectorMenuMonitors(QMenu *parent, Receiver *target, void (Receiver::*slot)(Args...))
	{
		auto projectors = GetProjectorMenuMonitorsFormatted();
		for (int i = 0; i < projectors.size(); i++) {
			QString str = projectors[i];
			QAction *action = parent->addAction(str, target, slot);
			action->setProperty("monitor", i);
		}
	}

	void ResetProjectors();

private slots:
	void OpenSavedProjector(SavedProjectorInfo *info);
	void OpenSourceProjector();
	void OpenSceneProjector();
	void OpenPreviewWindow();
	void OpenSourceWindow();
	void OpenSceneWindow();

	void on_multiviewProjectorWindowed_triggered();

	/* --------------------------
     * MARK: - OBSBasic+Recording
     * --------------------------
     */
private:
	obs_hotkey_pair_id recordingHotkeys;
	obs_hotkey_pair_id pauseHotkeys;
	obs_hotkey_id splitFileHotkey;
	obs_hotkey_id addChapterHotkey;

	QPointer<QTimer> diskFullTimer;

	bool recordingStarted = false;
	bool isRecordingPausable = false;
	bool recordingPaused = false;
	bool recordingStopping = false;

	void AutoRemux(QString input, bool no_show = false);
	void DiskSpaceMessage();
	bool LowDiskSpace();
	void UpdateIsRecordingPausable();

private slots:
	void RecordActionTriggered();
	void RecordPauseToggled();
	void CheckDiskSpaceRemaining();

	void on_actionShow_Recordings_triggered();

public slots:
	void StartRecording();
	bool RecordingActive();
	void PauseRecording();
	void UnpauseRecording();
	void StopRecording();

	void RecordingStart();
	void RecordStopping();
	void RecordingStop(int code, QString last_error);
	void RecordingFileChanged(QString lastRecordingPath);
signals:
	void RecordingStarted(bool pausable = false);
	void RecordingPaused();
	void RecordingUnpaused();
	void RecordingStopping();
	void RecordingStopped();

	/* --------------------------
     * MARK: - OBSBasic+ReplayBuffer
     * --------------------------
     */
private:
	std::string lastReplay;

	obs_hotkey_pair_id replayBufHotkeys;

	bool replayBufferStopping = false;

private slots:
	void ReplayBufferActionTriggered();

public slots:
	void ReplayBufferStart();
	bool ReplayBufferActive();
	void ReplayBufferSaved();
	void ReplayBufferStopping();
	void ReplayBufferStop(int code);

	void StartReplayBuffer();
	void StopReplayBuffer();
	void ReplayBufferSave();
	void ShowReplayBufferPauseWarning();

signals:
	void ReplayBufEnabled(bool enabled);
	void ReplayBufStarted();
	void ReplayBufStopping();
	void ReplayBufStopped();

	/* --------------------------
     * MARK: - OBSBasic+SceneCollections
     * --------------------------
     */
private:
	OBSDataAutoRelease collectionModuleData;
	QPointer<OBSMissingFiles> missDialog;
	std::optional<std::pair<uint32_t, uint32_t>> migrationBaseResolution;

	bool projectChanged = false;
	long disableSaving = 1;
	bool clearingFailed = false;
	bool usingAbsoluteCoordinates = false;

	OBSSceneCollectionCache collections{};

	void ShowMissingFilesDialog(obs_missing_files_t *files);

	void CreateDefaultScene(bool firstStart);

	void SaveProjectNow();

	void ClearSceneData();

	void Load(const char *file, bool remigrate = false);
	void LoadData(obs_data_t *data, const char *file, bool remigrate = false);
	void Save(const char *file);

	void LoadSceneListOrder(obs_data_array_t *array);

	void LogScenes();

	void DisableRelativeCoordinates(bool disable);

	void SetupNewSceneCollection(const std::string &collectionName);
	void SetupDuplicateSceneCollection(const std::string &collectionName);
	void SetupRenameSceneCollection(const std::string &collectionName);

	const OBSSceneCollection &CreateSceneCollection(const std::string &collectionName);
	void RemoveSceneCollection(OBSSceneCollection collection);

	bool CreateDuplicateSceneCollection(const QString &name);
	void DeleteSceneCollection(const QString &name);
	void ChangeSceneCollection();

	void RefreshSceneCollectionCache();

	void RefreshSceneCollections(bool refreshCache = false);
	void ActivateSceneCollection(const OBSSceneCollection &collection);

public:
	inline bool SavingDisabled() const { return disableSaving; }

	static OBSData BackupScene(obs_scene_t *scene, std::vector<obs_source_t *> *sources = nullptr);
	static inline OBSData BackupScene(obs_source_t *scene_source, std::vector<obs_source_t *> *sources = nullptr)
	{
		obs_scene_t *scene = obs_scene_from_source(scene_source);
		return BackupScene(scene, sources);
	}

	inline const OBSSceneCollectionCache &GetSceneCollectionCache() const noexcept { return collections; };

	const OBSSceneCollection &GetCurrentSceneCollection() const;

	std::optional<OBSSceneCollection> GetSceneCollectionByName(const std::string &collectionName) const;
	std::optional<OBSSceneCollection> GetSceneCollectionByFileName(const std::string &fileName) const;

private slots:
	void on_actionNewSceneCollection_triggered();
	void on_actionDupSceneCollection_triggered();
	void on_actionRenameSceneCollection_triggered();
	void on_actionRemoveSceneCollection_triggered(bool skipConfirmation = false);
	void on_actionImportSceneCollection_triggered();
	void on_actionExportSceneCollection_triggered();
	void on_actionRemigrateSceneCollection_triggered();

	void on_actionShowMissingFiles_triggered();

public slots:
	bool CreateNewSceneCollection(const QString &name);

	void SaveProject();
	void SaveProjectDeferred();

	void DeferSaveBegin();
	void DeferSaveEnd();

	/* --------------------------
     * MARK: - OBSBasic+SceneItems
     * --------------------------
     */
private:
	QPointer<QAction> renameSource;
	QPointer<QMenu> sourceProjector;

	OBSSceneItem GetCurrentSceneItem();
	OBSSceneItem GetSceneItem(QListWidgetItem *item);
	QModelIndexList GetAllSelectedSourceItems();
	int GetTopSelectedSourceItem();

	QMenu *CreateVisibilityTransitionMenu(bool visible);

	void CenterSelectedSceneItems(const CenterType &centerType);

	void CreateFirstRunSources();
	void AddSource(const char *id);

	void AddSourcePopupMenu(const QPoint &pos);
	QMenu *CreateAddSourcePopupMenu();

	bool QueryRemoveSource(obs_source_t *source);

	static void SourceCreated(void *data, calldata_t *params);
	static void SourceRemoved(void *data, calldata_t *params);
	static void SourceActivated(void *data, calldata_t *params);
	static void SourceDeactivated(void *data, calldata_t *params);
	static void SourceAudioActivated(void *data, calldata_t *params);
	static void SourceAudioDeactivated(void *data, calldata_t *params);
	static void SourceRenamed(void *data, calldata_t *params);

public:
	void ResetAudioDevice(const char *sourceId, const char *deviceId, const char *deviceDesc, int channel);

	QMenu *AddDeinterlacingMenu(QMenu *menu, obs_source_t *source);
	QMenu *AddScaleFilteringMenu(QMenu *menu, obs_sceneitem_t *item);
	QMenu *AddBlendingMethodMenu(QMenu *menu, obs_sceneitem_t *item);
	QMenu *AddBlendingModeMenu(QMenu *menu, obs_sceneitem_t *item);
	QMenu *AddBackgroundColorMenu(QMenu *menu, QWidgetAction *widgetAction, ColorSelect *select,
				      obs_sceneitem_t *item);

	void CreateSourcePopupMenu(int idx, bool preview);

private slots:
	void RenameSources(OBSSource source, QString newName, QString prevName);

	void ActivateAudioSource(OBSSource source);
	void DeactivateAudioSource(OBSSource source);

	void OpenFilters(OBSSource source = nullptr);
	void OpenProperties(OBSSource source = nullptr);
	void OpenInteraction(OBSSource source = nullptr);
	void OpenEditTransform(OBSSceneItem item = nullptr);

	void SetDeinterlacingMode();
	void SetDeinterlacingOrder();

	void SetScaleFilter();
	void SetBlendingMethod();
	void SetBlendingMode();

	void ReorderSources(OBSScene scene);
	void RefreshSources(OBSScene scene);

	void MixerRenameSource();

	void on_toggleSourceIcons_toggled(bool visible);

	void on_actionAddSource_triggered();
	void on_actionRemoveSource_triggered();
	void on_actionEditTransform_triggered();
	void on_actionInteract_triggered();
	void on_actionSourceProperties_triggered();
	void on_actionSourceUp_triggered();
	void on_actionSourceDown_triggered();
	void on_actionMoveUp_triggered();
	void on_actionMoveDown_triggered();
	void on_actionMoveToTop_triggered();
	void on_actionMoveToBottom_triggered();

	void on_sources_customContextMenuRequested(const QPoint &pos);
	void on_sourcePropertiesButton_clicked();
	void on_sourceFiltersButton_clicked();
	void on_sourceInteractButton_clicked();

	/* --------------------------
     * MARK: - OBSBasic+Scenes
     * --------------------------
     */
private:
	std::atomic<obs_scene_t *> currentScene = nullptr;

	OBSWeakSource lastScene;

	QPointer<QAction> renameScene;
	QPointer<QMenu> sceneProjectorMenu;

	void SetCurrentScene(obs_scene_t *scene, bool force = false);
	void ChangeSceneIndex(bool relative, int idx, int invalidIdx);
	void MoveSceneItem(enum obs_order_movement movement, const QString &action_name);

	obs_data_array_t *SaveSceneListOrder();

	static void SceneReordered(void *data, calldata_t *params);
	static void SceneRefreshed(void *data, calldata_t *params);
	static void SceneItemAdded(void *data, calldata_t *params);

	QMenu *CreatePerSceneTransitionMenu();

public:
	OBSScene GetCurrentScene();

	inline OBSSource GetCurrentSceneSource()
	{
		OBSScene curScene = GetCurrentScene();
		return OBSSource(obs_scene_get_source(curScene));
	}

private slots:
	void AddScene(OBSSource source);
	void RemoveScene(OBSSource source);

	void SceneNameEdited(QWidget *editor);
	void EditSceneName();

	void AddSceneItem(OBSSceneItem item);
	void EditSceneItemName();

	void DuplicateSelectedScene();
	void RemoveSelectedScene();

	void MoveSceneToTop();
	void MoveSceneToBottom();
	void OpenSceneFilters();

	void GridActionClicked();

	SourceTreeItem *GetItemWidgetFromSceneItem(obs_sceneitem_t *sceneItem);

	void on_actionSceneListMode_triggered();
	void on_actionSceneGridMode_triggered();
	void on_actionAddScene_triggered();
	void on_actionRemoveScene_triggered();
	void on_actionSceneUp_triggered();
	void on_actionSceneDown_triggered();

	void on_scenes_currentItemChanged(QListWidgetItem *current, QListWidgetItem *prev);
	void on_scenes_customContextMenuRequested(const QPoint &pos);
	void on_scenes_itemDoubleClicked(QListWidgetItem *item);

	void on_actionRotate90CW_triggered();
	void on_actionRotate90CCW_triggered();
	void on_actionRotate180_triggered();
	void on_actionFlipHorizontal_triggered();
	void on_actionFlipVertical_triggered();
	void on_actionFitToScreen_triggered();
	void on_actionStretchToScreen_triggered();
	void on_actionCenterToScreen_triggered();
	void on_actionVerticalCenter_triggered();
	void on_actionHorizontalCenter_triggered();

	void on_actionSceneFilters_triggered();

public slots:
	void SetCurrentScene(OBSSource scene, bool force = false);

	void on_actionResetTransform_triggered();

	/* --------------------------
     * MARK: - OBSBasic+Screenshots
     * --------------------------
     */
private:
	QPointer<QObject> screenshotData;
	std::string lastScreenshot;

	obs_hotkey_id screenshotHotkey = 0;
	obs_hotkey_id sourceScreenshotHotkey = 0;

private slots:
	void Screenshot(OBSSource source_ = nullptr);
	void ScreenshotSelectedSource();
	void ScreenshotProgram();
	void ScreenshotScene();

	/* --------------------------
     * MARK: - OBSBasic+Service
     * --------------------------
     */
private:
	OBSService service;
	bool InitService();

public:
	obs_service_t *GetService();

	void SetService(obs_service_t *service);

	void SaveService();
	bool LoadService();

	/* --------------------------
     * MARK: - OBSBasic+StatusBar
     * --------------------------
     */
private:
	QPointer<QTimer> cpuUsageTimer;
	os_cpu_usage_info_t *cpuUsageInfo = nullptr;

public:
	void ShowStatusBarMessage(const QString &message);

	inline double GetCPUUsage() const { return os_cpu_usage_info_query(cpuUsageInfo); }

	/* --------------------------
     * MARK: - OBSBasic+Streaming
     * --------------------------
     */
private:
	std::shared_future<void> setupStreamingGuard;

	obs_hotkey_pair_id streamingHotkeys;
	obs_hotkey_id forceStreamingStopHotkey;

	bool streamingStarting = false;
	bool streamingStopping = false;

private slots:
	void StreamActionTriggered();

public slots:
	void StartStreaming();
	void StopStreaming();
	void ForceStopStreaming();
	void StreamDelayStarting(int sec);
	void StreamDelayStopping(int sec);

	void StreamingStart();
	bool StreamingActive();
	void StreamStopping();
	void StreamingStop(int errorcode, QString last_error);

	void DisplayStreamStartError();

signals:
	void StreamingPreparing();
	void StreamingStarting(bool broadcastAutoStart);
	void StreamingStarted(bool withDelay = false);
	void StreamingStopping();
	void StreamingStopped(bool withDelay = false);

	/* --------------------------
     * MARK: - OBSBasic+StudioMode
     * --------------------------
     */
private:
	OBSWeakSource programScene;
	OBSWeakSource lastProgramScene;

	obs_hotkey_pair_id togglePreviewProgramHotkeys = 0;

	QPointer<QWidget> programWidget;
	QPointer<QVBoxLayout> programLayout;
	QPointer<OBSQTDisplay> program;
	QPointer<QLabel> programLabel;
	QPointer<QWidget> programOptions;
	QPointer<QMenu> studioProgramProjector;

	volatile bool previewProgramMode = false;
	bool sceneDuplicationMode = true;
	bool editPropertiesMode = false;

	int programX = 0;
	int programY = 0;
	int programCX = 0;
	int programCY = 0;
	float programScale = 0.0f;

	void CreateProgramDisplay();
	void CreateProgramOptions();
	void ResizeProgram(uint32_t cx, uint32_t cy);

	void UpdatePreviewProgramIndicators();

	static void RenderProgram(void *data, uint32_t cx, uint32_t cy);

public:
	OBSSource GetProgramSource();

	inline bool IsPreviewProgramMode() const { return os_atomic_load_bool(&previewProgramMode); }

	void SetPreviewProgramMode(bool enabled);
	void ProgramViewContextMenuRequested();

private slots:
	void EnablePreviewProgram();
	void DisablePreviewProgram();
	void TogglePreviewProgramMode();

	void OpenStudioProgramProjector();
	void OpenStudioProgramWindow();

signals:
	void PreviewProgramModeChanged(bool enabled);

	/* --------------------------
     * MARK: - OBSBasic+SysTray
     * --------------------------
     */
private:
	QPointer<QMenu> trayMenu;
	QScopedPointer<QSystemTrayIcon> trayIcon;

	QPointer<QAction> sysTrayStream;
	QPointer<QAction> sysTrayRecord;
	QPointer<QAction> sysTrayReplayBuffer;
	QPointer<QAction> sysTrayVirtualCam;

	bool sysTrayMinimizeToTray();

private slots:
	void IconActivated(QSystemTrayIcon::ActivationReason reason);

public:
	void SysTrayNotify(const QString &text, QSystemTrayIcon::MessageIcon n);
	void SystemTrayInit();
	void SystemTray(bool firstStarted);

	/* --------------------------
     * MARK: - OBSBasic+Transitions
     * --------------------------
     */
private:
	std::vector<OBSDataAutoRelease> safeModeTransitions;
	std::vector<QuickTransition> quickTransitions;

	OBSWeakSource swapScene;

	obs_source_t *cutTransition;
	obs_source_t *fadeTransition;

	QPointer<QPushButton> transitionButton;
	QPointer<QMenu> perSceneTransitionMenu;

	QSlider *tBar;

	OBSSource prevFTBSource = nullptr;

	obs_hotkey_id transitionHotkey = 0;

	int quickTransitionIdCounter = 1;

	bool tBarActive = false;

	bool swapScenesMode = true;

	bool overridingTransition = false;

	OBSSource GetCurrentTransition();
	obs_data_array_t *SaveTransitions();
	obs_data_array_t *SaveQuickTransitions();

	void InitTransition(obs_source_t *transition);
	void InitDefaultTransitions();

	obs_source_t *FindTransition(const char *name);

	void AddQuickTransition();
	void AddQuickTransitionId(int id);
	void CreateDefaultQuickTransitions();
	void RefreshQuickTransitions();
	void LoadQuickTransitions(obs_data_array_t *array);
	QuickTransition *GetQuickTransition(int id);
	int GetQuickTransitionIdx(int id);
	void ClearQuickTransitions();
	void QuickTransitionClicked();

	void AddQuickTransitionHotkey(QuickTransition *qt);
	void RemoveQuickTransitionHotkey(QuickTransition *qt);

	void QuickTransitionRemoveClicked();
	void QuickTransitionChangeDuration(int value);
	void QuickTransitionChange();

	void ClearQuickTransitionWidgets();

	QMenu *CreateTransitionMenu(QWidget *parent, QuickTransition *qt);
	void LoadTransitions(obs_data_array_t *transitions, obs_load_source_cb cb, void *private_data);

	int GetOverrideTransitionDuration(OBSSource source);
	OBSSource GetOverrideTransition(OBSSource source);

	void EnableTransitionWidgets(bool enable);

	// TODO: Remove orphaned method
	void DisableQuickTransitionWidgets();

public:
	int GetTransitionDuration();
	int GetTbarPosition();

private slots:
	void AddTransition(const char *id);
	void RenameTransition(OBSSource transition);

	void TransitionStopped();
	void TransitionFullyStopped();

	void TriggerQuickTransition(int id);

	void TransitionClicked();

	void TBarChanged(int value);
	void TBarReleased();

	void ShowTransitionProperties();
	void HideTransitionProperties();

	void on_transitions_currentIndexChanged(int index);

	void on_transitionAdd_clicked();
	void on_transitionRemove_clicked();
	void on_transitionProps_clicked();
	void on_transitionDuration_valueChanged();

public slots:
	void SetTransition(OBSSource transition);
	void OverrideTransition(OBSSource transition);

	void TransitionToScene(OBSScene scene, bool force = false);
	void TransitionToScene(OBSSource scene, bool force = false, bool quickTransition = false, int quickDuration = 0,
			       bool black = false, bool manual = false);

	/* --------------------------
     * MARK: - OBSBasic+Updater
     * --------------------------
     */
private:
	QScopedPointer<QThread> updateCheckThread;
	QScopedPointer<QThread> introCheckThread;
	QScopedPointer<QThread> whatsNewInitThread;

	void TimedCheckForUpdates();
	void ReceivedIntroJson(const QString &text);

	void CheckForUpdates(bool manualUpdate);
	void MacBranchesFetched(const QString &branch, bool manualUpdate);

	void ShowWhatsNew(const QString &url);

	/* --------------------------
     * MARK: - OBSBasic+VirtualCam
     * --------------------------
     */
private:
	VCamConfig vcamConfig;

	obs_hotkey_pair_id vcamHotkeys;

	bool vcamEnabled = false;
	bool restartingVCam = false;

public:
	inline bool VCamEnabled() const { return vcamEnabled; }

private slots:
	void UpdateVirtualCamConfig(const VCamConfig &config);
	void RestartVirtualCam(const VCamConfig &config);
	void RestartingVirtualCam();
	void VirtualCamActionTriggered();
	void OpenVirtualCamConfig();

public slots:
	void OnVirtualCamStart();
	bool VirtualCamActive();
	void OnVirtualCamStop(int code);

	void StartVirtualCam();
	void StopVirtualCam();

signals:
	void VirtualCamEnabled();
	void VirtualCamStarted();
	void VirtualCamStopped();

	/* --------------------------
     * MARK: - OBSBasic+VolControl
     * --------------------------
     */
private:
	std::vector<VolControl *> volumes;

	void UpdateVolumeControlsDecayRate();
	void UpdateVolumeControlsPeakMeterType();

	void VolControlContextMenu();

	void ToggleVolControlLayout();
	void ToggleMixerLayout(bool vertical);

	void GetAudioSourceFilters();
	void GetAudioSourceProperties();

public:
	void RefreshVolumeColors();

private slots:
	void LockVolumeControl(bool lock);

	void HideAudioControl();
	void UnhideAllAudioControls();
	void ToggleHideMixer();
	void StackedMixerAreaContextMenuRequested();

	void on_vMixerScrollArea_customContextMenuRequested();
	void on_hMixerScrollArea_customContextMenuRequested();

	void on_actionMixerToolbarAdvAudio_triggered();
	void on_actionMixerToolbarMenu_triggered();

	/* --------------------------
     * MARK: - OBSBasic+YouTube
     * --------------------------
     */

private:
	QPointer<QThread> youtubeStreamCheckThread;

	bool autoStartBroadcast = true;
	bool autoStopBroadcast = true;
	bool broadcastReady = false;
	bool broadcastActive = false;

	void SetBroadcastFlowEnabled(bool enabled);
	void BroadcastButtonClicked();
#ifdef YOUTUBE_ENABLED
	QPointer<YouTubeAppDock> youtubeAppDock;
	uint64_t lastYouTubeAppDockCreationTime = 0;

	void YoutubeStreamCheck(const std::string &key);
	void ShowYouTubeAutoStartWarning();

	void DeleteYouTubeAppDock();

	void YouTubeActionDialogOk(const QString &broadcast_id, const QString &stream_id, const QString &key,
				   bool autostart, bool autostop, bool start_now);

public:
	void NewYouTubeAppDock();
	YouTubeAppDock *GetYouTubeAppDock();
#endif

public slots:
	void SetupBroadcast();

signals:
	void BroadcastStreamReady(bool ready);
	void BroadcastStreamStarted(bool autoStop);
	void BroadcastStreamActive();

	void BroadcastFlowEnabled(bool enabled);
};
