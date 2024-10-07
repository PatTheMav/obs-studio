/******************************************************************************
    Copyright (C) 2023 by Lain Bailey <lain@obsproject.com>
                          Zachary Lund <admin@computerquip.com>
                          Philippe Groarke <philippe.groarke@gmail.com>

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

#include "OBSBasic.hpp"
#include "OBSProjector.hpp"

#include <dialogs/NameDialog.hpp>

#include <qt-wrappers.hpp>

#include <QLineEdit>
#include <QWidgetAction>

#include <vector>

using namespace std;

namespace {

template<typename OBSRef> struct SignalContainer {
	OBSRef ref;
	vector<shared_ptr<OBSSignal>> handlers;
};
} // namespace

Q_DECLARE_METATYPE(obs_order_movement);
Q_DECLARE_METATYPE(SignalContainer<OBSScene>);

extern void undo_redo(const std::string &data);

static bool select_one(obs_scene_t * /* scene */, obs_sceneitem_t *item, void *param)
{
	obs_sceneitem_t *selectedItem = reinterpret_cast<obs_sceneitem_t *>(param);
	if (obs_sceneitem_is_group(item))
		obs_sceneitem_group_enum_items(item, select_one, param);

	obs_sceneitem_select(item, (selectedItem == item));

	return true;
}

static void RenameListItem(OBSBasic *parent, QListWidget *listWidget, obs_source_t *source, const string &name)
{
	const char *prevName = obs_source_get_name(source);
	if (name == prevName)
		return;

	OBSSourceAutoRelease foundSource = obs_get_source_by_name(name.c_str());
	QListWidgetItem *listItem = listWidget->currentItem();

	if (foundSource || name.empty()) {
		listItem->setText(QT_UTF8(prevName));

		if (foundSource) {
			OBSMessageBox::warning(parent, QTStr("NameExists.Title"), QTStr("NameExists.Text"));
		} else if (name.empty()) {
			OBSMessageBox::warning(parent, QTStr("NoNameEntered.Title"), QTStr("NoNameEntered.Text"));
		}
	} else {
		auto undo = [prev = std::string(prevName)](const std::string &data) {
			OBSSourceAutoRelease source = obs_get_source_by_uuid(data.c_str());
			obs_source_set_name(source, prev.c_str());
		};

		auto redo = [name](const std::string &data) {
			OBSSourceAutoRelease source = obs_get_source_by_uuid(data.c_str());
			obs_source_set_name(source, name.c_str());
		};

		std::string source_uuid(obs_source_get_uuid(source));
		parent->undo_s.add_action(QTStr("Undo.Rename").arg(name.c_str()), undo, redo, source_uuid, source_uuid);

		listItem->setText(QT_UTF8(name.c_str()));
		obs_source_set_name(source, name.c_str());
	}
}

static inline void RemoveSceneAndReleaseNested(obs_source_t *source)
{
	obs_source_remove(source);
	auto cb = [](void *, obs_source_t *source) {
		if (strcmp(obs_source_get_id(source), "scene") == 0)
			obs_scene_prune_sources(obs_scene_from_source(source));
		return true;
	};
	obs_enum_scenes(cb, NULL);
}

static bool RotateSelectedSources(obs_scene_t * /* scene */, obs_sceneitem_t *item, void *param)
{
	if (obs_sceneitem_is_group(item))
		obs_sceneitem_group_enum_items(item, RotateSelectedSources, param);
	if (!obs_sceneitem_selected(item))
		return true;
	if (obs_sceneitem_locked(item))
		return true;

	float rot = *reinterpret_cast<float *>(param);

	vec3 tl = GetItemTL(item);

	rot += obs_sceneitem_get_rot(item);
	if (rot >= 360.0f)
		rot -= 360.0f;
	else if (rot <= -360.0f)
		rot += 360.0f;
	obs_sceneitem_set_rot(item, rot);

	obs_sceneitem_force_update_transform(item);

	SetItemTL(item, tl);

	return true;
};

static bool reset_tr(obs_scene_t * /* scene */, obs_sceneitem_t *item, void *)
{
	if (obs_sceneitem_is_group(item))
		obs_sceneitem_group_enum_items(item, reset_tr, nullptr);
	if (!obs_sceneitem_selected(item))
		return true;
	if (obs_sceneitem_locked(item))
		return true;

	obs_sceneitem_defer_update_begin(item);

	obs_transform_info info;
	vec2_set(&info.pos, 0.0f, 0.0f);
	vec2_set(&info.scale, 1.0f, 1.0f);
	info.rot = 0.0f;
	info.alignment = OBS_ALIGN_TOP | OBS_ALIGN_LEFT;
	info.bounds_type = OBS_BOUNDS_NONE;
	info.bounds_alignment = OBS_ALIGN_CENTER;
	info.crop_to_bounds = false;
	vec2_set(&info.bounds, 0.0f, 0.0f);
	obs_sceneitem_set_info2(item, &info);

	obs_sceneitem_crop crop = {};
	obs_sceneitem_set_crop(item, &crop);

	obs_sceneitem_defer_update_end(item);

	return true;
}

static bool CenterAlignSelectedItems(obs_scene_t * /* scene */, obs_sceneitem_t *item, void *param)
{
	obs_bounds_type boundsType = *reinterpret_cast<obs_bounds_type *>(param);

	if (obs_sceneitem_is_group(item))
		obs_sceneitem_group_enum_items(item, CenterAlignSelectedItems, param);
	if (!obs_sceneitem_selected(item))
		return true;
	if (obs_sceneitem_locked(item))
		return true;

	obs_video_info ovi;
	obs_get_video_info(&ovi);

	obs_transform_info itemInfo;
	vec2_set(&itemInfo.pos, 0.0f, 0.0f);
	vec2_set(&itemInfo.scale, 1.0f, 1.0f);
	itemInfo.alignment = OBS_ALIGN_LEFT | OBS_ALIGN_TOP;
	itemInfo.rot = 0.0f;

	vec2_set(&itemInfo.bounds, float(ovi.base_width), float(ovi.base_height));
	itemInfo.bounds_type = boundsType;
	itemInfo.bounds_alignment = OBS_ALIGN_CENTER;
	itemInfo.crop_to_bounds = obs_sceneitem_get_bounds_crop(item);

	obs_sceneitem_set_info2(item, &itemInfo);

	return true;
}

