class_name RwResourceCatalog
extends RefCounted

var _definitions: Dictionary
var _team_resources: Array[RwResourceDefinition]


static func create_vanilla() -> RwResourceCatalog:
	var catalog: RwResourceCatalog = RwResourceCatalog.new()
	var credits: RwResourceDefinition = RwResourceDefinition.new()
	credits.resource_id = "credits"
	credits.display_name = "Credits"
	credits.scope = RwResourceDefinition.Scope.TEAM
	credits.display_when_zero = true
	catalog.register_definition(credits)
	return catalog


func register_definition(definition: RwResourceDefinition) -> void:
	assert(definition != null)
	assert(not definition.resource_id.is_empty())
	assert(not _definitions.has(definition.resource_id))
	_definitions[definition.resource_id] = definition
	if definition.scope != RwResourceDefinition.Scope.TEAM:
		return
	var index: int = 0
	while index < _team_resources.size() and _team_resources[index].display_position <= definition.display_position:
		index += 1
	_team_resources.insert(index, definition)


func find_definition(resource_id: String) -> RwResourceDefinition:
	return _definitions.get(resource_id) as RwResourceDefinition


func format_team_balances(balances: Dictionary) -> String:
	var lines: Array[String]
	for definition: RwResourceDefinition in _team_resources:
		if not definition.display_in_hud or not balances.has(definition.resource_id):
			continue
		var amount: float = float(balances[definition.resource_id])
		if amount != 0.0 or definition.display_when_zero:
			lines.append(definition.format_balance(amount))
	return "  |  ".join(lines)
