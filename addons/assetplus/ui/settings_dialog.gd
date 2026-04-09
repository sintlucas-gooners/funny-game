@tool
extends AcceptDialog

## Settings dialog for Asset Store plugin

const GLOBAL_APP_FOLDER = "GodotAssetPlus"
const CONFIG_FILE = "settings.cfg"
const ICON_CACHE_FOLDER = "icon_cache"

signal clear_icon_cache_requested
const UpdateChecker = preload("res://addons/assetplus/ui/update_checker.gd")


static func _get_global_config_path() -> String:
	## Returns path to global settings file (shared between all projects)
	## Uses system config directory: AppData/Roaming on Windows, ~/.config on Linux, ~/Library/Application Support on macOS
	var config_dir = OS.get_config_dir()
	var app_dir = config_dir.path_join(GLOBAL_APP_FOLDER)

	if not DirAccess.dir_exists_absolute(app_dir):
		DirAccess.make_dir_recursive_absolute(app_dir)

	return app_dir.path_join(CONFIG_FILE)


# Debug print levels
enum DebugLevel { OFF, MINIMAL, FULL }

# Default values
var _settings: Dictionary = {
	"default_export_path": "",
	"global_asset_folder": "",
	"debug_level": DebugLevel.OFF,
	"enabled_stores": {
		"godot_assetlib": true,
		"godot_beta": true,
		"godot_shaders": true
	}
}

# UI elements
var _export_path_edit: LineEdit
var _export_path_btn: Button
var _global_folder_edit: LineEdit
var _global_folder_btn: Button
var _debug_option: OptionButton
var _cache_size_label: Label
var _clear_cache_btn: Button
var _store_checkboxes: Dictionary = {}
var _version_label: Label
var _check_updates_btn: Button
var _auto_update_checkbox: CheckBox
var _update_checker: RefCounted


func _init() -> void:
	title = "Asset Store Settings"
	size = Vector2i(500, 400)
	ok_button_text = "Save"


func _ready() -> void:
	_load_settings()
	_build_ui()
	confirmed.connect(_on_save)


