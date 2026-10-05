#include "rw_game_math.h"

#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>

#include <godot_cpp/core/class_db.hpp>

namespace {
	static_assert(sizeof(float) == 4 && std::numeric_limits<float>::is_iec559, "RW requires IEEE 754 binary32");

#include "rw_math_tables.inc"
	constexpr const uint32_t* ANGLE_TABLES[] = {
		ANGLE_BITS_0,
		ANGLE_BITS_1,
		ANGLE_BITS_2,
		ANGLE_BITS_3,
		ANGLE_BITS_4,
		ANGLE_BITS_5,
		ANGLE_BITS_6,
		ANGLE_BITS_7,
	};

	float from_bits(uint32_t bits) {
		float value;
		std::memcpy(&value, &bits, sizeof(value));
		return value;
	}

	// 保持原版线段相交判定的单精度乘减与除法顺序
	bool segments_intersect(float ax, float ay, float bx, float by, float cx, float cy, float dx, float dy) {
		const float denominator = (dy - cy) * (bx - ax) - (dx - cx) * (by - ay);
		const float first_numerator = (dx - cx) * (ay - cy) - (dy - cy) * (ax - cx);
		const float second_numerator = (bx - ax) * (ay - cy) - (by - ay) * (ax - cx);
		if (denominator == 0.0f) {
			return false;
		}
		const float first = first_numerator / denominator;
		const float second = second_numerator / denominator;
		return first >= 0.0f && first <= 1.0f && second >= 0.0f && second <= 1.0f;
	}

	float approach(float current, float target, float step) {
		if (current > target + step) {
			return current - step;
		}
		if (current < target - step) {
			return current + step;
		}
		return target;
	}

	float rotate(float current, float step) {
		current += step;
		if (current > 180.0f) {
			current -= 360.0f;
		}
		if (current < -180.0f) {
			current += 360.0f;
		}
		return current;
	}

	// Java 浮点转整数会对 NaN 与超界值作规定处理，避免 C++ 转换产生未定义行为
	int32_t java_int(double value) {
		if (std::isnan(value)) {
			return 0;
		}
		if (value >= std::numeric_limits<int32_t>::max()) {
			return std::numeric_limits<int32_t>::max();
		}
		if (value <= std::numeric_limits<int32_t>::min()) {
			return std::numeric_limits<int32_t>::min();
		}
		return static_cast<int32_t>(value);
	}

	float angle_lookup(int table, float numerator, float denominator) {
		const float product = 1024.0f * numerator;
		const float ratio = product / denominator;
		const int32_t index = java_int(static_cast<double>(ratio) + 0.5);
		if (index < 0 || index > 1024) {
			return std::numeric_limits<float>::quiet_NaN();
		}
		return from_bits(ANGLE_TABLES[table][index]);
	}

	float fast_angle(float y, float x) {
		if (x >= 0.0f) {
			if (y >= 0.0f) {
				return x >= y ? angle_lookup(0, y, x) : angle_lookup(1, x, y);
			}
			return x >= -y ? angle_lookup(2, -y, x) : angle_lookup(3, x, -y);
		}
		if (y >= 0.0f) {
			return -x >= y ? angle_lookup(4, y, -x) : angle_lookup(5, -x, y);
		}
		return x <= y ? angle_lookup(6, -y, -x) : angle_lookup(7, -x, -y);
	}
}

namespace godot {
	double RwGameMath::float32(double value) {
		return static_cast<float>(value);
	}

	Vector2 RwGameMath::path_direction(const Vector2& start_position, const Vector2& target_position) {
		return direction_for_angle(direction_degrees(start_position, target_position));
	}

	double RwGameMath::direction_degrees(const Vector2& start_position, const Vector2& target_position) {
		const float y = static_cast<float>(target_position.y) - static_cast<float>(start_position.y);
		const float x = static_cast<float>(target_position.x) - static_cast<float>(start_position.x);
		const float table_angle = fast_angle(y, x);
		// 超大输入造成查表索引溢出时保持原版的 atan2 回退路径
		const float angle = std::isnan(table_angle) ? static_cast<float>(std::atan2(static_cast<double>(y), static_cast<double>(x))) : table_angle;
		return angle * 57.29578f;
	}

	double RwGameMath::signed_angle_delta(double current_degrees, double target_degrees) {
		const float current = std::fmod(static_cast<float>(current_degrees), 360.0f);
		const float target = std::fmod(static_cast<float>(target_degrees), 360.0f);
		float delta = target - current;
		if (delta > 180.0f) {
			delta -= 360.0f;
		}
		if (delta < -180.0f) {
			delta += 360.0f;
		}
		return delta;
	}

