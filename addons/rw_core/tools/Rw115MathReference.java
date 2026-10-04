import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.Random;

// 使用原版 1.15 的 StrictMath 公式生成浮点位表与独立验证样本
@SuppressWarnings("strictfp")
public strictfp class Rw115MathReference {
	private static final float[][] ANGLES = new float[8][1025];
	private static final float[] SIN = new float[8192];
	private static final float[] COS = new float[8192];

	public static void main(String[] args) throws IOException {
		if (args.length != 2) {
			throw new IllegalArgumentException("Expected C++ table path and reference TSV path");
		}
		for (int i = 0; i <= 1024; i++) {
			float ratio = (float) i / 1024.0F;
			float angle = (float) (StrictMath.atan((double) ratio) * 3.1415927410125732D / 3.141592653589793D);
			ANGLES[0][i] = angle;
			ANGLES[1][i] = 1.5707964F - angle;
			ANGLES[2][i] = -angle;
			ANGLES[3][i] = angle - 1.5707964F;
			ANGLES[4][i] = 3.1415927F - angle;
			ANGLES[5][i] = angle + 1.5707964F;
			ANGLES[6][i] = angle - 3.1415927F;
			ANGLES[7][i] = -1.5707964F - angle;
		}
		for (int i = 0; i < 8192; i++) {
			float radians = ((float) i + 0.5F) / 8192.0F * 6.2831855F;
			SIN[i] = (float) StrictMath.sin((double) radians);
			COS[i] = (float) StrictMath.cos((double) radians);
		}
		try (BufferedWriter output = Files.newBufferedWriter(Path.of(args[0]), StandardCharsets.UTF_8)) {
			output.write("// 由 Rw115MathReference.java 按原版 1.15 公式生成，保存 IEEE 754 位模式\n");
			for (int i = 0; i < 8; i++) {
				writeTable(output, "ANGLE_BITS_" + i, ANGLES[i]);
			}
			writeTable(output, "SIN_BITS", SIN);
			writeTable(output, "COS_BITS", COS);
		}
		try (BufferedWriter output = Files.newBufferedWriter(Path.of(args[1]), StandardCharsets.UTF_8)) {
			output.write("operation\ta\tb\tc\td\tx_bits\ty_bits\te\tf\tz_bits\n");
			for (int i = 0; i < 8192; i++) {
				float angle = ((float) i + 0.25F) / 22.755556F;
				writeDirection(output, angle);
				writeDirection(output, -angle);
			}
			for (int i = 0; i <= 1024; i++) {
				float[][] pairs = {
					{1024.0F, i}, {i, 1024.0F}, {1024.0F, -i}, {i, -1024.0F},
					{-1024.0F, i}, {-i, 1024.0F}, {-1024.0F, -i}, {-i, -1024.0F},
				};
				for (float[] pair : pairs) {
					writeCase(output, "angle", 0.0F, 0.0F, pair[0], pair[1], fastAngle(pair[1], pair[0]) * 57.29578F, 0.0F);
				}
			}
			writeCase(output, "angle", 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F);
			Random random = new Random(115L);
			for (int i = 0; i < 2048; i++) {
				float a = random.nextFloat() * 20000.0F - 10000.0F;
				float b = random.nextFloat() * 20000.0F - 10000.0F;
				float c = random.nextFloat() * 20000.0F - 10000.0F;
				float d = random.nextFloat() * 20000.0F - 10000.0F;
				writeCase(output, "angle", a, b, c, d, fastAngle(d - b, c - a) * 57.29578F, 0.0F);
				float delta = b % 360.0F - a % 360.0F;
				if (delta > 180.0F) {
					delta -= 360.0F;
				}
				if (delta < -180.0F) {
					delta += 360.0F;
				}
				writeCase(output, "delta", a, b, 0.0F, 0.0F, delta, 0.0F);
				float radius = random.nextFloat() * 80.0F;
				int index = (int) (90.0F * 22.755556F) & 8191;
				float distance = radius * 3.0F;
				writeCase(output, "factory", a, b, radius, 0.0F, a + COS[index] * distance - SIN[index], b + SIN[index] * distance + COS[index]);
			}
			// GDScript 标量是 double，原生入口需先转换到原版 Java 的 float 参数
			for (int i = 0; i < 2048; i++) {
				double a = random.nextDouble() * 720.0D - 360.0D;
				double b = random.nextDouble() * 720.0D - 360.0D;
				float delta = (float) b % 360.0F - (float) a % 360.0F;
				if (delta > 180.0F) {
					delta -= 360.0F;
				}
				if (delta < -180.0F) {
					delta += 360.0F;
				}
				output.write("double_delta\t" + Double.toString(a) + "\t" + Double.toString(b) + "\t0.0\t0.0\t"
					+ Integer.toUnsignedString(Float.floatToRawIntBits(delta)) + "\t0\t0.0\t0.0\t0\n");
			}
			writeMotionCases(output, random);
		}
		System.out.println("RW115_MATH_REFERENCE_GENERATED tables=24584");
	}

	private static float fastAngle(float y, float x) {
		if (x >= 0.0F) {
			if (y >= 0.0F) {
				return x >= y ? lookup(0, y, x) : lookup(1, x, y);
			}
			return x >= -y ? lookup(2, -y, x) : lookup(3, x, -y);
		}
		if (y >= 0.0F) {
			return -x >= y ? lookup(4, y, -x) : lookup(5, -x, y);
		}
		return x <= y ? lookup(6, -y, -x) : lookup(7, -x, -y);
	}

	private static float lookup(int table, float numerator, float denominator) {
		int index = (int) ((double) (1024.0F * numerator / denominator) + 0.5D);
		return ANGLES[table][index];
	}

	private static void writeDirection(BufferedWriter output, float angle) throws IOException {
		int index = (int) (angle * 22.755556F) & 8191;
		writeCase(output, "direction", angle, 0.0F, 0.0F, 0.0F, COS[index], SIN[index]);
	}

	private static void writeCase(BufferedWriter output, String operation, float a, float b, float c, float d, float x, float y) throws IOException {
		output.write(operation + "\t" + Double.toString((double) a) + "\t" + Double.toString((double) b) + "\t" + Double.toString((double) c) + "\t" + Double.toString((double) d)
			+ "\t" + Integer.toUnsignedString(Float.floatToRawIntBits(x)) + "\t" + Integer.toUnsignedString(Float.floatToRawIntBits(y)) + "\t0.0\t0.0\t0\n");
	}

	// 直接照原版 f.a 与 y.a/y.i 的公式验证转向、加减速与位移
	private static void writeMotionCases(BufferedWriter output, Random random) throws IOException {
		for (int i = 0; i < 2048; i++) {
			float current = random.nextFloat() * 360.0F - 180.0F;
			float target = random.nextFloat() * 360.0F - 180.0F;
			float velocity = random.nextFloat() * 4.0F - 2.0F;
			float speed = random.nextFloat() * 3.0F;
			float acceleration = i % 4 == 0 ? 0.0F : random.nextFloat() * 0.3F;
			float delta = i % 3 == 0 ? 2.0F : 1.0F;
			float difference = target % 360.0F - current % 360.0F;
			if (difference > 180.0F) {
				difference -= 360.0F;
			}
			if (difference < -180.0F) {
				difference += 360.0F;
			}
			float nextVelocity = velocity;
			float step = 0.0F;
			float rotation = current;
			if (StrictMath.abs(difference) >= 0.01F) {
				float sign = difference > 0.0F ? 1.0F : -1.0F;
				if (acceleration > 0.0F) {
					float braking = StrictMath.abs(velocity) / acceleration;
					nextVelocity = approach(velocity, sign * (StrictMath.abs(difference) < braking ? acceleration : speed), acceleration * delta);
					step = nextVelocity * delta;
				} else {
					step = sign * speed * delta;
				}
				if (StrictMath.abs(step) > StrictMath.abs(difference)) {
					nextVelocity = 0.0F;
					step = difference;
				}
				rotation += step;
				if (rotation > 180.0F) {
					rotation -= 360.0F;
				}
				if (rotation < -180.0F) {
					rotation += 360.0F;
				}
			}
			writeDetailedCase(output, "turn", current, target, velocity, speed, acceleration, delta, rotation, nextVelocity, step);
			float factor = random.nextFloat();
			float requestedFactor = i % 2 == 0 ? 0.0F : 1.0F;
			writeCase(output, "speed", factor, requestedFactor, acceleration, delta, approach(factor, requestedFactor, acceleration * delta), 0.0F);
			float x = random.nextFloat() * 3000.0F;
			float y = random.nextFloat() * 3000.0F;
			int index = (int) (rotation * 22.755556F) & 8191;
			float distance = speed * factor * delta;
			writeDetailedCase(output, "movement", x, y, rotation, speed, factor, delta, x + COS[index] * distance, y + SIN[index] * distance, 0.0F);
		}
	}

	private static float approach(float current, float target, float step) {
		return current > target + step ? current - step : (current < target - step ? current + step : target);
	}

	private static void writeDetailedCase(BufferedWriter output, String operation, float a, float b, float c, float d, float e, float f, float x, float y, float z) throws IOException {
		output.write(operation + "\t" + Double.toString((double) a) + "\t" + Double.toString((double) b) + "\t" + Double.toString((double) c) + "\t" + Double.toString((double) d)
			+ "\t" + Integer.toUnsignedString(Float.floatToRawIntBits(x)) + "\t" + Integer.toUnsignedString(Float.floatToRawIntBits(y))
			+ "\t" + Double.toString((double) e) + "\t" + Double.toString((double) f) + "\t" + Integer.toUnsignedString(Float.floatToRawIntBits(z)) + "\n");
	}

	private static void writeTable(BufferedWriter output, String name, float[] values) throws IOException {
		output.write("constexpr uint32_t " + name + "[] = {\n");
		for (int i = 0; i < values.length; i++) {
			if (i % 8 == 0) {
				output.write("\t");
			}
			output.write(String.format(Locale.ROOT, "0x%08xu,", Float.floatToRawIntBits(values[i])));
			output.write(i % 8 == 7 || i == values.length - 1 ? "\n" : " ");
		}
		output.write("};\n\n");
	}
}