static bool MultiplySelectedItemScale(obs_scene_t * /* scene */, obs_sceneitem_t *item, void *param)
{
	vec2 &mul = *reinterpret_cast<vec2 *>(param);

	if (obs_sceneitem_is_group(item))
		obs_sceneitem_group_enum_items(item, MultiplySelectedItemScale, param);
	if (!obs_sceneitem_selected(item))
		return true;
	if (obs_sceneitem_locked(item))
		return true;

	vec3 tl = GetItemTL(item);

	vec2 scale;
	obs_sceneitem_get_scale(item, &scale);
	vec2_mul(&scale, &scale, &mul);
	obs_sceneitem_set_scale(item, &scale);

	obs_sceneitem_force_update_transform(item);

	SetItemTL(item, tl);

	return true;
}

static bool save_undo_source_enum(obs_scene_t * /* scene */, obs_sceneitem_t *item, void *p)
{
	obs_source_t *source = obs_sceneitem_get_source(item);
	if (obs_obj_is_private(source) && !obs_source_removed(source))
		return true;

	obs_data_array_t *array = (obs_data_array_t *)p;

	/* check if the source is already stored in the array */
	const char *name = obs_source_get_name(source);
	const size_t count = obs_data_array_count(array);
	for (size_t i = 0; i < count; i++) {
		OBSDataAutoRelease sourceData = obs_data_array_item(array, i);
		if (strcmp(name, obs_data_get_string(sourceData, "name")) == 0)
			return true;
	}

	if (obs_source_is_group(source))
		obs_scene_enum_items(obs_group_from_source(source), save_undo_source_enum, p);

	OBSDataAutoRelease source_data = obs_save_source(source);
	obs_data_array_push_back(array, source_data);
	return true;
}

void OBSBasic::SetCurrentScene(obs_scene_t *scene, bool force)
{
	obs_source_t *source = obs_scene_get_source(scene);
	SetCurrentScene(source, force);
}

void OBSBasic::ChangeSceneIndex(bool relative, int offset, int invalidIdx)
{
	int idx = ui->scenes->currentRow();
	if (idx == -1 || idx == invalidIdx)
		return;

	ui->scenes->blockSignals(true);
	QListWidgetItem *item = ui->scenes->takeItem(idx);

	if (!relative)
		idx = 0;

	ui->scenes->insertItem(idx + offset, item);
	ui->scenes->setCurrentRow(idx + offset);
	item->setSelected(true);
	currentScene = GetOBSRef<OBSScene>(item).Get();
	ui->scenes->blockSignals(false);

	OBSProjector::UpdateMultiviewProjectors();
}

void OBSBasic::MoveSceneItem(enum obs_order_movement movement, const QString &action_name)
{
	OBSSceneItem item = GetCurrentSceneItem();
	obs_source_t *source = obs_sceneitem_get_source(item);

	if (!source)
		return;

	OBSScene scene = GetCurrentScene();
	std::vector<obs_source_t *> sources;
	if (scene != obs_sceneitem_get_scene(item))
		sources.push_back(obs_scene_get_source(obs_sceneitem_get_scene(item)));

	OBSData undo_data = BackupScene(scene, &sources);

	obs_sceneitem_set_order(item, movement);

	const char *source_name = obs_source_get_name(source);
	const char *scene_name = obs_source_get_name(obs_scene_get_source(scene));

	OBSData redo_data = BackupScene(scene, &sources);
	CreateSceneUndoRedoAction(action_name.arg(source_name, scene_name), undo_data, redo_data);
}

obs_data_array_t *OBSBasic::SaveSceneListOrder()
{
	obs_data_array_t *sceneOrder = obs_data_array_create();

	for (int i = 0; i < ui->scenes->count(); i++) {
		OBSDataAutoRelease data = obs_data_create();
		obs_data_set_string(data, "name", QT_TO_UTF8(ui->scenes->item(i)->text()));
		obs_data_array_push_back(sceneOrder, data);
	}

	return sceneOrder;
}

void OBSBasic::SceneReordered(void *data, calldata_t *params)
{
	OBSBasic *window = static_cast<OBSBasic *>(data);

	obs_scene_t *scene = (obs_scene_t *)calldata_ptr(params, "scene");

	QMetaObject::invokeMethod(window, "ReorderSources", Q_ARG(OBSScene, OBSScene(scene)));
}

void OBSBasic::SceneRefreshed(void *data, calldata_t *params)
{
	OBSBasic *window = static_cast<OBSBasic *>(data);

	obs_scene_t *scene = (obs_scene_t *)calldata_ptr(params, "scene");

	QMetaObject::invokeMethod(window, "RefreshSources", Q_ARG(OBSScene, OBSScene(scene)));
}

void OBSBasic::SceneItemAdded(void *data, calldata_t *params)
{
	OBSBasic *window = static_cast<OBSBasic *>(data);

	obs_sceneitem_t *item = (obs_sceneitem_t *)calldata_ptr(params, "item");

	QMetaObject::invokeMethod(window, "AddSceneItem", Q_ARG(OBSSceneItem, OBSSceneItem(item)));
}

