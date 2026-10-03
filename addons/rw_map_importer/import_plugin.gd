@tool
extends EditorImportPlugin


func _get_importer_name() -> String:
	return "rusted_godot.rw_map_xml"


func _get_visible_name() -> String:
	return "Rusted Warfare Map XML"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["tmx", "tsx",])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "Resource"


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset_index: int) -> String:
	return "Default"


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []


func _import(source_file: String, save_path: String, _options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var source: FileAccess = FileAccess.open(source_file, FileAccess.READ)
	if source == null:
		return FileAccess.get_open_error()
	var xml_text: String = source.get_as_text()
	var parser: XMLParser = XMLParser.new()
	if parser.open_buffer(xml_text.to_utf8_buffer()) != OK:
		return ERR_PARSE_ERROR
	var expected_root: String = "map" if source_file.get_extension().to_lower() == "tmx" else "tileset"
	var found_root: bool
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and not found_root:
			if parser.get_node_name() != expected_root:
				return ERR_PARSE_ERROR
			found_root = true
	if not found_root:
		return ERR_PARSE_ERROR
	var document: RwXmlDocument = RwXmlDocument.new()
	document.xml_text = xml_text
	return ResourceSaver.save(document, save_path + ".res")