	Vector2 RwGameMath::direction_for_angle(double angle_degrees) {
		const float scaled = static_cast<float>(angle_degrees) * 22.755556f;
		const uint32_t index = static_cast<uint32_t>(java_int(scaled)) & 8191u;
		return Vector2(from_bits(COS_BITS[index]), from_bits(SIN_BITS[index]));
	}

	Vector2 RwGameMath::factory_exit_target(const Vector2& factory_position, double factory_radius) {
		const Vector2 facing = direction_for_angle(90.0);
		const float distance = static_cast<float>(factory_radius) * 3.0f;
		const float offset_x = static_cast<float>(facing.x) * distance;
		const float offset_y = static_cast<float>(facing.y) * distance;
		const float target_x = static_cast<float>(factory_position.x) + offset_x;
		const float target_y = static_cast<float>(factory_position.y) + offset_y;
		return Vector2(target_x - static_cast<float>(facing.y), target_y + static_cast<float>(facing.x));
	}

	Vector3 RwGameMath::turn_toward(double current_degrees, double target_degrees, double velocity, double speed, double acceleration, double delta) {
		const float current = static_cast<float>(current_degrees);
		const float difference = static_cast<float>(signed_angle_delta(current, target_degrees));
		float turn_velocity = static_cast<float>(velocity);
		if (std::fabs(difference) < 0.01f) {
			return Vector3(current, turn_velocity, 0.0f);
		}
		const float direction = difference > 0.0f ? 1.0f : -1.0f;
		const float turn_acceleration = static_cast<float>(acceleration);
		const float time_step = static_cast<float>(delta);
		float turn_step;
		if (turn_acceleration > 0.0f) {
			const float braking_angle = std::fabs(turn_velocity) / turn_acceleration;
			const float requested = direction * (std::fabs(difference) < braking_angle ? turn_acceleration : static_cast<float>(speed));
			turn_velocity = approach(turn_velocity, requested, turn_acceleration * time_step);
			turn_step = turn_velocity * time_step;
		} else {
			const float requested = direction * static_cast<float>(speed);
			turn_step = requested * time_step;
		}
		if (std::fabs(turn_step) > std::fabs(difference)) {
			turn_velocity = 0.0f;
			turn_step = difference;
		}
		return Vector3(rotate(current, turn_step), turn_velocity, turn_step);
	}

	double RwGameMath::advance_speed(double current, double target, double acceleration, double delta) {
		const float step = static_cast<float>(acceleration) * static_cast<float>(delta);
		return approach(static_cast<float>(current), static_cast<float>(target), step);
	}

	Vector2 RwGameMath::movement_position(const Vector2& position, double angle_degrees, double speed, double factor, double delta) {
		const float rate = static_cast<float>(speed) * static_cast<float>(factor);
		const float step = rate * static_cast<float>(delta);
		const Vector2 direction = direction_for_angle(angle_degrees);
		const float offset_x = static_cast<float>(direction.x) * step;
		const float offset_y = static_cast<float>(direction.y) * step;
		return Vector2(static_cast<float>(position.x) + offset_x, static_cast<float>(position.y) + offset_y);
	}

	Vector4 RwGameMath::collision_offsets(const Vector2& separation, const Vector2& direction, double radius_sum, int64_t priority, double delta, double actor_mass, double other_mass) {
		const float x = static_cast<float>(separation.x);
		const float y = static_cast<float>(separation.y);
		const float squared_distance = x * x + y * y;
		const float distance = static_cast<float>(std::sqrt(static_cast<double>(squared_distance)));
		float push = static_cast<float>(radius_sum) - distance;
		push += 0.001f;
		if (push <= 0.0f) {
			return Vector4();
		}
		if (priority != 0) {
			const float reduced = push / static_cast<float>(priority) * static_cast<float>(delta);
			push = reduced > push ? push : reduced;
		}
		push *= 0.95f;
		if (push > 1.0f) {
			push *= 0.7f;
		}
		if (push > 3.0f) {
			push = 3.0f + (push - 3.0f) * 0.7f;
		}
		if (push > 6.0f) {
			push = 6.0f + (push - 6.0f) * 0.7f;
		}
		if (push > 10.0f) {
			push = 10.0f + (push - 10.0f) * 0.7f;
		}
		const float first_mass = static_cast<float>(actor_mass);
		const float second_mass = static_cast<float>(other_mass);
		const float fraction = first_mass / (first_mass + second_mass);
		const float complement = 1.0f - fraction;
		const float other_push = push * fraction;
		const float actor_push = push * complement;
		return Vector4(-static_cast<float>(direction.x) * actor_push, -static_cast<float>(direction.y) * actor_push,
			static_cast<float>(direction.x) * other_push, static_cast<float>(direction.y) * other_push);
	}