QMenu *OBSBasic::CreatePerSceneTransitionMenu()
{
	OBSSource scene = GetCurrentSceneSource();
	QMenu *menu = new QMenu(QTStr("TransitionOverride"));
	QAction *action;

	OBSDataAutoRelease data = obs_source_get_private_settings(scene);

	obs_data_set_default_int(data, "transition_duration", 300);

	const char *curTransition = obs_data_get_string(data, "transition");
	int curDuration = (int)obs_data_get_int(data, "transition_duration");

	QSpinBox *duration = new QSpinBox(menu);
	duration->setMinimum(50);
	duration->setSuffix(" ms");
	duration->setMaximum(20000);
	duration->setSingleStep(50);
	duration->setValue(curDuration);

	auto setTransition = [this](QAction *action) {
		int idx = action->property("transition_index").toInt();
		OBSSource scene = GetCurrentSceneSource();
		OBSDataAutoRelease data = obs_source_get_private_settings(scene);

		if (idx == -1) {
			obs_data_set_string(data, "transition", "");
			return;
		}

		OBSSource tr = GetTransitionComboItem(ui->transitions, idx);

		if (tr) {
			const char *name = obs_source_get_name(tr);
			obs_data_set_string(data, "transition", name);
		}
	};

	auto setDuration = [this](int duration) {
		OBSSource scene = GetCurrentSceneSource();
		OBSDataAutoRelease data = obs_source_get_private_settings(scene);

		obs_data_set_int(data, "transition_duration", duration);
	};

	connect(duration, (void(QSpinBox::*)(int)) & QSpinBox::valueChanged, setDuration);

	for (int i = -1; i < ui->transitions->count(); i++) {
		const char *name = "";

		if (i >= 0) {
			OBSSource tr;
			tr = GetTransitionComboItem(ui->transitions, i);
			if (!tr)
				continue;
			name = obs_source_get_name(tr);
		}

		bool match = (name && strcmp(name, curTransition) == 0);

		if (!name || !*name)
			name = Str("None");

		action = menu->addAction(QT_UTF8(name));
		action->setProperty("transition_index", i);
		action->setCheckable(true);
		action->setChecked(match);

		connect(action, &QAction::triggered, std::bind(setTransition, action));
	}

	QWidgetAction *durationAction = new QWidgetAction(menu);
	durationAction->setDefaultWidget(duration);

	menu->addSeparator();
	menu->addAction(durationAction);
	return menu;
}

OBSScene OBSBasic::GetCurrentScene()
{
	return currentScene.load();
}

void OBSBasic::AddScene(OBSSource source)
{
	const char *name = obs_source_get_name(source);
	obs_scene_t *scene = obs_scene_from_source(source);

	QListWidgetItem *item = new QListWidgetItem(QT_UTF8(name));
	SetOBSRef(item, OBSScene(scene));
	ui->scenes->insertItem(ui->scenes->currentRow() + 1, item);

	obs_hotkey_register_source(
		source, "OBSBasic.SelectScene", Str("Basic.Hotkeys.SelectScene"),
		[](void *data, obs_hotkey_id, obs_hotkey_t *, bool pressed) {
			OBSBasic *main = reinterpret_cast<OBSBasic *>(App()->GetMainWindow());

			auto potential_source = static_cast<obs_source_t *>(data);
			OBSSourceAutoRelease source = obs_source_get_ref(potential_source);
			if (source && pressed)
				main->SetCurrentScene(source.Get());
		},
		static_cast<obs_source_t *>(source));

	signal_handler_t *handler = obs_source_get_signal_handler(source);

	SignalContainer<OBSScene> container;
	container.ref = scene;
	container.handlers.assign({
		std::make_shared<OBSSignal>(handler, "item_add", OBSBasic::SceneItemAdded, this),
		std::make_shared<OBSSignal>(handler, "reorder", OBSBasic::SceneReordered, this),
		std::make_shared<OBSSignal>(handler, "refresh", OBSBasic::SceneRefreshed, this),
	});

	item->setData(static_cast<int>(QtDataRole::OBSSignals), QVariant::fromValue(container));

	/* if the scene already has items (a duplicated scene) add them */
	auto addSceneItem = [this](obs_sceneitem_t *item) {
		AddSceneItem(item);
	};

	using addSceneItem_t = decltype(addSceneItem);

	obs_scene_enum_items(
		scene,
		[](obs_scene_t *, obs_sceneitem_t *item, void *param) {
			addSceneItem_t *func;
			func = reinterpret_cast<addSceneItem_t *>(param);
			(*func)(item);
			return true;
		},
		&addSceneItem);

	SaveProject();

	if (!disableSaving) {
		obs_source_t *source = obs_scene_get_source(scene);
		blog(LOG_INFO, "User added scene '%s'", obs_source_get_name(source));

		OBSProjector::UpdateMultiviewProjectors();
	}

	OnEvent(OBS_FRONTEND_EVENT_SCENE_LIST_CHANGED);
}
void OBSBasic::RemoveScene(OBSSource source)
{
	obs_scene_t *scene = obs_scene_from_source(source);

	QListWidgetItem *sel = nullptr;
	int count = ui->scenes->count();

	for (int i = 0; i < count; i++) {
		auto item = ui->scenes->item(i);
		auto cur_scene = GetOBSRef<OBSScene>(item);
		if (cur_scene != scene)
			continue;

		sel = item;
		break;
	}

	if (sel != nullptr) {
		if (sel == ui->scenes->currentItem())
			ui->sources->Clear();
		delete sel;
	}

	SaveProject();

	if (!disableSaving) {
		blog(LOG_INFO, "User Removed scene '%s'", obs_source_get_name(source));

		OBSProjector::UpdateMultiviewProjectors();
	}

	OnEvent(OBS_FRONTEND_EVENT_SCENE_LIST_CHANGED);
}

