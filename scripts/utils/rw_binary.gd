class_name RwBinary
extends RefCounted


static func writer() -> StreamPeerBuffer:
	var stream: StreamPeerBuffer = StreamPeerBuffer.new()
	stream.big_endian = true
	return stream


static func reader(data: PackedByteArray) -> StreamPeerBuffer:
	var stream: StreamPeerBuffer = StreamPeerBuffer.new()
	stream.big_endian = true
	stream.data_array = data
	return stream


static func write_utf(stream: StreamPeerBuffer, value: String) -> void:
	var encoded: PackedByteArray
	for index: int in value.length():
		var codepoint: int = value.unicode_at(index)
		if codepoint > 0xFFFF:
			var offset: int = codepoint - 0x10000
			encoded.append_array(_encode_code_unit(0xD800 | (offset >> 10)))
			encoded.append_array(_encode_code_unit(0xDC00 | (offset & 0x3FF)))
		else:
			encoded.append_array(_encode_code_unit(codepoint))
	assert(encoded.size() <= 65535)
	stream.put_u16(encoded.size())
	stream.put_data(encoded)


static func read_utf(stream: StreamPeerBuffer) -> String:
	var length: int = stream.get_u16()
	if length > stream.get_available_bytes():
		return ""
	var result: Array = stream.get_data(length)
	var data: PackedByteArray = result[1]
	var output: String = ""
	var index: int = 0
	var high_surrogate: int = -1
	while index < data.size():
		var lead: int = data[index]
		var code_unit: int
		if lead < 0x80:
			code_unit = lead
			index += 1
		elif lead < 0xE0 and index + 1 < data.size():
			code_unit = ((lead & 0x1F) << 6) | (data[index + 1] & 0x3F)
			index += 2
		elif index + 2 < data.size():
			code_unit = ((lead & 0x0F) << 12) | ((data[index + 1] & 0x3F) << 6) | (data[index + 2] & 0x3F)
			index += 3
		else:
			break
		if code_unit >= 0xD800 and code_unit <= 0xDBFF:
			high_surrogate = code_unit
			continue
		if code_unit >= 0xDC00 and code_unit <= 0xDFFF and high_surrogate >= 0:
			output += String.chr(0x10000 + ((high_surrogate - 0xD800) << 10) + code_unit - 0xDC00)
			high_surrogate = -1
			continue
		if high_surrogate >= 0:
			output += String.chr(0xFFFD)
			high_surrogate = -1
		output += String.chr(code_unit)
	return output


static func write_nullable_utf(stream: StreamPeerBuffer, value: String, is_null: bool) -> void:
	stream.put_u8(0 if is_null else 1)
	if not is_null:
		write_utf(stream, value)


static func read_nullable_utf(stream: StreamPeerBuffer) -> String:
	if stream.get_u8() == 0:
		return ""
	return read_utf(stream)


static func read_nullable_int(stream: StreamPeerBuffer) -> int:
	if stream.get_u8() == 0:
		return -1
	return stream.get_32()


static func _encode_code_unit(code_unit: int) -> PackedByteArray:
	var encoded: PackedByteArray
	if code_unit >= 0x01 and code_unit <= 0x7F:
		encoded.append(code_unit)
	elif code_unit <= 0x7FF:
		encoded.append(0xC0 | (code_unit >> 6))
		encoded.append(0x80 | (code_unit & 0x3F))
	else:
		encoded.append(0xE0 | (code_unit >> 12))
		encoded.append(0x80 | ((code_unit >> 6) & 0x3F))
		encoded.append(0x80 | (code_unit & 0x3F))
	return encoded