	Vector3 RwGameMath::terrain_slide_position(const Vector2& start_position, const Vector2& end_position, const Vector2& tile_size, const Vector2& blocked_cell, int64_t open_neighbors) {
		const float width = static_cast<float>(tile_size.x);
		const float height = static_cast<float>(tile_size.y);
		const float inverse_width = 1.0f / width;
		const float inverse_height = 1.0f / height;
		const float ax = static_cast<float>(start_position.x) * inverse_width;
		const float ay = static_cast<float>(start_position.y) * inverse_height;
		const float bx = static_cast<float>(end_position.x) * inverse_width;
		const float by = static_cast<float>(end_position.y) * inverse_height;
		const float left = static_cast<float>(blocked_cell.x);
		const float top = static_cast<float>(blocked_cell.y);
		const float right = left + 1.0f;
		const float bottom = top + 1.0f;
		int edge = -1;
		if (ay < by) {
			if ((open_neighbors & 1) != 0 && segments_intersect(ax, ay, bx, by, left, top, right, top)) {
				edge = 3;
			}
		} else if ((open_neighbors & 2) != 0 && segments_intersect(ax, ay, bx, by, left, bottom, right, bottom)) {
			edge = 1;
		}
		if (ax < bx) {
			if ((open_neighbors & 4) != 0 && segments_intersect(ax, ay, bx, by, left, top, left, bottom)) {
				edge = 2;
			}
		} else if ((open_neighbors & 8) != 0 && segments_intersect(ax, ay, bx, by, right, top, right, bottom)) {
			edge = 0;
		}
		if (edge < 0) {
			return Vector3();
		}
		float result_x = bx;
		float result_y = by;
		if (edge == 0) {
			result_x = right + 0.01f;
		} else if (edge == 2) {
			result_x = left - 0.01f;
		} else if (edge == 1) {
			result_y = bottom + 0.01f;
		} else {
			result_y = top - 0.01f;
		}
		return Vector3(result_x * width, result_y * height, 1.0f);
	}

	Vector2 RwGameMath::sliding_velocity(const Vector2& current_velocity, const Vector2& desired_velocity, double speed, double acceleration, double delta) {
		float x = static_cast<float>(current_velocity.x);
		float y = static_cast<float>(current_velocity.y);
		const float target_x = static_cast<float>(desired_velocity.x);
		const float target_y = static_cast<float>(desired_velocity.y);
		const float offset_x = x - target_x;
		const float offset_y = y - target_y;
		const float distance_squared = offset_x * offset_x + offset_y * offset_y;
		const float current_speed = static_cast<float>(speed);
		const float step_delta = static_cast<float>(delta);
		if (distance_squared > current_speed * current_speed) {
			x = static_cast<float>(static_cast<double>(x) - static_cast<double>(x) * 0.05 * static_cast<double>(step_delta));
			y = static_cast<float>(static_cast<double>(y) - static_cast<double>(y) * 0.05 * static_cast<double>(step_delta));
		}
		const float step = (static_cast<float>(acceleration) * 1.41f) * step_delta;
		if (distance_squared < step * step) {
			return Vector2(target_x, target_y);
		}
		const Vector2 direction = path_direction(Vector2(x, y), Vector2(target_x, target_y));
		x += static_cast<float>(direction.x) * step;
		y += static_cast<float>(direction.y) * step;
		return Vector2(x, y);
	}

	double RwGameMath::distance_squared(const Vector2& first, const Vector2& second) {
		const float x = static_cast<float>(first.x) - static_cast<float>(second.x);
		const float y = static_cast<float>(first.y) - static_cast<float>(second.y);
		return x * x + y * y;
	}

	int64_t RwGameMath::rounded_distance(const Vector2& first, const Vector2& second) {
		const int32_t squared = java_int(distance_squared(first, second));
		const float root = static_cast<float>(std::sqrt(static_cast<double>(static_cast<float>(squared))));
		return java_int(std::floor(static_cast<double>(root) + 0.5));
	}

	PackedVector2Array RwGameMath::formation_offsets(int64_t count, double radius, double angle_degrees) {
		PackedVector2Array result;
		const int64_t total = count % 2 == 0 ? count : count + 1;
		const float spacing = 2.0f + static_cast<float>(radius) * 2.0f * 1.5f;
		const Vector2 direction = direction_for_angle(angle_degrees);
		const float cosine = static_cast<float>(direction.x);
		const float sine = static_cast<float>(direction.y);
		int column = 1;
		int row = 0;
		for (int64_t index = 0; index < total; index++) {
			const int grid_column = column % 2 == 0 ? 3 + column / 2 : 3 - (column + 1) / 2;
			const float lateral = static_cast<float>(grid_column - 3) * spacing;
			const float longitudinal = static_cast<float>(-row) * spacing;
			result.append(Vector2(longitudinal * cosine - lateral * sine, lateral * cosine + longitudinal * sine));
			column++;
			if (column > 6) {
				column = 0;
				row++;
			}
		}
		return result;
	}

