class_name RwUnitTeamColors
extends RefCounted

enum Relation {
	OWN,
	ALLY,
	ENEMY,
	NEUTRAL,
}

const COLORS: Array[Color] = [
	Color("00ff00"),
	Color("d02013"),
	Color("0463f3"),
	Color("ffff40"),
	Color("00ffff"),
	Color("d0f8f7"),
	Color("000000"),
	Color("ff00ea"),
	Color("ff7f18"),
	Color("9368c4"),
]


static func for_team(team: String, players: Array[Dictionary]) -> Color:
	if team.to_lower() == "none":
		return COLORS[5]
	var slot: int = team.to_int()
	for player: Dictionary in players:
		if int(player.get("slot", -1)) != slot:
			continue
		var assigned_color: int = int(player.get("assigned_color", -1))
		return COLORS[posmod(assigned_color if assigned_color >= 0 else slot, COLORS.size())]
	return COLORS[posmod(slot, COLORS.size())]


static func relation_for_team(team: String, players: Array[Dictionary], local_slot: int) -> Relation:
	if not team.is_valid_int() or local_slot < 0:
		return Relation.NEUTRAL
	var slot: int = team.to_int()
	if slot == local_slot:
		return Relation.OWN
	var local_alliance: int = -1
	var other_alliance: int = -2
	for player: Dictionary in players:
		var player_slot: int = int(player.get("slot", -1))
		if player_slot == local_slot:
			local_alliance = int(player.get("color", -1))
		elif player_slot == slot:
			other_alliance = int(player.get("color", -2))
	if local_alliance >= 0 and local_alliance == other_alliance:
		return Relation.ALLY
	return Relation.ENEMY


static func relation_color(relation: Relation) -> Color:
	match relation:
		Relation.OWN:
			return Color("59ed62")
		Relation.ALLY:
			return Color("54bdff")
		Relation.ENEMY:
			return Color("ff665c")
		_:
			return Color("b7b7b7")


static func relation_name(relation: Relation) -> String:
	match relation:
		Relation.OWN:
			return "Own"
		Relation.ALLY:
			return "Ally"
		Relation.ENEMY:
			return "Enemy"
		_:
			return "Neutral"