func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)
	add_child(main_vbox)

	# Export settings section
	var export_section = _create_section("Export Settings")
	main_vbox.add_child(export_section)

	var export_grid = GridContainer.new()
	export_grid.columns = 2
	export_grid.add_theme_constant_override("h_separation", 10)
	export_grid.add_theme_constant_override("v_separation", 8)
	export_section.add_child(export_grid)

	var export_label = Label.new()
	export_label.text = "Default Export Path:"
	export_grid.add_child(export_label)

	var path_hbox = HBoxContainer.new()
	path_hbox.add_theme_constant_override("separation", 5)
	path_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_grid.add_child(path_hbox)

	_export_path_edit = LineEdit.new()
	_export_path_edit.placeholder_text = "Leave empty for system default"
	_export_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_export_path_edit.text = _settings.get("default_export_path", "")
	path_hbox.add_child(_export_path_edit)

	_export_path_btn = Button.new()
	_export_path_btn.text = "Browse..."
	_export_path_btn.pressed.connect(_on_browse_export_path)
	path_hbox.add_child(_export_path_btn)

	# Global Asset Folder
	var global_label = Label.new()
	global_label.text = "Global Asset Folder:"
	export_grid.add_child(global_label)

	var global_hbox = HBoxContainer.new()
	global_hbox.add_theme_constant_override("separation", 5)
	global_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_grid.add_child(global_hbox)

	_global_folder_edit = LineEdit.new()
	_global_folder_edit.placeholder_text = "Folder for shared local assets"
	_global_folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_global_folder_edit.text = _settings.get("global_asset_folder", "")
	global_hbox.add_child(_global_folder_edit)

	_global_folder_btn = Button.new()
	_global_folder_btn.text = "Browse..."
	_global_folder_btn.pressed.connect(_on_browse_global_folder)
	global_hbox.add_child(_global_folder_btn)

	# Global folder description
	var global_desc = Label.new()
	global_desc.text = "Assets stored here can be imported across multiple projects"
	global_desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	global_desc.add_theme_font_size_override("font_size", 11)
	export_section.add_child(global_desc)

	main_vbox.add_child(HSeparator.new())

	# Debug settings section
	var debug_section = _create_section("Debug Settings")
	main_vbox.add_child(debug_section)

	var debug_hbox = HBoxContainer.new()
	debug_hbox.add_theme_constant_override("separation", 10)
	debug_section.add_child(debug_hbox)

	var debug_label = Label.new()
	debug_label.text = "Debug Output:"
	debug_hbox.add_child(debug_label)

	_debug_option = OptionButton.new()
	_debug_option.add_item("Off", DebugLevel.OFF)
	_debug_option.add_item("Minimal", DebugLevel.MINIMAL)
	_debug_option.add_item("Full", DebugLevel.FULL)
	_debug_option.selected = _settings.get("debug_level", DebugLevel.OFF)
	debug_hbox.add_child(_debug_option)

	var debug_desc = Label.new()
	debug_desc.text = "Controls debug messages in Output panel"
	debug_desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	debug_desc.add_theme_font_size_override("font_size", 11)
	debug_section.add_child(debug_desc)

	# Icon cache info
	var cache_hbox = HBoxContainer.new()
	cache_hbox.add_theme_constant_override("separation", 10)
	debug_section.add_child(cache_hbox)

	_cache_size_label = Label.new()
	_cache_size_label.text = "Icon cache: calculating..."
	_cache_size_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_cache_size_label.add_theme_font_size_override("font_size", 11)
	cache_hbox.add_child(_cache_size_label)

	_clear_cache_btn = Button.new()
	_clear_cache_btn.text = "Clear Cache"
	_clear_cache_btn.tooltip_text = "Delete all cached icon images"
	_clear_cache_btn.pressed.connect(_on_clear_cache)
	cache_hbox.add_child(_clear_cache_btn)

	# Calculate cache size async
	_update_cache_size_label()

	main_vbox.add_child(HSeparator.new())

	# Store settings section
	var store_section = _create_section("Available Stores")
	main_vbox.add_child(store_section)

	var store_desc = Label.new()
	store_desc.text = "Enable or disable store sources:"
	store_desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	store_section.add_child(store_desc)

	var store_list = VBoxContainer.new()
	store_list.add_theme_constant_override("separation", 8)
	store_section.add_child(store_list)

	# Add store checkboxes
	var stores = [
		["godot_assetlib", "Godot Asset Library", "Official Godot asset repository"],
		["godot_beta", "Godot Store Beta", "New Godot store (beta)"],
		["godot_shaders", "Godot Shaders", "Community shader repository"]
	]

	var enabled_stores = _settings.get("enabled_stores", {})

	for store_info in stores:
		var store_id = store_info[0]
		var store_name = store_info[1]
		var store_desc_text = store_info[2]

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		store_list.add_child(hbox)

		var checkbox = CheckBox.new()
		checkbox.text = store_name
		checkbox.button_pressed = enabled_stores.get(store_id, true)
		checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(checkbox)

		var desc = Label.new()
		desc.text = store_desc_text
		desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		desc.add_theme_font_size_override("font_size", 12)
		hbox.add_child(desc)

		_store_checkboxes[store_id] = checkbox

	main_vbox.add_child(HSeparator.new())

	# Version and Updates section
	var version_section = _create_section("About")
	main_vbox.add_child(version_section)

	var version_hbox = HBoxContainer.new()
	version_hbox.add_theme_constant_override("separation", 15)
	version_section.add_child(version_hbox)

	_version_label = Label.new()
	_version_label.text = "AssetPlus v%s" % _get_plugin_version()
	version_hbox.add_child(_version_label)

	_check_updates_btn = Button.new()
	_check_updates_btn.text = "Check for Updates"
	_check_updates_btn.pressed.connect(_on_check_updates)
	version_hbox.add_child(_check_updates_btn)

	# Auto-update checkbox
	var auto_update_hbox = HBoxContainer.new()
	auto_update_hbox.add_theme_constant_override("separation", 10)
	version_section.add_child(auto_update_hbox)

	_auto_update_checkbox = CheckBox.new()
	_auto_update_checkbox.text = "Check for updates at startup"
	_auto_update_checkbox.button_pressed = not _settings.get("auto_update_disabled", false)
	auto_update_hbox.add_child(_auto_update_checkbox)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(spacer)

	# Bottom bar with info and open folder button
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(bottom_hbox)

	# Info label
	var info = Label.new()
	info.text = "Settings are shared between all projects"
	info.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	info.add_theme_font_size_override("font_size", 11)
	bottom_hbox.add_child(info)

	# Open config folder button
	var open_folder_btn = Button.new()
	open_folder_btn.text = "Open Config Folder"
	open_folder_btn.tooltip_text = "Open the folder where settings and favorites are stored"
	open_folder_btn.pressed.connect(_on_open_config_folder)
	bottom_hbox.add_child(open_folder_btn)


func _create_section(title_text: String) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var title_label = Label.new()
	title_label.text = title_text
	title_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title_label)

	return vbox


func _on_browse_export_path() -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = "Select Default Export Folder"

	if not _export_path_edit.text.is_empty():
		dialog.current_dir = _export_path_edit.text

	dialog.dir_selected.connect(func(dir: String):
		_export_path_edit.text = dir
		dialog.queue_free()
	)

	dialog.canceled.connect(func():
		dialog.queue_free()
	)

	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


func _on_browse_global_folder() -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = "Select Global Asset Folder"

	if not _global_folder_edit.text.is_empty():
		dialog.current_dir = _global_folder_edit.text

	dialog.dir_selected.connect(func(dir: String):
		_global_folder_edit.text = dir
		dialog.queue_free()
	)

	dialog.canceled.connect(func():
		dialog.queue_free()
	)

	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


func _on_save() -> void:
	_settings["default_export_path"] = _export_path_edit.text.strip_edges()
	_settings["global_asset_folder"] = _global_folder_edit.text.strip_edges()
	_settings["debug_level"] = _debug_option.get_selected_id()
	_settings["auto_update_disabled"] = not _auto_update_checkbox.button_pressed

	var enabled_stores: Dictionary = {}
	for store_id in _store_checkboxes:
		enabled_stores[store_id] = _store_checkboxes[store_id].button_pressed
	_settings["enabled_stores"] = enabled_stores

	_save_settings()


