@tool
extends RefCounted

## Handles automatic installation of AssetPlus updates
## Inspired by gdUnit4's update system

const SettingsDialog = preload("res://addons/assetplus/ui/settings_dialog.gd")

const ADDON_PATH = "res://addons/assetplus"
const TEMP_DIR = "user://assetplus_update_temp"

signal progress_updated(message: String)
signal install_completed(success: bool, error_message: String)

var _http_request: HTTPRequest
var _parent_node: Node
var _download_url: String


func install_update(parent: Node, download_url: String) -> void:
	## Start the update installation process
	_parent_node = parent
	_download_url = download_url

	SettingsDialog.debug_print("Starting update installation from: %s" % download_url)
	progress_updated.emit("Downloading update...")

	# Create HTTP request for download
	_http_request = HTTPRequest.new()
	_http_request.download_file = TEMP_DIR.path_join("update.zip")
	parent.add_child(_http_request)
	_http_request.request_completed.connect(_on_download_completed)

	# Ensure temp directory exists
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_DIR))

	var error = _http_request.request(download_url)
	if error != OK:
		_fail("Failed to start download: error %d" % error)


func _on_download_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("Download failed: result %d" % result)
		return

	if code != 200:
		_fail("Download failed: HTTP %d" % code)
		return

	SettingsDialog.debug_print("Download completed, extracting...")
	progress_updated.emit("Extracting update...")

	# Extract the ZIP
	var zip_path = ProjectSettings.globalize_path(TEMP_DIR.path_join("update.zip"))
	var extract_path = ProjectSettings.globalize_path(TEMP_DIR.path_join("extracted"))

	# Create extraction directory
	DirAccess.make_dir_recursive_absolute(extract_path)

	var zip = ZIPReader.new()
	var err = zip.open(zip_path)
	if err != OK:
		_fail("Failed to open ZIP file: error %d" % err)
		return

	# Extract all files
	var files = zip.get_files()
	for file_path in files:
		if file_path.ends_with("/"):
			# Directory
			DirAccess.make_dir_recursive_absolute(extract_path.path_join(file_path))
		else:
			# File
			var dir_path = extract_path.path_join(file_path.get_base_dir())
			DirAccess.make_dir_recursive_absolute(dir_path)
			var content = zip.read_file(file_path)
			var file = FileAccess.open(extract_path.path_join(file_path), FileAccess.WRITE)
			if file:
				file.store_buffer(content)
				file.close()

	zip.close()

	SettingsDialog.debug_print("Extraction completed, installing...")
	progress_updated.emit("Installing update...")

	# Find the addon folder in extracted files (might be nested)
	var addon_source = _find_addon_folder(extract_path)
	if addon_source.is_empty():
		_fail("Could not find addon folder in downloaded package")
		return

	# Verify the source has required files before proceeding
	var plugin_cfg = addon_source.path_join("plugin.cfg")
	if not FileAccess.file_exists(plugin_cfg):
		_fail("Invalid addon: plugin.cfg not found in %s" % addon_source)
		return

	SettingsDialog.debug_print("Found valid addon at: %s" % addon_source)

	# Disable the plugin (frees file locks)
	_disable_plugin()

	# Delete old addon folder
	var addon_dest = ProjectSettings.globalize_path(ADDON_PATH)
	if DirAccess.dir_exists_absolute(addon_dest):
		SettingsDialog.debug_print("Deleting old addon at: %s" % addon_dest)
		_delete_directory_recursive(addon_dest)

	# Copy new addon folder
	SettingsDialog.debug_print("Copying from %s to %s" % [addon_source, addon_dest])
	var copy_success = _copy_directory_recursive(addon_source, addon_dest)

	# Verify copy was successful
	var dest_plugin_cfg = addon_dest.path_join("plugin.cfg")
	if not FileAccess.file_exists(dest_plugin_cfg):
		_fail("Copy failed: plugin.cfg not found in destination. Please reinstall manually.")
		return

	SettingsDialog.debug_print("Copy verified, plugin.cfg exists at destination")

	# Re-enable the plugin in settings (before restart)
	_enable_plugin()

	# Cleanup temp files
	_delete_directory_recursive(ProjectSettings.globalize_path(TEMP_DIR))

	SettingsDialog.debug_print("Update installed successfully, restarting editor...")
	progress_updated.emit("Restarting Godot...")

	install_completed.emit(true, "")

	# Small delay to let UI update
	await _parent_node.get_tree().create_timer(0.5).timeout

	# Restart Godot
	EditorInterface.restart_editor(true)


