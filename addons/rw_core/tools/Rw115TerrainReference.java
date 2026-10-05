import android.graphics.PointF;
import com.corrodinggames.rts.gameFramework.f;
import java.io.BufferedWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Random;

/** 使用原版线段相交函数及 aq.java 边缘规则生成 Java float 参考 */
public final class Rw115TerrainReference {
	private static float[] resolve(float sx, float sy, float ex, float ey, float width, float height, int x, int y, int neighbors) {
		PointF start = new PointF(sx * (1.0F / width), sy * (1.0F / height));
		PointF end = new PointF(ex * (1.0F / width), ey * (1.0F / height));
		PointF topLeft = new PointF(x, y);
		PointF topRight = new PointF(x + 1, y);
		PointF bottomLeft = new PointF(x, y + 1);
		PointF bottomRight = new PointF(x + 1, y + 1);
		int edge = -1;
		if (start.b < end.b) {
			if ((neighbors & 1) != 0 && f.a(start, end, topLeft, topRight)) {
				edge = 3;
			}
		} else if ((neighbors & 2) != 0 && f.a(start, end, bottomLeft, bottomRight)) {
			edge = 1;
		}
		if (start.a < end.a) {
			if ((neighbors & 4) != 0 && f.a(start, end, topLeft, bottomLeft)) {
				edge = 2;
			}
		} else if ((neighbors & 8) != 0 && f.a(start, end, topRight, bottomRight)) {
			edge = 0;
		}
		if (edge < 0) {
			return new float[]{0.0F, 0.0F, 0.0F};
		}
		if (edge == 0) {
			end.a = (float)(x + 1) + 0.01F;
		} else if (edge == 2) {
			end.a = (float)x - 0.01F;
		} else if (edge == 1) {
			end.b = (float)(y + 1) + 0.01F;
		} else {
			end.b = (float)y - 0.01F;
		}
		return new float[]{end.a * width, end.b * height, 1.0F};
	}

	public static void main(String[] args) throws Exception {
		Random random = new Random(1152017L);
		try (BufferedWriter output = Files.newBufferedWriter(Path.of(args[0]), StandardCharsets.UTF_8)) {
			output.write("sx\tsy\tex\tey\twidth\theight\tx\ty\tneighbors\tresult_x_bits\tresult_y_bits\tvalid_bits\n");
			for (int index = 0; index < 8192; index++) {
				float width = index % 3 == 0 ? 20.0F : 16.0F + random.nextInt(32);
				float height = index % 3 == 0 ? 20.0F : 16.0F + random.nextInt(32);
				int x = random.nextInt(256);
				int y = random.nextInt(256);
				float sx = (x - 1.0F + random.nextFloat() * 3.0F) * width;
				float sy = (y - 1.0F + random.nextFloat() * 3.0F) * height;
				float ex = (x + random.nextFloat()) * width;
				float ey = (y + random.nextFloat()) * height;
				// 整点端点和共线方向覆盖边缘相交的特殊分支
				if (index % 7 == 0) {
					sx = x * width;
					ex = sx;
				}
				if (index % 11 == 0) {
					sy = y * height;
					ey = sy;
				}
				int neighbors = index % 16;
				float[] result = resolve(sx, sy, ex, ey, width, height, x, y, neighbors);
				output.write(sx + "\t" + sy + "\t" + ex + "\t" + ey + "\t" + width + "\t" + height + "\t" + x + "\t" + y + "\t" + neighbors);
				for (float value : result) {
					output.write("\t" + Integer.toUnsignedLong(Float.floatToRawIntBits(value)));
				}
				output.write("\n");
			}
		}
	}
}