	Vector3 RwGameMath::formation_target(const Vector2& leader_position, const Vector2& offset, const PackedVector2Array& points, int64_t original_count, int64_t age_ms) {
		const int64_t remaining = points.size();
		Vector2 selected;
		bool has_selected = false;
		if (age_ms < 3000 && original_count > 2 && original_count - remaining <= 2 && remaining > 2) {
			selected = points[2];
			has_selected = true;
		}
		if (age_ms < 1500 && !has_selected && original_count > 0 && remaining >= original_count) {
			const Vector2 direction = path_direction(leader_position, points[0]);
			float distance = 80.0f;
			if (age_ms > 300) {
				distance -= static_cast<float>(age_ms - 300) * 0.06666667f;
			}
			selected = Vector2(static_cast<float>(leader_position.x) + static_cast<float>(direction.x) * distance,
				static_cast<float>(leader_position.y) + static_cast<float>(direction.y) * distance);
			has_selected = true;
		}
		if (has_selected) {
			return Vector3(static_cast<float>(selected.x) + static_cast<float>(offset.x), static_cast<float>(selected.y) + static_cast<float>(offset.y), 1.0f);
		}
		if (original_count >= 2 && remaining >= 1) {
			const Vector2 first = points[0];
			const Vector2 second = remaining >= 2 ? points[1] : points[0];
			const float distance = static_cast<float>(rounded_distance(leader_position, first));
			float factor = 1.0f - (distance - 15.0f) * 0.05f;
			factor = std::fmax(0.0f, std::fmin(2.0f, factor));
			float x = static_cast<float>(second.x) - static_cast<float>(first.x);
			float y = static_cast<float>(second.y) - static_cast<float>(first.y);
			if (factor > 1.0f) {
				if (remaining >= 3) {
					const Vector2 third = points[2];
					x += (static_cast<float>(third.x) - static_cast<float>(second.x)) * (factor - 1.0f);
					y += (static_cast<float>(third.y) - static_cast<float>(second.y)) * (factor - 1.0f);
				}
			} else {
				x *= factor;
				y *= factor;
			}
			return Vector3((static_cast<float>(first.x) + static_cast<float>(offset.x)) + x,
				(static_cast<float>(first.y) + static_cast<float>(offset.y)) + y, 0.0f);
		}
		return Vector3(static_cast<float>(leader_position.x) + static_cast<float>(offset.x), static_cast<float>(leader_position.y) + static_cast<float>(offset.y), 0.0f);
	}

	void RwGameMath::_bind_methods() {
		ClassDB::bind_static_method("RwGameMath", D_METHOD("float32", "value"), &RwGameMath::float32);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("path_direction", "start_position", "target_position"), &RwGameMath::path_direction);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("direction_degrees", "start_position", "target_position"), &RwGameMath::direction_degrees);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("signed_angle_delta", "current_degrees", "target_degrees"), &RwGameMath::signed_angle_delta);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("direction_for_angle", "angle_degrees"), &RwGameMath::direction_for_angle);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("factory_exit_target", "factory_position", "factory_radius"), &RwGameMath::factory_exit_target);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("turn_toward", "current_degrees", "target_degrees", "velocity", "speed", "acceleration", "delta"), &RwGameMath::turn_toward);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("advance_speed", "current", "target", "acceleration", "delta"), &RwGameMath::advance_speed);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("movement_position", "position", "angle_degrees", "speed", "factor", "delta"), &RwGameMath::movement_position);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("distance_squared", "first", "second"), &RwGameMath::distance_squared);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("rounded_distance", "first", "second"), &RwGameMath::rounded_distance);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("formation_offsets", "count", "radius", "angle_degrees"), &RwGameMath::formation_offsets);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("formation_target", "leader_position", "offset", "points", "original_count", "age_ms"), &RwGameMath::formation_target);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("sliding_velocity", "current_velocity", "desired_velocity", "speed", "acceleration", "delta"), &RwGameMath::sliding_velocity);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("terrain_slide_position", "start_position", "end_position", "tile_size", "blocked_cell", "open_neighbors"), &RwGameMath::terrain_slide_position);
		ClassDB::bind_static_method("RwGameMath", D_METHOD("collision_offsets", "separation", "direction", "radius_sum", "priority", "delta", "actor_mass", "other_mass"), &RwGameMath::collision_offsets);
	}
}
