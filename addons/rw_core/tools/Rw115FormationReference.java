import android.graphics.PointF;
import com.corrodinggames.rts.gameFramework.aa;
import com.corrodinggames.rts.gameFramework.f;
import java.io.BufferedWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Random;

/** 使用原版 aa 槽位函数、f 距离函数和 y 的路径前瞻分支生成参考 */
public final class Rw115FormationReference {
	public static void main(String[] args) throws Exception {
		Random random = new Random(1154061L);
		aa formation = new aa();
		try (BufferedWriter output = Files.newBufferedWriter(Path.of(args[0]), StandardCharsets.UTF_8)) {
			output.write("kind\tinputs\tresult\n");
			for (int index = 0; index < 1024; index++) {
				int count = random.nextInt(65);
				float radius = random.nextFloat() * 80.0F;
				float angle = (random.nextFloat() * 2.0F - 1.0F) * 720.0F;
				StringBuilder result = new StringBuilder();
				for (Object item : formation.a(count, radius, angle)) {
					PointF point = (PointF)item;
					if (result.length() != 0) {
						result.append('|');
					}
					result.append(bits(point.a)).append(',').append(bits(point.b));
				}
				output.write("offsets\t" + count + "," + radius + "," + angle + "\t" + result + "\n");
			}
			for (int index = 0; index < 8192; index++) {
				float x = random.nextFloat() * 4000.0F;
				float y = random.nextFloat() * 4000.0F;
				float tx = x + (random.nextFloat() * 2.0F - 1.0F) * 1000.0F;
				float ty = y + (random.nextFloat() * 2.0F - 1.0F) * 1000.0F;
				output.write("distance\t" + x + "," + y + "," + tx + "," + ty + "\t" + bits(f.a(x, y, tx, ty)) + "," + f.c(x, y, tx, ty) + "\n");
				int original = random.nextInt(12);
				int remaining = original == 0 ? 0 : random.nextInt(original + 1);
				int[] boundaries = {0, 300, 301, 1499, 1500, 2999, 3000, 5000};
				int age = boundaries[index % boundaries.length];
				float ox = (random.nextFloat() * 2.0F - 1.0F) * 100.0F;
				float oy = (random.nextFloat() * 2.0F - 1.0F) * 100.0F;
				PointF[] points = new PointF[remaining];
				StringBuilder inputs = new StringBuilder(x + "," + y + "," + ox + "," + oy + "," + original + "," + age);
				for (int p = 0; p < remaining; p++) {
					points[p] = new PointF(x - p * 20.0F - random.nextFloat() * 30.0F, y + random.nextFloat() * 30.0F);
					inputs.append(',').append(points[p].a).append(',').append(points[p].b);
				}
				float[] result = target(x, y, ox, oy, points, original, age);
				output.write("target\t" + inputs + "\t" + bits(result[0]) + "," + bits(result[1]) + "," + bits(result[2]) + "\n");
			}
		}
	}

	private static String bits(float value) {
		return Integer.toUnsignedString(Float.floatToRawIntBits(value));
	}

	private static float[] target(float x, float y, float ox, float oy, PointF[] points, int original, int age) {
		int remaining = points.length;
		PointF selected = null;
		if (age < 3000 && original > 2 && original - remaining <= 2 && remaining > 2) {
			selected = points[2];
		}
		if (age < 1500 && selected == null && original > 0 && remaining >= original) {
			float angle = f.d(x, y, points[0].a, points[0].b);
			float distance = 80.0F;
			if (age > 300) {
				distance -= (float)(age - 300) * 0.06666667F;
			}
			selected = new PointF(x + f.k(angle) * distance, y + f.j(angle) * distance);
		}
		if (selected != null) {
			return new float[]{selected.a + ox, selected.b + oy, 1.0F};
		}
		if (original >= 2 && remaining >= 1) {
			PointF first = points[0];
			PointF second = points[remaining >= 2 ? 1 : 0];
			float distance = (float)f.c(x, y, first.a, first.b);
			float factor = 1.0F - (distance - 15.0F) * 0.05F;
			if (factor > 2.0F) {
				factor = 2.0F;
			}
			if (factor < 0.0F) {
				factor = 0.0F;
			}
			float dx = second.a - first.a;
			float dy = second.b - first.b;
			if (factor > 1.0F) {
				if (remaining >= 3) {
					dx += (points[2].a - second.a) * (factor - 1.0F);
					dy += (points[2].b - second.b) * (factor - 1.0F);
				}
			} else {
				dx *= factor;
				dy *= factor;
			}
			return new float[]{first.a + ox + dx, first.b + oy + dy, 0.0F};
		}
		return new float[]{x + ox, y + oy, 0.0F};
	}
}