void OBSBasic::SceneNameEdited(QWidget *editor)
{
	OBSScene scene = GetCurrentScene();
	QLineEdit *edit = qobject_cast<QLineEdit *>(editor);
	string text = QT_TO_UTF8(edit->text().trimmed());

	if (!scene)
		return;

	obs_source_t *source = obs_scene_get_source(scene);
	RenameListItem(this, ui->scenes, source, text);

	ui->scenesDock->addAction(renameScene);

	OnEvent(OBS_FRONTEND_EVENT_SCENE_LIST_CHANGED);
}

void OBSBasic::AddSceneItem(OBSSceneItem item)
{
	obs_scene_t *scene = obs_sceneitem_get_scene(item);

	if (GetCurrentScene() == scene)
		ui->sources->Add(item);

	SaveProject();

	if (!disableSaving) {
		obs_source_t *sceneSource = obs_scene_get_source(scene);
		obs_source_t *itemSource = obs_sceneitem_get_source(item);
		blog(LOG_INFO, "User added source '%s' (%s) to scene '%s'", obs_source_get_name(itemSource),
		     obs_source_get_id(itemSource), obs_source_get_name(sceneSource));

		obs_scene_enum_items(scene, select_one, (obs_sceneitem_t *)item);
	}
}
void OBSBasic::EditSceneName()
{
	ui->scenesDock->removeAction(renameScene);
	QListWidgetItem *item = ui->scenes->currentItem();
	Qt::ItemFlags flags = item->flags();

	item->setFlags(flags | Qt::ItemIsEditable);
	ui->scenes->editItem(item);
	item->setFlags(flags);
}

void OBSBasic::EditSceneItemName()
{
	int idx = GetTopSelectedSourceItem();
	ui->sources->Edit(idx);
}

void OBSBasic::DuplicateSelectedScene()
{
	OBSScene curScene = GetCurrentScene();

	if (!curScene)
		return;

	OBSSource curSceneSource = obs_scene_get_source(curScene);
	QString format{obs_source_get_name(curSceneSource)};
	format += " %1";

	int i = 2;
	QString placeHolderText = format.arg(i);
	OBSSourceAutoRelease source = nullptr;
	while ((source = obs_get_source_by_name(QT_TO_UTF8(placeHolderText)))) {
		placeHolderText = format.arg(++i);
	}

	for (;;) {
		string name;
		bool accepted = NameDialog::AskForName(this, QTStr("Basic.Main.AddSceneDlg.Title"),
						       QTStr("Basic.Main.AddSceneDlg.Text"), name, placeHolderText);
		if (!accepted)
			return;

		if (name.empty()) {
			OBSMessageBox::warning(this, QTStr("NoNameEntered.Title"), QTStr("NoNameEntered.Text"));
			continue;
		}

		obs_source_t *source = obs_get_source_by_name(name.c_str());
		if (source) {
			OBSMessageBox::warning(this, QTStr("NameExists.Title"), QTStr("NameExists.Text"));

			obs_source_release(source);
			continue;
		}

		OBSSceneAutoRelease scene = obs_scene_duplicate(curScene, name.c_str(), OBS_SCENE_DUP_REFS);
		source = obs_scene_get_source(scene);
		SetCurrentScene(source, true);

		auto undo = [](const std::string &data) {
			OBSSourceAutoRelease source = obs_get_source_by_name(data.c_str());
			obs_source_remove(source);
		};

		auto redo = [this, name](const std::string &data) {
			OBSSourceAutoRelease source = obs_get_source_by_name(data.c_str());
			obs_scene_t *scene = obs_scene_from_source(source);
			scene = obs_scene_duplicate(scene, name.c_str(), OBS_SCENE_DUP_REFS);
			source = obs_scene_get_source(scene);
			SetCurrentScene(source.Get(), true);
		};

		undo_s.add_action(QTStr("Undo.Scene.Duplicate").arg(obs_source_get_name(source)), undo, redo,
				  obs_source_get_name(source), obs_source_get_name(obs_scene_get_source(curScene)));

		break;
	}
}
void OBSBasic::RemoveSelectedScene()
{
	OBSScene scene = GetCurrentScene();
	obs_source_t *source = obs_scene_get_source(scene);

	if (!source || !QueryRemoveSource(source)) {
		return;
	}

	/* ------------------------------ */
	/* save all sources in scene      */

	OBSDataArrayAutoRelease sources_in_deleted_scene = obs_data_array_create();

	obs_scene_enum_items(scene, save_undo_source_enum, sources_in_deleted_scene);

	OBSDataAutoRelease scene_data = obs_save_source(source);
	obs_data_array_push_back(sources_in_deleted_scene, scene_data);

	/* ----------------------------------------------- */
	/* save all scenes and groups the scene is used in */

	OBSDataArrayAutoRelease scene_used_in_other_scenes = obs_data_array_create();

	struct other_scenes_cb_data {
		obs_source_t *oldScene;
		obs_data_array_t *scene_used_in_other_scenes;
	} other_scenes_cb_data;
	other_scenes_cb_data.oldScene = source;
	other_scenes_cb_data.scene_used_in_other_scenes = scene_used_in_other_scenes;

	auto other_scenes_cb = [](void *data_ptr, obs_source_t *scene) {
		struct other_scenes_cb_data *data = (struct other_scenes_cb_data *)data_ptr;
		if (strcmp(obs_source_get_name(scene), obs_source_get_name(data->oldScene)) == 0)
			return true;
		obs_sceneitem_t *item = obs_scene_find_source(obs_group_or_scene_from_source(scene),
							      obs_source_get_name(data->oldScene));
		if (item) {
			OBSDataAutoRelease scene_data =
				obs_save_source(obs_scene_get_source(obs_sceneitem_get_scene(item)));
			obs_data_array_push_back(data->scene_used_in_other_scenes, scene_data);
		}
		return true;
	};
	obs_enum_scenes(other_scenes_cb, &other_scenes_cb_data);

	/* --------------------------- */
	/* undo/redo                   */

	auto undo = [this](const std::string &json) {
		OBSDataAutoRelease base = obs_data_create_from_json(json.c_str());
		OBSDataArrayAutoRelease sources_in_deleted_scene = obs_data_get_array(base, "sources_in_deleted_scene");
		OBSDataArrayAutoRelease scene_used_in_other_scenes =
			obs_data_get_array(base, "scene_used_in_other_scenes");
		int savedIndex = (int)obs_data_get_int(base, "index");
		std::vector<OBSSource> sources;

		/* create missing sources */
		size_t count = obs_data_array_count(sources_in_deleted_scene);
		sources.reserve(count);

		for (size_t i = 0; i < count; i++) {
			OBSDataAutoRelease data = obs_data_array_item(sources_in_deleted_scene, i);
			const char *name = obs_data_get_string(data, "name");

			OBSSourceAutoRelease source = obs_get_source_by_name(name);
			if (!source) {
				source = obs_load_source(data);
				sources.push_back(source.Get());
			}
		}

		/* actually load sources now */
		for (obs_source_t *source : sources)
			obs_source_load2(source);

		/* Add scene to scenes and groups it was nested in */
		for (size_t i = 0; i < obs_data_array_count(scene_used_in_other_scenes); i++) {
			OBSDataAutoRelease data = obs_data_array_item(scene_used_in_other_scenes, i);
			const char *name = obs_data_get_string(data, "name");
			OBSSourceAutoRelease source = obs_get_source_by_name(name);

			OBSDataAutoRelease settings = obs_data_get_obj(data, "settings");
			OBSDataArrayAutoRelease items = obs_data_get_array(settings, "items");

			/* Clear scene, but keep a reference to all sources in the scene to make sure they don't get destroyed */
			std::vector<OBSSource> existing_sources;
			auto cb = [](obs_scene_t *, obs_sceneitem_t *item, void *data) {
				std::vector<OBSSource> *existing = (std::vector<OBSSource> *)data;
				OBSSource source = obs_sceneitem_get_source(item);
				obs_sceneitem_remove(item);
				existing->push_back(source);
				return true;
			};
			obs_scene_enum_items(obs_group_or_scene_from_source(source), cb, (void *)&existing_sources);

			/* Re-add sources to the scene */
			obs_sceneitems_add(obs_group_or_scene_from_source(source), items);
		}

		obs_source_t *scene_source = sources.back();
		OBSScene scene = obs_scene_from_source(scene_source);
		SetCurrentScene(scene, true);

		/* set original index in list box */
		ui->scenes->blockSignals(true);
		int curIndex = ui->scenes->currentRow();
		QListWidgetItem *item = ui->scenes->takeItem(curIndex);
		ui->scenes->insertItem(savedIndex, item);
		ui->scenes->setCurrentRow(savedIndex);
		currentScene = scene.Get();
		ui->scenes->blockSignals(false);
	};

	auto redo = [](const std::string &name) {
		OBSSourceAutoRelease source = obs_get_source_by_name(name.c_str());
		RemoveSceneAndReleaseNested(source);
	};

	OBSDataAutoRelease data = obs_data_create();
	obs_data_set_array(data, "sources_in_deleted_scene", sources_in_deleted_scene);
	obs_data_set_array(data, "scene_used_in_other_scenes", scene_used_in_other_scenes);
	obs_data_set_int(data, "index", ui->scenes->currentRow());

	const char *scene_name = obs_source_get_name(source);
	undo_s.add_action(QTStr("Undo.Delete").arg(scene_name), undo, redo, obs_data_get_json(data), scene_name);

	/* --------------------------- */
	/* remove                      */

	RemoveSceneAndReleaseNested(source);

	OnEvent(OBS_FRONTEND_EVENT_SCENE_LIST_CHANGED);
}
void OBSBasic::MoveSceneToTop()
{
	ChangeSceneIndex(false, 0, 0);
}

