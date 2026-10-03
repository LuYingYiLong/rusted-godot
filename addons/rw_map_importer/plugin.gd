@tool
extends EditorPlugin

var _import_plugin: EditorImportPlugin


func _enter_tree() -> void:
	_import_plugin = preload("uid://bkv6ee3yp2yha").new()
	add_import_plugin(_import_plugin)


func _exit_tree() -> void:
	remove_import_plugin(_import_plugin)
	_import_plugin = null
