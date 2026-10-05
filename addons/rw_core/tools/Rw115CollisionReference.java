import java.io.BufferedWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Random;

/** 按 1.15 y.java 的挤压公式生成 Java float 位模式参考 */
public final class Rw115CollisionReference {
	public static void main(String[] args) throws Exception {
		Random random = new Random(115862L);
		try (BufferedWriter output = Files.newBufferedWriter(Path.of(args[0]), StandardCharsets.UTF_8)) {
			output.write("x\ty\tdir_x\tdir_y\tradius\tpriority\tdelta\tactor_mass\tother_mass\tactor_x_bits\tactor_y_bits\tother_x_bits\tother_y_bits\n");
			for (int i = 0; i < 4096; i++) {
				float radius = 1.0F + random.nextFloat() * 60.0F;
				float x = (random.nextFloat() - 0.5F) * radius;
				float y = (random.nextFloat() - 0.5F) * radius;
				double angle = StrictMath.atan2(y, x);
				float dirX = (float) StrictMath.cos(angle);
				float dirY = (float) StrictMath.sin(angle);
				int priority = i % 5;
				float delta = 0.25F + random.nextFloat() * 2.0F;
				float actorMass = 1.0F + random.nextFloat() * 5000.0F;
				float otherMass = i % 3 == 0 ? actorMass : 1.0F + random.nextFloat() * 5000.0F;
				float squared = x * x + y * y;
				float push = radius - (float) StrictMath.sqrt((double) squared) + 0.001F;
				if (priority != 0) {
					float reduced = push / (float) priority * delta;
					if (reduced > push) {
						reduced = push;
					}
					push = reduced;
				}
				push *= 0.95F;
				if (push > 1.0F) {
					push *= 0.7F;
				}
				if (push > 3.0F) {
					push = 3.0F + (push - 3.0F) * 0.7F;
				}
				if (push > 6.0F) {
					push = 6.0F + (push - 6.0F) * 0.7F;
				}
				if (push > 10.0F) {
					push = 10.0F + (push - 10.0F) * 0.7F;
				}
				float fraction = actorMass / (actorMass + otherMass);
				float otherPush = push * fraction;
				float actorPush = push * (1.0F - fraction);
				output.write(x + "\t" + y + "\t" + dirX + "\t" + dirY + "\t" + radius + "\t" + priority + "\t" + delta + "\t" + actorMass + "\t" + otherMass + "\t"
					+ Integer.toUnsignedLong(Float.floatToRawIntBits(-dirX * actorPush)) + "\t" + Integer.toUnsignedLong(Float.floatToRawIntBits(-dirY * actorPush)) + "\t"
					+ Integer.toUnsignedLong(Float.floatToRawIntBits(dirX * otherPush)) + "\t" + Integer.toUnsignedLong(Float.floatToRawIntBits(dirY * otherPush)) + "\n");
			}
		}
	}
}
