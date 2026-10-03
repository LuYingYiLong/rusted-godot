class_name RwBattleCommandWriter
extends RefCounted

const COMMAND_BLOCK_NAME: String = "c"
const MOVE_COMMAND_TYPE: int = 0


static func write_move(team_slot: int, unit_ids: Array[int], target: Vector2) -> PackedByteArray:
	var command: StreamPeerBuffer = RwBinary.writer()
	command.put_8(team_slot)
	command.put_u8(1)
	command.put_32(MOVE_COMMAND_TYPE)
	command.put_32(-1)
	command.put_float(target.x)
	command.put_float(target.y)
	command.put_64(-1)
	command.put_8(1)
	command.put_float(-1.0)
	command.put_float(-1.0)
	command.put_u8(0)
	command.put_u8(0)
	command.put_u8(0)
	command.put_u8(0)
	command.put_u8(0)
	command.put_u8(0)
	command.put_32(-1)
	command.put_32(-1)
	command.put_u8(0)
	command.put_u8(0)
	command.put_32(unit_ids.size())
	for unit_id: int in unit_ids:
		command.put_64(unit_id)
	command.put_u8(0)
	command.put_u8(0)
	command.put_64(-1)
	RwBinary.write_utf(command, "-1")
	command.put_u8(0)
	command.put_u16(0)
	command.put_u8(0)
	command.put_32(0)
	command.put_u8(0)
	var packet: StreamPeerBuffer = RwBinary.writer()
	RwBinary.write_utf(packet, COMMAND_BLOCK_NAME)
	packet.put_32(command.data_array.size())
	packet.put_data(command.data_array)
	return packet.data_array
