class_name RwUnitRegistry
extends RefCounted

var _definitions: Dictionary
var _providers: Dictionary


func register_definition(definition: RwUnitDefinition, provider: RwUnitAssetProvider) -> void:
	if definition == null or provider == null or definition.unit_name.is_empty():
		push_error("Cannot register an incomplete unit definition")
		return
	var key: String = definition.key()
	_definitions[key] = definition
	_providers[key] = provider


func find_definition(source_id: String, unit_name: String) -> RwUnitDefinition:
	return _definitions.get("%s:%s" % [source_id, unit_name]) as RwUnitDefinition


func create_visual(spawn: Dictionary, team_color: Color) -> RwUnitVisual:
	var source_id: String = str(spawn.get("source_id", ""))
	var unit_name: String = str(spawn.get("unit_name", ""))
	var key: String = "%s:%s" % [source_id, unit_name]
	var definition: RwUnitDefinition = _definitions.get(key) as RwUnitDefinition
	var visual: RwUnitVisual = RwUnitVisual.new()
	if definition == null:
		visual.configure_placeholder(unit_name, team_color)
	else:
		definition.configure_visual(visual, _providers[key] as RwUnitAssetProvider, team_color, spawn)
	return visual
