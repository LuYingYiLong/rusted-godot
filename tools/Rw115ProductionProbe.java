import java.lang.reflect.Method;

/** 只读提取原版 1.15 单位枚举、生产动作 ID 和生产数据 */
public final class Rw115ProductionProbe {
	private Rw115ProductionProbe() {}

	/** 输出原版单位、动作 ID 和单精度生产完成帧数 */
	public static void main(String[] args) throws Exception {
		Class<?> unitTypeClass = Class.forName("com.corrodinggames.rts.game.units.ar");
		Method getProductionName = unitTypeClass.getMethod("v");
		Method getCost = unitTypeClass.getMethod("c");
		Method getProductionRate = unitTypeClass.getMethod("D");

		for (Object unitType : unitTypeClass.getEnumConstants()) {
			Enum<?> unitEnum = (Enum<?>) unitType;
			float rate = ((Number) getProductionRate.invoke(unitType)).floatValue();
			System.out.printf(
				"UNIT\t%d\t%s\t%s\t%s\t%s%n",
				unitEnum.ordinal(),
				unitEnum.name(),
				unitType.getClass().getName(),
				getCost.invoke(unitType),
				rate
			);
			String productionName = (String) getProductionName.invoke(unitType);
			System.out.printf(
				"ACTION\t%s\t%s%n",
				unitEnum.name(),
				"u_" + productionName
			);
			float progress = 0.0f;
			int completionFrames = 0;
			while (progress < 1.0f && completionFrames < 100000) {
				progress += rate * 1.0f * 1.0f;
				completionFrames++;
			}
			System.out.printf("FRAMES\t%s\t%d%n", unitEnum.name(), completionFrames);
		}
	}
}