func _load_settings() -> void:
	if not FileAccess.file_exists(_get_global_config_path()):
		return

	var file = FileAccess.open(_get_global_config_path(), FileAccess.READ)
	if file == null:
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.data
		if data is Dictionary:
			# Merge with defaults
			for key in data:
				_settings[key] = data[key]

	file.close()


func _save_settings() -> void:
	var file = FileAccess.open(_get_global_config_path(), FileAccess.WRITE)
	if file == null:
		push_error("AssetPlus: Failed to save settings")
		return

	file.store_string(JSON.stringify(_settings, "\t"))
	file.close()
	debug_print("Settings saved")


func _on_open_config_folder() -> void:
	var config_path = _get_global_config_path()
	var folder_path = config_path.get_base_dir()
	OS.shell_open(folder_path)


func _get_icon_cache_dir() -> String:
	var config_dir = OS.get_config_dir()
	return config_dir.path_join(GLOBAL_APP_FOLDER).path_join(ICON_CACHE_FOLDER)


func _get_cache_size() -> int:
	## Returns total size of icon cache in bytes
	var cache_dir = _get_icon_cache_dir()
	if not DirAccess.dir_exists_absolute(cache_dir):
		return 0

	var total_size = 0
	var dir = DirAccess.open(cache_dir)
	if not dir:
		return 0

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".png"):
			var file_path = cache_dir.path_join(file_name)
			var file = FileAccess.open(file_path, FileAccess.READ)
			if file:
				total_size += file.get_length()
				file.close()
		file_name = dir.get_next()
	dir.list_dir_end()

	return total_size


func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	else:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))


func _update_cache_size_label() -> void:
	var size = _get_cache_size()
	_cache_size_label.text = "Icon cache: %s" % _format_size(size)


func _on_clear_cache() -> void:
	clear_icon_cache_requested.emit()
	_update_cache_size_label()


func _get_plugin_version() -> String:
	var config = ConfigFile.new()
	var err = config.load("res://addons/assetplus/plugin.cfg")
	if err != OK:
		return "?"
	return config.get_value("plugin", "version", "?")


func _on_check_updates() -> void:
	_check_updates_btn.disabled = true
	_check_updates_btn.text = "Checking..."

	_update_checker = UpdateChecker.new()
	_update_checker.update_available.connect(_on_update_available)
	_update_checker.check_complete.connect(_on_check_complete)
	_update_checker.check_for_updates(self)


func _on_update_available(current_version: String, new_version: String, browse_url: String, download_url: String, release_notes: String = "") -> void:
	# Show update dialog
	var UpdateDialog = load("res://addons/assetplus/ui/update_dialog.gd")
	var dialog = UpdateDialog.new()
	dialog.setup(current_version, new_version, browse_url, download_url, release_notes)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()


func _on_check_complete(has_update: bool) -> void:
	_check_updates_btn.disabled = false
	_check_updates_btn.text = "Check for Updates"

	if not has_update:
		# Show brief message that we're up to date
		var dialog = AcceptDialog.new()
		dialog.title = "Up to Date"
		dialog.dialog_text = "AssetPlus is up to date!"
		dialog.confirmed.connect(func(): dialog.queue_free())
		dialog.canceled.connect(func(): dialog.queue_free())
		EditorInterface.get_base_control().add_child(dialog)
		dialog.popup_centered()


## Static method to get current settings
static func get_settings() -> Dictionary:
	var settings: Dictionary = {
		"default_export_path": "",
		"global_asset_folder": "",
		"debug_level": 0,  # DebugLevel.OFF
		"enabled_stores": {
			"godot_assetlib": true,
			"godot_beta": true,
			"godot_shaders": true
		}
	}

	if not FileAccess.file_exists(_get_global_config_path()):
		return settings

	var file = FileAccess.open(_get_global_config_path(), FileAccess.READ)
	if file == null:
		return settings

	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.data
		if data is Dictionary:
			for key in data:
				settings[key] = data[key]

	file.close()
	return settings


## Static method to save settings
static func save_settings(settings: Dictionary) -> void:
	var file = FileAccess.open(_get_global_config_path(), FileAccess.WRITE)
	if file == null:
		push_error("AssetPlus: Failed to save settings")
		return

	file.store_string(JSON.stringify(settings, "\t"))
	file.close()
	debug_print("Settings saved")


## Static method to get debug level
static func get_debug_level() -> int:
	return get_settings().get("debug_level", 0)


## Static helper for debug printing - minimal level (important messages)
static func debug_print(message: String) -> void:
	if get_debug_level() >= 1:  # MINIMAL or FULL
		print("AssetPlus: ", message)


## Static helper for verbose debug printing - full level only
static func debug_print_verbose(message: String) -> void:
	if get_debug_level() >= 2:  # FULL only
		print("AssetPlus [verbose]: ", message)