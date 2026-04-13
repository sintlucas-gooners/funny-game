@tool
extends EditorPlugin

const MainPanelScene = preload("res://addons/assetplus/ui/main_panel.tscn")
const FileSystemContextMenu = preload("res://addons/assetplus/filesystem_context_menu.gd")
const SettingsDialog = preload("res://addons/assetplus/ui/settings_dialog.gd")

var _main_panel: Control
var _context_menu_plugin: EditorContextMenuPlugin


func _enter_tree() -> void:
	_main_panel = MainPanelScene.instantiate()
	_main_panel.set_editor_plugin(self)
	EditorInterface.get_editor_main_screen().add_child(_main_panel)
	_make_visible(false)

	# Register context menu plugin for FileSystem dock
	_context_menu_plugin = FileSystemContextMenu.new()
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _context_menu_plugin)


func _exit_tree() -> void:
	if _context_menu_plugin:
		remove_context_menu_plugin(_context_menu_plugin)
		_context_menu_plugin = null

	if _main_panel:
		_main_panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _main_panel:
		_main_panel.visible = visible
		# Notify main panel about visibility change for deferred filesystem tracking
		_main_panel.set_panel_visible(visible)


func _get_plugin_name() -> String:
	return "AssetPlus"


func _get_plugin_icon() -> Texture2D:
	var icon = load("res://addons/assetplus/iconbw.png")
	if icon:
		return icon
	# Fallback: try to load as ImageTexture directly
	var image = Image.new()
	var path = "res://addons/assetplus/iconbw.png"
	if image.load(ProjectSettings.globalize_path(path)) == OK:
		return ImageTexture.create_from_image(image)
	# Last resort: return editor's default icon
	return EditorInterface.get_editor_theme().get_icon("Node", "EditorIcons")
