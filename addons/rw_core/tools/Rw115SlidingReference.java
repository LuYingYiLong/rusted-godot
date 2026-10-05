import com.corrodinggames.rts.gameFramework.f;
import java.io.BufferedWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Random;

/** 使用原版方向查表和 y.java 滑行公式生成 Java float 参考 */
public final class Rw115SlidingReference {
	public static void main(String[] args) throws Exception {
		Random random = new Random(1153235L);
		try (BufferedWriter output = Files.newBufferedWriter(Path.of(args[0]), StandardCharsets.UTF_8)) {
			output.write("vx\tvy\ttx\tty\tspeed\tacceleration\tdelta\tresult_x_bits\tresult_y_bits\n");
			for (int index = 0; index < 8192; index++) {
				float speed = 0.25F + random.nextFloat() * 10.0F;
				float vx = (random.nextFloat() * 2.0F - 1.0F) * speed * 2.0F;
				float vy = (random.nextFloat() * 2.0F - 1.0F) * speed * 2.0F;
				float tx = index % 3 == 0 ? 0.0F : (random.nextFloat() * 2.0F - 1.0F) * speed;
				float ty = index % 3 == 0 ? 0.0F : (random.nextFloat() * 2.0F - 1.0F) * speed;
				float acceleration = index % 5 == 0 ? 0.06F : random.nextFloat() * 0.5F;
				float delta = index % 4 == 0 ? 0.5F : index % 4 == 1 ? 2.0F : 1.0F;
				if (index % 11 == 0) {
					vx = tx;
					vy = ty;
				}
				if (index % 17 == 0) {
					vx = -0.00095876196F;
					vy = 0.49999908F;
					tx = 0.0F;
					ty = 0.0F;
					speed = 1.0F;
					acceleration = 0.06F;
					delta = 1.0F;
				}
				float x = vx;
				float y = vy;
				float distance = f.a(vx, vy, tx, ty);
				if (distance > speed * speed) {
					x = (float)((double)x - (double)x * 0.05D * (double)delta);
					y = (float)((double)y - (double)y * 0.05D * (double)delta);
				}
				float step = (acceleration * 1.41F) * delta;
				if (distance < step * step) {
					x = tx;
					y = ty;
				} else {
					float angle = f.d(x, y, tx, ty);
					x += f.k(angle) * step;
					y += f.j(angle) * step;
				}
				output.write(vx + "\t" + vy + "\t" + tx + "\t" + ty + "\t" + speed + "\t" + acceleration + "\t" + delta
					+ "\t" + Integer.toUnsignedString(Float.floatToRawIntBits(x))
					+ "\t" + Integer.toUnsignedString(Float.floatToRawIntBits(y)) + "\n");
			}
		}
	}
}
