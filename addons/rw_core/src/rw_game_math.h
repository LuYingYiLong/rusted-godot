#ifndef RW_GAME_MATH_H
#define RW_GAME_MATH_H

// 复现原版 1.15 的 Java 单精度运算与 StrictMath 查表结果

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

namespace godot {
	class RwGameMath : public RefCounted {
		GDCLASS(RwGameMath, RefCounted)

	protected:
		static void _bind_methods();

	public:
		// 将输入舍入为 Java float 并无损返回给 GDScript
		static double float32(double value);
		// 返回原版直线路径使用的量化方向
		static Vector2 path_direction(const Vector2& start_position, const Vector2& target_position);
		// 返回原版按反正切查表计算的目标方向角
		static double direction_degrees(const Vector2& start_position, const Vector2& target_position);
		// 返回有符号最短转角并保持原版单精度取余与相减顺序
		static double signed_angle_delta(double current_degrees, double target_degrees);
		// 返回原版三角函数查表中的移动方向
		static Vector2 direction_for_angle(double angle_degrees);
		// 返回原版工厂没有集结点时的离厂目标
		static Vector2 factory_exit_target(const Vector2& factory_position, double factory_radius);
		// 执行原版单帧转向，返回车体角度、转向速度与本帧转角
		static Vector3 turn_toward(double current_degrees, double target_degrees, double velocity, double speed, double acceleration, double delta);
		// 按原版分支与舍入顺序更新移动速度系数
		static double advance_speed(double current, double target, double acceleration, double delta);
		// 按原版乘法与加法顺序计算单帧位移
		static Vector2 movement_position(const Vector2& position, double angle_degrees, double speed, double factor, double delta);
		// 返回原版单精度平方距离与整数舍入距离
		static double distance_squared(const Vector2& first, const Vector2& second);
		static int64_t rounded_distance(const Vector2& first, const Vector2& second);
		// 按原版六列排列生成编队槽位
		static PackedVector2Array formation_offsets(int64_t count, double radius, double angle_degrees);
		// 返回领队路径前瞻目标，第三项表示需要按距离降低跟随速度
		static Vector3 formation_target(const Vector2& leader_position, const Vector2& offset, const PackedVector2Array& points, int64_t original_count, int64_t age_ms);
		// 按原版滑行加减速更新二维速度，保留 float 乘法与 double 衰减分支
		static Vector2 sliding_velocity(const Vector2& current_velocity, const Vector2& desired_velocity, double speed, double acceleration, double delta);
		// 按原版格子边缘相交顺序修正移动，第三项表示是否找到可滑动边缘
		static Vector3 terrain_slide_position(const Vector2& start_position, const Vector2& end_position, const Vector2& tile_size, const Vector2& blocked_cell, int64_t open_neighbors);
		// 按原版单精度顺序计算挤压，前两项为主体推力，后两项为另一单位推力
		static Vector4 collision_offsets(const Vector2& separation, const Vector2& direction, double radius_sum, int64_t priority, double delta, double actor_mass, double other_mass);
	};
}

#endif // !RW_GAME_MATH_H