void OBSBasic::MoveSceneToBottom()
{
	ChangeSceneIndex(false, ui->scenes->count() - 1, ui->scenes->count() - 1);
}

void OBSBasic::OpenSceneFilters()
{
	OBSScene scene = GetCurrentScene();
	OBSSource source = obs_scene_get_source(scene);

	CreateFiltersWindow(source);
}

void OBSBasic::GridActionClicked()
{
	bool gridMode = !ui->scenes->GetGridMode();
	ui->scenes->SetGridMode(gridMode);

	if (gridMode)
		ui->actionSceneGridMode->setChecked(true);
	else
		ui->actionSceneListMode->setChecked(true);

	config_set_bool(App()->GetUserConfig(), "BasicWindow", "gridMode", gridMode);
}

SourceTreeItem *OBSBasic::GetItemWidgetFromSceneItem(obs_sceneitem_t *sceneItem)
{
	int i = 0;
	SourceTreeItem *treeItem = ui->sources->GetItemWidget(i);
	OBSSceneItem item = ui->sources->Get(i);
	int64_t id = obs_sceneitem_get_id(sceneItem);
	while (treeItem && obs_sceneitem_get_id(item) != id) {
		i++;
		treeItem = ui->sources->GetItemWidget(i);
		item = ui->sources->Get(i);
	}
	if (treeItem)
		return treeItem;

	return nullptr;
}

void OBSBasic::on_actionSceneListMode_triggered()
{
	ui->scenes->SetGridMode(false);
	config_set_bool(App()->GetUserConfig(), "BasicWindow", "gridMode", false);
}

