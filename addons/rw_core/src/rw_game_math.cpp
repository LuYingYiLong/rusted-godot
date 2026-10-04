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
	}
}