func _find_addon_folder(base_path: String) -> String:
	## Find the assetplus addon folder in extracted files
	## It might be directly in base_path or nested (e.g., repo-main/addons/assetplus)

	# Check direct path
	var direct = base_path.path_join("addons/assetplus")
	if DirAccess.dir_exists_absolute(direct):
		return direct

	# Check one level deep (common for GitHub ZIPs: repo-branch/addons/...)
	var dir = DirAccess.open(base_path)
	if dir:
		dir.list_dir_begin()
		var folder = dir.get_next()
		while folder != "":
			if dir.current_is_dir() and not folder.begins_with("."):
				var nested = base_path.path_join(folder).path_join("addons/assetplus")
				if DirAccess.dir_exists_absolute(nested):
					return nested
			folder = dir.get_next()
		dir.list_dir_end()

	return ""


func _disable_plugin() -> void:
	## Disable the plugin to free file locks
	var enabled_plugins: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	var new_plugins: PackedStringArray = []

	for plugin in enabled_plugins:
		if plugin != "res://addons/assetplus/plugin.cfg":
			new_plugins.append(plugin)

	ProjectSettings.set_setting("editor_plugins/enabled", new_plugins)
	SettingsDialog.debug_print("Plugin disabled for update")


func _enable_plugin() -> void:
	## Re-enable the plugin in project settings
	var enabled_plugins: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())

	if not enabled_plugins.has("res://addons/assetplus/plugin.cfg"):
		enabled_plugins.append("res://addons/assetplus/plugin.cfg")

	ProjectSettings.set_setting("editor_plugins/enabled", enabled_plugins)
	ProjectSettings.save()
	SettingsDialog.debug_print("Plugin re-enabled in settings")


func _delete_directory_recursive(path: String) -> void:
	## Recursively delete a directory and all its contents
	var dir = DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path = path.path_join(file_name)
			if dir.current_is_dir():
				_delete_directory_recursive(full_path)
			else:
				dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Remove the now-empty directory
	DirAccess.remove_absolute(path)


func _copy_directory_recursive(from: String, to: String) -> bool:
	## Recursively copy a directory. Returns true on success.
	var err = DirAccess.make_dir_recursive_absolute(to)
	if err != OK and err != ERR_ALREADY_EXISTS:
		SettingsDialog.debug_print("Failed to create directory: %s (error %d)" % [to, err])
		return false

	var dir = DirAccess.open(from)
	if not dir:
		SettingsDialog.debug_print("Failed to open source directory: %s" % from)
		return false

	dir.list_dir_begin()
	var file_name = dir.get_next()
	var success = true
	while file_name != "":
		if file_name != "." and file_name != "..":
			var from_path = from.path_join(file_name)
			var to_path = to.path_join(file_name)
			if dir.current_is_dir():
				if not _copy_directory_recursive(from_path, to_path):
					success = false
			else:
				var copy_err = dir.copy(from_path, to_path)
				if copy_err != OK:
					SettingsDialog.debug_print("Failed to copy file: %s -> %s (error %d)" % [from_path, to_path, copy_err])
					success = false
		file_name = dir.get_next()
	dir.list_dir_end()
	return success


func _fail(message: String) -> void:
	SettingsDialog.debug_print("Update failed: %s" % message)
	_cleanup()
	install_completed.emit(false, message)


func _cleanup() -> void:
	if _http_request and is_instance_valid(_http_request):
		_http_request.queue_free()
		_http_request = null