void OBSBasic::on_actionSceneGridMode_triggered()
{
	ui->scenes->SetGridMode(true);
	config_set_bool(App()->GetUserConfig(), "BasicWindow", "gridMode", true);
}
void OBSBasic::on_actionAddScene_triggered()
{
	string name;
	QString format{QTStr("Basic.Main.DefaultSceneName.Text")};

	int i = 2;
	QString placeHolderText = format.arg(i);
	OBSSourceAutoRelease source = nullptr;
	while ((source = obs_get_source_by_name(QT_TO_UTF8(placeHolderText)))) {
		placeHolderText = format.arg(++i);
	}

	bool accepted = NameDialog::AskForName(this, QTStr("Basic.Main.AddSceneDlg.Title"),
					       QTStr("Basic.Main.AddSceneDlg.Text"), name, placeHolderText);

	if (accepted) {
		if (name.empty()) {
			OBSMessageBox::warning(this, QTStr("NoNameEntered.Title"), QTStr("NoNameEntered.Text"));
			on_actionAddScene_triggered();
			return;
		}

		OBSSourceAutoRelease source = obs_get_source_by_name(name.c_str());
		if (source) {
			OBSMessageBox::warning(this, QTStr("NameExists.Title"), QTStr("NameExists.Text"));

			on_actionAddScene_triggered();
			return;
		}

		auto undo_fn = [](const std::string &data) {
			obs_source_t *t = obs_get_source_by_name(data.c_str());
			if (t) {
				obs_source_remove(t);
				obs_source_release(t);
			}
		};

		auto redo_fn = [this](const std::string &data) {
			OBSSceneAutoRelease scene = obs_scene_create(data.c_str());
			obs_source_t *source = obs_scene_get_source(scene);
			SetCurrentScene(source, true);
		};
		undo_s.add_action(QTStr("Undo.Add").arg(QString(name.c_str())), undo_fn, redo_fn, name, name);

		OBSSceneAutoRelease scene = obs_scene_create(name.c_str());
		obs_source_t *scene_source = obs_scene_get_source(scene);
		SetCurrentScene(scene_source);
	}
}

void OBSBasic::on_actionRemoveScene_triggered()
{
	RemoveSelectedScene();
}

void OBSBasic::on_actionSceneUp_triggered()
{
	ChangeSceneIndex(true, -1, 0);
}

void OBSBasic::on_actionSceneDown_triggered()
{
	ChangeSceneIndex(true, 1, ui->scenes->count() - 1);
}
void OBSBasic::on_scenes_currentItemChanged(QListWidgetItem *current, QListWidgetItem *)
{
	OBSSource source;

	if (current) {
		OBSScene scene = GetOBSRef<OBSScene>(current);
		source = obs_scene_get_source(scene);

		currentScene = scene;
	} else {
		currentScene = NULL;
	}

	SetCurrentScene(source);

	if (vcamEnabled && vcamConfig.type == VCamOutputType::PreviewOutput)
		outputHandler->UpdateVirtualCamOutputSource();

	OnEvent(OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED);

	UpdateContextBar();
}
void OBSBasic::on_scenes_customContextMenuRequested(const QPoint &pos)
{
	QListWidgetItem *item = ui->scenes->itemAt(pos);

	QMenu popup(this);
	QMenu order(QTStr("Basic.MainMenu.Edit.Order"), this);

	popup.addAction(QTStr("Add"), this, &OBSBasic::on_actionAddScene_triggered);

	if (item) {
		QAction *copyFilters = new QAction(QTStr("Copy.Filters"), this);
		copyFilters->setEnabled(false);
		connect(copyFilters, &QAction::triggered, this, &OBSBasic::SceneCopyFilters);
		QAction *pasteFilters = new QAction(QTStr("Paste.Filters"), this);
		pasteFilters->setEnabled(!obs_weak_source_expired(copyFiltersSource));
		connect(pasteFilters, &QAction::triggered, this, &OBSBasic::ScenePasteFilters);

		popup.addSeparator();
		popup.addAction(QTStr("Duplicate"), this, &OBSBasic::DuplicateSelectedScene);
		popup.addAction(copyFilters);
		popup.addAction(pasteFilters);
		popup.addSeparator();
		popup.addAction(renameScene);
		popup.addAction(ui->actionRemoveScene);
		popup.addSeparator();

		order.addAction(QTStr("Basic.MainMenu.Edit.Order.MoveUp"), this, &OBSBasic::on_actionSceneUp_triggered);
		order.addAction(QTStr("Basic.MainMenu.Edit.Order.MoveDown"), this,
				&OBSBasic::on_actionSceneDown_triggered);
		order.addSeparator();
		order.addAction(QTStr("Basic.MainMenu.Edit.Order.MoveToTop"), this, &OBSBasic::MoveSceneToTop);
		order.addAction(QTStr("Basic.MainMenu.Edit.Order.MoveToBottom"), this, &OBSBasic::MoveSceneToBottom);
		popup.addMenu(&order);

		popup.addSeparator();

		delete sceneProjectorMenu;
		sceneProjectorMenu = new QMenu(QTStr("SceneProjector"));
		AddProjectorMenuMonitors(sceneProjectorMenu, this, &OBSBasic::OpenSceneProjector);
		popup.addMenu(sceneProjectorMenu);

		QAction *sceneWindow = popup.addAction(QTStr("SceneWindow"), this, &OBSBasic::OpenSceneWindow);

		popup.addAction(sceneWindow);
		popup.addAction(QTStr("Screenshot.Scene"), this, &OBSBasic::ScreenshotScene);
		popup.addSeparator();
		popup.addAction(QTStr("Filters"), this, &OBSBasic::OpenSceneFilters);

		popup.addSeparator();

		delete perSceneTransitionMenu;
		perSceneTransitionMenu = CreatePerSceneTransitionMenu();
		popup.addMenu(perSceneTransitionMenu);

		/* ---------------------- */

		QAction *multiviewAction = popup.addAction(QTStr("ShowInMultiview"));

		OBSSource source = GetCurrentSceneSource();
		OBSDataAutoRelease data = obs_source_get_private_settings(source);

		obs_data_set_default_bool(data, "show_in_multiview", true);
		bool show = obs_data_get_bool(data, "show_in_multiview");

		multiviewAction->setCheckable(true);
		multiviewAction->setChecked(show);

		auto showInMultiview = [](OBSData data) {
			bool show = obs_data_get_bool(data, "show_in_multiview");
			obs_data_set_bool(data, "show_in_multiview", !show);
			OBSProjector::UpdateMultiviewProjectors();
		};

		connect(multiviewAction, &QAction::triggered, std::bind(showInMultiview, data.Get()));

		copyFilters->setEnabled(obs_source_filter_count(source) > 0);
	}

	popup.addSeparator();

	bool grid = ui->scenes->GetGridMode();

	QAction *gridAction = new QAction(grid ? QTStr("Basic.Main.ListMode") : QTStr("Basic.Main.GridMode"), this);
	connect(gridAction, &QAction::triggered, this, &OBSBasic::GridActionClicked);
	popup.addAction(gridAction);

	popup.exec(QCursor::pos());
}
void OBSBasic::on_scenes_itemDoubleClicked(QListWidgetItem *witem)
{
	if (!witem)
		return;

	if (IsPreviewProgramMode()) {
		bool doubleClickSwitch =
			config_get_bool(App()->GetUserConfig(), "BasicWindow", "TransitionOnDoubleClick");

		if (doubleClickSwitch)
			TransitionClicked();
	}
}

