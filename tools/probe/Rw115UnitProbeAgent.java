import java.io.BufferedWriter;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;

/** Samples stock 1.15 unit positions without changing game-lib.jar. */
public final class Rw115UnitProbeAgent {
    private Rw115UnitProbeAgent() {}

    public static void premain(String outputPath, Instrumentation instrumentation) {
        Thread sampler = new Thread(() -> sample(outputPath), "rw115-unit-probe");
        sampler.setDaemon(true);
        sampler.start();
    }

    private static void sample(String outputPath) {
        try (BufferedWriter writer = Files.newBufferedWriter(Path.of(outputPath))) {
            Class<?> engineType = Class.forName("com.corrodinggames.rts.gameFramework.l");
            Class<?> unitType = Class.forName("com.corrodinggames.rts.game.units.am");
            Class<?> objectType = Class.forName("com.corrodinggames.rts.gameFramework.w");
            Class<?> mobileType = Class.forName("com.corrodinggames.rts.game.units.y");
            Class<?> waypointType = Class.forName("com.corrodinggames.rts.game.units.af");
            Class<?> orderType = Class.forName("com.corrodinggames.rts.game.units.au");
            Object units = unitType.getField("bE").get(null);
            Method engineInstance = engineType.getMethod("B");
            Method unitArray = units.getClass().getMethod("a");
            Method unitCount = units.getClass().getMethod("size");
            Field frameField = engineType.getField("bx");
            Field idField = objectType.getField("eh");
            Field xField = objectType.getField("eo");
            Field yField = objectType.getField("ep");
            Field rotationField = unitType.getField("cg");
            Field speedField = unitType.getField("cf");
            Field pushXField = unitType.getField("bZ");
            Field pushYField = unitType.getField("ca");
            Field buildProgressField = unitType.getField("cm");
            Field pathCountField = mobileType.getDeclaredField("aw");
            pathCountField.setAccessible(true);
            Field pathPointsField = mobileType.getDeclaredField("av");
            pathPointsField.setAccessible(true);
            Method firstWaypoint = mobileType.getMethod("aE");
            Field waypointX = waypointType.getField("a");
            Field waypointY = waypointType.getField("b");
            Method currentOrder = mobileType.getMethod("ar");
            Field orderKindField = orderType.getDeclaredField("a");
            orderKindField.setAccessible(true);
            int lastFrame = -1;
            while (lastFrame < 1800) {
                Object engine = engineInstance.invoke(null);
                if (engine == null) {
                    Thread.sleep(1);
                    continue;
                }
                int frame = frameField.getInt(engine);
                if (frame == lastFrame || frame <= 0) {
                    Thread.sleep(1);
                    continue;
                }
                lastFrame = frame;
                Object[] snapshot = (Object[]) unitArray.invoke(units);
                int count = Math.min((Integer) unitCount.invoke(units), snapshot.length);
                for (int index = 0; index < count; index++) {
                    Object unit = snapshot[index];
                    if (unit == null) {
                        continue;
                    }
                    long id = idField.getLong(unit);
                    if (id < 287) {
                        continue;
                    }
                    int pathCount = 0;
                    String first = ",,";
                    String orderKind = "";
                    String pathPoints = "";
                    if (mobileType.isInstance(unit)) {
                        pathCount = pathCountField.getInt(unit);
                        Object waypoint = firstWaypoint.invoke(unit);
                        if (waypoint != null) {
                            first = "," + waypointX.getFloat(waypoint) + "," + waypointY.getFloat(waypoint);
                        }
                        Object order = currentOrder.invoke(unit);
                        if (order != null) {
                            orderKind = String.valueOf(orderKindField.get(order));
                        }
                        Object[] points = (Object[]) pathPointsField.get(unit);
                        if (points != null) {
                            StringBuilder path = new StringBuilder();
                            for (int pointIndex = 0; pointIndex < Math.min(pathCount, points.length); pointIndex++) {
                                Object point = points[pointIndex];
                                if (point != null) {
                                    if (path.length() > 0) {
                                        path.append('|');
                                    }
                                    path.append(waypointX.getFloat(point)).append(':').append(waypointY.getFloat(point));
                                }
                            }
                            pathPoints = path.toString();
                        }
                    }
                    writer.write(frame + "," + id + "," + xField.getFloat(unit) + "," + yField.getFloat(unit) + "," + rotationField.getFloat(unit) + "," + speedField.getFloat(unit) + "," + pathCount + first + "," + pushXField.getFloat(unit) + "," + pushYField.getFloat(unit) + "," + buildProgressField.getFloat(unit) + "," + orderKind + "," + pathPoints + "\n");
                }
                writer.flush();
                Thread.sleep(1);
            }
        } catch (Throwable failure) {
            failure.printStackTrace();
        }
    }
}