void OBSBasic::on_actionRotate90CW_triggered()
{
	float f90CW = 90.0f;
	OBSDataAutoRelease wrapper = obs_scene_save_transform_states(GetCurrentScene(), false);
	obs_scene_enum_items(GetCurrentScene(), RotateSelectedSources, &f90CW);
	OBSDataAutoRelease rwrapper = obs_scene_save_transform_states(GetCurrentScene(), false);

	std::string undo_data(obs_data_get_json(wrapper));
	std::string redo_data(obs_data_get_json(rwrapper));
	undo_s.add_action(
		QTStr("Undo.Transform.Rotate").arg(obs_source_get_name(obs_scene_get_source(GetCurrentScene()))),
		undo_redo, undo_redo, undo_data, redo_data);
}

void OBSBasic::on_actionRotate90CCW_triggered()
{
	float f90CCW = -90.0f;
	OBSDataAutoRelease wrapper = obs_scene_save_transform_states(GetCurrentScene(), false);
	obs_scene_enum_items(GetCurrentScene(), RotateSelectedSources, &f90CCW);
	OBSDataAutoRelease rwrapper = obs_scene_save_transform_states(GetCurrentScene(), false);

	std::string undo_data(obs_data_get_json(wrapper));
	std::string redo_data(obs_data_get_json(rwrapper));
	undo_s.add_action(
		QTStr("Undo.Transform.Rotate").arg(obs_source_get_name(obs_scene_get_source(GetCurrentScene()))),
		undo_redo, undo_redo, undo_data, redo_data);
}

void OBSBasic::on_actionRotate180_triggered()
{
	float f180 = 180.0f;
	OBSDataAutoRelease wrapper = obs_scene_save_transform_states(GetCurrentScene(), false);
	obs_scene_enum_items(GetCurrentScene(), RotateSelectedSources, &f180);
	OBSDataAutoRelease rwrapper = obs_scene_save_transform_states(GetCurrentScene(), false);

	std::string undo_data(obs_data_get_json(wrapper));
	std::string redo_data(obs_data_get_json(rwrapper));
	undo_s.add_action(
		QTStr("Undo.Transform.Rotate").arg(obs_source_get_name(obs_scene_get_source(GetCurrentScene()))),
		undo_redo, undo_redo, undo_data, redo_data);
}

void OBSBasic::on_actionFlipHorizontal_triggered()
{
	vec2 scale;
	vec2_set(&scale, -1.0f, 1.0f);
	OBSDataAutoRelease wrapper = obs_scene_save_transform_states(GetCurrentScene(), false);
	obs_scene_enum_items(GetCurrentScene(), MultiplySelectedItemScale, &scale);
	OBSDataAutoRelease rwrapper = obs_scene_save_transform_states(GetCurrentScene(), false);

	std::string undo_data(obs_data_get_json(wrapper));
	std::string redo_data(obs_data_get_json(rwrapper));
	undo_s.add_action(
		QTStr("Undo.Transform.HFlip").arg(obs_source_get_name(obs_scene_get_source(GetCurrentScene()))),
		undo_redo, undo_redo, undo_data, redo_data);
}

void OBSBasic::on_actionFlipVertical_triggered()
{
	vec2 scale;
	vec2_set(&scale, 1.0f, -1.0f);
	OBSDataAutoRelease wrapper = obs_scene_save_transform_states(GetCurrentScene(), false);
	obs_scene_enum_items(GetCurrentScene(), MultiplySelectedItemScale, &scale);
	OBSDataAutoRelease rwrapper = obs_scene_save_transform_states(GetCurrentScene(), false);

	std::string undo_data(obs_data_get_json(wrapper));
	std::string redo_data(obs_data_get_json(rwrapper));
	undo_s.add_action(
		QTStr("Undo.Transform.VFlip").arg(obs_source_get_name(obs_scene_get_source(GetCurrentScene()))),
		undo_redo, undo_redo, undo_data, redo_data);
}

void OBSBasic::on_actionFitToScreen_triggered()
{
	obs_bounds_type boundsType = OBS_BOUNDS_SCALE_INNER;
	OBSDataAutoRelease wrapper = obs_scene_save_transform_states(GetCurrentScene(), false);
	obs_scene_enum_items(GetCurrentScene(), CenterAlignSelectedItems, &boundsType);
	OBSDataAutoRelease rwrapper = obs_scene_save_transform_states(GetCurrentScene(), false);

	std::string undo_data(obs_data_get_json(wrapper));
	std::string redo_data(obs_data_get_json(rwrapper));
	undo_s.add_action(
		QTStr("Undo.Transform.FitToScreen").arg(obs_source_get_name(obs_scene_get_source(GetCurrentScene()))),
		undo_redo, undo_redo, undo_data, redo_data);
}

void OBSBasic::on_actionStretchToScreen_triggered()
{
	obs_bounds_type boundsType = OBS_BOUNDS_STRETCH;
	OBSDataAutoRelease wrapper = obs_scene_save_transform_states(GetCurrentScene(), false);
	obs_scene_enum_items(GetCurrentScene(), CenterAlignSelectedItems, &boundsType);
	OBSDataAutoRelease rwrapper = obs_scene_save_transform_states(GetCurrentScene(), false);

	std::string undo_data(obs_data_get_json(wrapper));
	std::string redo_data(obs_data_get_json(rwrapper));
	undo_s.add_action(QTStr("Undo.Transform.StretchToScreen")
				  .arg(obs_source_get_name(obs_scene_get_source(GetCurrentScene()))),
			  undo_redo, undo_redo, undo_data, redo_data);
}

void OBSBasic::on_actionCenterToScreen_triggered()
{
	CenterType centerType = CenterType::Scene;
	OBSDataAutoRelease wrapper = obs_scene_save_transform_states(GetCurrentScene(), false);
	CenterSelectedSceneItems(centerType);
	OBSDataAutoRelease rwrapper = obs_scene_save_transform_states(GetCurrentScene(), false);

	std::string undo_data(obs_data_get_json(wrapper));
	std::string redo_data(obs_data_get_json(rwrapper));
	undo_s.add_action(
		QTStr("Undo.Transform.Center").arg(obs_source_get_name(obs_scene_get_source(GetCurrentScene()))),
		undo_redo, undo_redo, undo_data, redo_data);
}

void OBSBasic::on_actionVerticalCenter_triggered()
{
	CenterType centerType = CenterType::Vertical;
	OBSDataAutoRelease wrapper = obs_scene_save_transform_states(GetCurrentScene(), false);
	CenterSelectedSceneItems(centerType);
	OBSDataAutoRelease rwrapper = obs_scene_save_transform_states(GetCurrentScene(), false);

	std::string undo_data(obs_data_get_json(wrapper));
	std::string redo_data(obs_data_get_json(rwrapper));
	undo_s.add_action(
		QTStr("Undo.Transform.VCenter").arg(obs_source_get_name(obs_scene_get_source(GetCurrentScene()))),
		undo_redo, undo_redo, undo_data, redo_data);
}

void OBSBasic::on_actionHorizontalCenter_triggered()
{
	CenterType centerType = CenterType::Horizontal;
	OBSDataAutoRelease wrapper = obs_scene_save_transform_states(GetCurrentScene(), false);
	CenterSelectedSceneItems(centerType);
	OBSDataAutoRelease rwrapper = obs_scene_save_transform_states(GetCurrentScene(), false);

	std::string undo_data(obs_data_get_json(wrapper));
	std::string redo_data(obs_data_get_json(rwrapper));
	undo_s.add_action(
		QTStr("Undo.Transform.HCenter").arg(obs_source_get_name(obs_scene_get_source(GetCurrentScene()))),
		undo_redo, undo_redo, undo_data, redo_data);
}

void OBSBasic::on_actionSceneFilters_triggered()
{
	OBSSource sceneSource = GetCurrentSceneSource();

	if (sceneSource)
		OpenFilters(sceneSource);
}

void OBSBasic::SetCurrentScene(OBSSource scene, bool force)
{
	if (!IsPreviewProgramMode()) {
		TransitionToScene(scene, force);
	} else {
		OBSSource actualLastScene = OBSGetStrongRef(lastScene);
		if (actualLastScene != scene) {
			if (scene)
				obs_source_inc_showing(scene);
			if (actualLastScene)
				obs_source_dec_showing(actualLastScene);
			lastScene = OBSGetWeakRef(scene);
		}
	}

	if (obs_scene_get_source(GetCurrentScene()) != scene) {
		for (int i = 0; i < ui->scenes->count(); i++) {
			QListWidgetItem *item = ui->scenes->item(i);
			OBSScene itemScene = GetOBSRef<OBSScene>(item);
			obs_source_t *source = obs_scene_get_source(itemScene);

			if (source == scene) {
				ui->scenes->blockSignals(true);
				currentScene = itemScene.Get();
				ui->scenes->setCurrentItem(item);
				ui->scenes->blockSignals(false);

				if (vcamEnabled && vcamConfig.type == VCamOutputType::PreviewOutput)
					outputHandler->UpdateVirtualCamOutputSource();

				OnEvent(OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED);
				break;
			}
		}
	}

	UpdateContextBar(true);
	UpdatePreviewProgramIndicators();

	if (scene) {
		bool userSwitched = (!force && !disableSaving);
		blog(LOG_INFO, "%s to scene '%s'", userSwitched ? "User switched" : "Switched",
		     obs_source_get_name(scene));
	}
}

void OBSBasic::on_actionResetTransform_triggered()
{
	OBSScene scene = GetCurrentScene();

	OBSDataAutoRelease wrapper = obs_scene_save_transform_states(scene, false);
	obs_scene_enum_items(scene, reset_tr, nullptr);
	OBSDataAutoRelease rwrapper = obs_scene_save_transform_states(scene, false);

	std::string undo_data(obs_data_get_json(wrapper));
	std::string redo_data(obs_data_get_json(rwrapper));
	undo_s.add_action(QTStr("Undo.Transform.Reset").arg(obs_source_get_name(obs_scene_get_source(scene))),
			  undo_redo, undo_redo, undo_data, redo_data);

	obs_scene_enum_items(GetCurrentScene(), reset_tr, nullptr);
}
