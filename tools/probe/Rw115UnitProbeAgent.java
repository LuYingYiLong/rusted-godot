import java.io.BufferedWriter;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.ProtectionDomain;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import jdk.internal.org.objectweb.asm.ClassReader;
import jdk.internal.org.objectweb.asm.ClassVisitor;
import jdk.internal.org.objectweb.asm.ClassWriter;
import jdk.internal.org.objectweb.asm.MethodVisitor;
import jdk.internal.org.objectweb.asm.Opcodes;

/** 在原版模拟帧末尾只读采样，不修改磁盘上的游戏 jar */
public final class Rw115UnitProbeAgent {
	private static BufferedWriter writer;
	private static Access access;
	private static boolean failed;
	private static int lastFrame = -1;
	private static Path tracePath;
	private static BufferedWriter stepWriter;
	private static BufferedWriter teamWriter;
	private static BufferedWriter obstacleWriter;
	private static BufferedWriter weaponWriter;
	private static BufferedWriter projectileWriter;
	private static BufferedWriter objectIdWriter;
	private static boolean weaponCatalogCaptured;
	private static boolean projectileTraceEveryFrame;
	private static final Set<Long> capturedProjectileIds = new HashSet<>();
	private static java.util.Set<Long> obstacleIds = new java.util.HashSet<>();
	private static long stepUnitId;
	private static int stepFirstFrame;
	private static int stepLastFrame;
	private static final String HEADER = "frame,id,type,x,y,rotation,speed,turn_velocity,push_x,push_y,build,hp,dead,order,path_count,path_points,pending_path,nav_requested,repath_timer,unit_index,collision_active,collision_refresh,next_refresh,moving_path,candidates,weapon_warmup,factory_clearance,terrain_blocked_time,terrain_clear_steps,waypoint_time,slide_x,slide_y,formation_leader,formation_x,formation_y,formation_angle,formation_size,formation_leader_age,formation_recovery,formation_lag,arrival_time\n";

	private Rw115UnitProbeAgent() {}

	public static void premain(String outputPath, Instrumentation instrumentation) throws Exception {
		tracePath = Path.of(outputPath);
		writer = Files.newBufferedWriter(tracePath);
		writer.write(HEADER);
		teamWriter = Files.newBufferedWriter(tracePath.resolveSibling("original-teams.csv"));
		teamWriter.write("frame,slot,credits,ai,difficulty,income_multiplier\n");
		objectIdWriter = Files.newBufferedWriter(tracePath.resolveSibling("original-object-ids.csv"));
		objectIdWriter.write("frame,id,class,thread\n");
		String weaponCatalog = System.getenv("RW115_WEAPON_CATALOG");
		if (weaponCatalog != null && !weaponCatalog.isEmpty()) {
			Path weaponPath = Path.of(weaponCatalog);
			weaponWriter = Files.newBufferedWriter(weaponPath);
			projectileWriter = Files.newBufferedWriter(weaponPath.resolveSibling("original-projectiles.jsonl"));
		}
		String projectileTrace = System.getenv("RW115_PROJECTILE_TRACE");
		if (projectileTrace != null && !projectileTrace.isEmpty()) {
			if (projectileWriter != null) {
				projectileWriter.close();
			}
			projectileWriter = Files.newBufferedWriter(Path.of(projectileTrace));
			projectileTraceEveryFrame = true;
		}
		String obstacleList = System.getenv("RW115_OBSTACLE_IDS");
		if (obstacleList != null && !obstacleList.isEmpty()) {
			for (String id : obstacleList.split(",")) {
				obstacleIds.add(Long.parseLong(id));
			}
			obstacleWriter = Files.newBufferedWriter(tracePath.resolveSibling("original-obstacles.csv"));
			obstacleWriter.write("frame,id,class,x,y,hp,dead,collidable,collision_group,radius\n");
		}
		String stepUnit = System.getenv("RW115_STEP_UNIT");
		if (stepUnit != null && !stepUnit.isEmpty()) {
			stepUnitId = Long.parseLong(stepUnit);
			stepFirstFrame = Integer.parseInt(System.getenv().getOrDefault("RW115_STEP_FIRST_FRAME", "0"));
			stepLastFrame = Integer.parseInt(System.getenv().getOrDefault("RW115_STEP_LAST_FRAME", "2147483647"));
			stepWriter = Files.newBufferedWriter(tracePath.resolveSibling("original-steps.csv"));
			stepWriter.write("frame,id,phase,x,y,rotation,speed,turn_velocity,target_x,target_y,navigation,target_available,movement_enabled,path_count,path_points,attack_target,attack_target_search_timer,attack_target_refresh_timer\n");
		}
		instrumentation.addTransformer(new ClassFileTransformer() {
			@Override
			public byte[] transform(ClassLoader loader, String name, Class<?> type, ProtectionDomain domain, byte[] bytes) {
				boolean frameClass = "com/corrodinggames/rts/game/i".equals(name);
				boolean movementClass = stepWriter != null && "com/corrodinggames/rts/game/units/y".equals(name);
				boolean pathClass = stepWriter != null && "com/corrodinggames/rts/gameFramework/k/o".equals(name);
				boolean objectClass = "com/corrodinggames/rts/gameFramework/w".equals(name);
				if (!frameClass && !movementClass && !pathClass && !objectClass) {
					return null;
				}
				ClassReader reader = new ClassReader(bytes);
				ClassWriter output = new ClassWriter(reader, ClassWriter.COMPUTE_MAXS);
				int[] hooks = {0};
				reader.accept(new ClassVisitor(Opcodes.ASM5, output) {
					@Override
					public MethodVisitor visitMethod(int flags, String method, String descriptor, String signature, String[] exceptions) {
						MethodVisitor next = super.visitMethod(flags, method, descriptor, signature, exceptions);
						boolean frameHook = frameClass && "a".equals(method) && "(F)V".equals(descriptor);
						boolean movementHook = movementClass && "a".equals(method) && "(FLcom/corrodinggames/rts/game/units/ad;Lcom/corrodinggames/rts/game/units/au;Z)V".equals(descriptor);
						boolean pathHook = pathClass && "a".equals(method) && "(Lcom/corrodinggames/rts/gameFramework/k/k;)V".equals(descriptor);
						boolean objectIdHook = objectClass && "<init>".equals(method) && "(Z)V".equals(descriptor);
						if (!frameHook && !movementHook && !pathHook && !objectIdHook) {
							return next;
						}
						if (objectIdHook) {
							hooks[0]++;
							return new MethodVisitor(Opcodes.ASM5, next) {
								@Override
								public void visitFieldInsn(int opcode, String owner, String fieldName, String fieldDescriptor) {
									super.visitFieldInsn(opcode, owner, fieldName, fieldDescriptor);
									if (opcode == Opcodes.PUTFIELD && "com/corrodinggames/rts/gameFramework/w".equals(owner)
										&& "eh".equals(fieldName) && "J".equals(fieldDescriptor)) {
										super.visitVarInsn(Opcodes.ALOAD, 0);
										super.visitFieldInsn(Opcodes.GETFIELD, owner, fieldName, fieldDescriptor);
										super.visitVarInsn(Opcodes.ALOAD, 0);
										super.visitMethodInsn(Opcodes.INVOKEVIRTUAL, "java/lang/Object", "getClass", "()Ljava/lang/Class;", false);
										super.visitMethodInsn(Opcodes.INVOKEVIRTUAL, "java/lang/Class", "getName", "()Ljava/lang/String;", false);
										super.visitMethodInsn(Opcodes.INVOKESTATIC, "Rw115UnitProbeAgent", "recordObjectId", "(JLjava/lang/String;)V", false);
									}
								}
							};
						}
						if (pathHook) {
							hooks[0]++;
							return new MethodVisitor(Opcodes.ASM5, next) {
								@Override
								public void visitCode() {
									super.visitCode();
									super.visitVarInsn(Opcodes.ALOAD, 1);
									super.visitMethodInsn(Opcodes.INVOKESTATIC, "Rw115UnitProbeAgent", "capturePath", "(Ljava/lang/Object;)V", false);
								}
							};
						}
						if (movementHook) {
							hooks[0]++;
							return new MethodVisitor(Opcodes.ASM5, next) {
								private void capture(String phase) {
									super.visitVarInsn(Opcodes.ALOAD, 0);
									super.visitVarInsn(Opcodes.ALOAD, 2);
									super.visitLdcInsn(phase);
									super.visitVarInsn(Opcodes.ILOAD, 4);
									super.visitMethodInsn(Opcodes.INVOKESTATIC, "Rw115UnitProbeAgent", "captureMovement", "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;Z)V", false);
								}

								@Override
								public void visitCode() {
									super.visitCode();
									capture("before");
								}

							};
						}
						return new MethodVisitor(Opcodes.ASM5, next) {
							@Override
							public void visitInsn(int opcode) {
								if (opcode == Opcodes.RETURN) {
									super.visitMethodInsn(Opcodes.INVOKESTATIC, "Rw115UnitProbeAgent", "captureFrame", "()V", false);
									hooks[0]++;
								}
								super.visitInsn(opcode);
							}
						};
					}
				}, 0);
				if (hooks[0] != 1) {
					throw new IllegalStateException("Unexpected stock simulation hook count: " + hooks[0]);
				}
				System.out.println("RW115 probe hooked " + (frameClass ? "main-thread simulation frame end" : pathClass ? "path solver inputs" : movementClass ? "movement decision" : "global object ID allocation"));
				return output.toByteArray();
			}
		});
	}

	/** 记录原版全局对象分配器产生的编号和对象类型 */
	public static void recordObjectId(long objectId, String className) {
		if (objectIdWriter == null || objectId == 0L) {
			return;
		}
		try {
			objectIdWriter.write(lastFrame + "," + objectId + "," + className + "," + Thread.currentThread().getName() + "\n");
		} catch (Throwable failure) {
			recordFailure(failure);
		}
	}

	/** 在求解器接收任务时复制寻路输入，不修改任务或地图代价数组 */
	public static void capturePath(Object query) {
		if (failed || stepWriter == null) {
			return;
		}
		try {
			Class<?> queryType = Class.forName("com.corrodinggames.rts.gameFramework.k.k");
			int frame = queryType.getField("g").getInt(query);
			if (frame < stepFirstFrame || frame > stepLastFrame) {
				return;
			}
			int queryId = Access.field(queryType, "e").getInt(query);
			Path directory = tracePath.resolveSibling("path-" + frame + "-" + queryId);
			Files.createDirectories(directory);
			StringBuilder description = new StringBuilder();
			for (String name : new String[] {"g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r"}) {
				description.append(name).append('=').append(Access.field(queryType, name).get(query)).append('\n');
			}
			Object engine = access.engineInstance.invoke(null);
			Object pathEngine = engine.getClass().getField("bU").get(engine);
			Class<?> movementType = Class.forName("com.corrodinggames.rts.game.units.ao");
			Object costMap = pathEngine.getClass().getMethod("a", movementType).invoke(pathEngine, Access.field(queryType, "o").get(query));
			description.append("cost_refresh_frame=").append(costMap.getClass().getField("k").getInt(costMap)).append('\n');
			Files.writeString(directory.resolve("query.txt"), description.toString());
			for (String name : new String[] {"y", "z", "A", "C"}) {
				byte[] costs = (byte[]) queryType.getField(name).get(query);
				if (costs != null) {
					Files.write(directory.resolve(name + ".bin"), costs);
				}
			}
		} catch (Throwable failure) {
			recordFailure(failure);
		}
	}

	/** 只读记录移动决策输入，结果由帧末轨迹记录 */
	public static void captureMovement(Object unit, Object navigation, String phase, boolean movementEnabled) {
		if (failed || stepWriter == null) {
			return;
		}
		try {
			if (access == null) {
				access = new Access();
			}
			int frame = access.frame.getInt(access.engineInstance.invoke(null));
			long id = access.id.getLong(unit);
			if (id != stepUnitId || frame < stepFirstFrame || frame > stepLastFrame) {
				return;
			}
			StringBuilder points = new StringBuilder();
			Object[] path = (Object[]) access.pathPoints.get(unit);
			int count = access.pathCount.getInt(unit);
			for (int index = 0; index < count; index++) {
				if (index > 0) {
					points.append('|');
				}
				points.append(access.waypointX.getFloat(path[index])).append(':').append(access.waypointY.getFloat(path[index]));
			}
			Class<?> navigationType = navigation.getClass();
			Object attackTarget = access.attackTarget.get(unit);
			stepWriter.write(frame + "," + id + "," + phase + "," + access.x.getFloat(unit) + "," + access.y.getFloat(unit) + ","
				+ access.rotation.getFloat(unit) + "," + access.speed.getFloat(unit) + "," + access.turnVelocity.getFloat(unit) + ","
				+ Access.field(navigationType, "e").getFloat(navigation) + "," + Access.field(navigationType, "f").getFloat(navigation) + ","
				+ access.navigation.getBoolean(unit) + "," + Access.field(navigationType, "b").getBoolean(navigation) + ","
				+ movementEnabled + "," + count + "," + points + "," + (attackTarget == null ? -1 : access.id.getLong(attackTarget)) + ","
				+ access.attackTargetSearchTimer.getFloat(unit) + "," + access.attackTargetRefreshTimer.getFloat(unit) + "\n");
			stepWriter.flush();
		} catch (Throwable failure) {
			recordFailure(failure);
		}
	}

	/** 在完整模拟步结束后采样，禁止通过后台轮询推断帧边界 */
	public static void captureFrame() {
		if (failed) {
			return;
		}
		try {
			if (access == null) {
				access = new Access();
			}
			Object engine = access.engineInstance.invoke(null);
			int frame = access.frame.getInt(engine);
			if (!weaponCatalogCaptured && weaponWriter != null) {
				weaponCatalogCaptured = true;
				captureNativeWeaponCatalog();
			}
			if (projectileWriter != null) {
				captureLiveProjectiles(frame);
			}
			if (frame < lastFrame) {
				writer.close();
				writer = Files.newBufferedWriter(tracePath);
				writer.write(HEADER);
				teamWriter.close();
				teamWriter = Files.newBufferedWriter(tracePath.resolveSibling("original-teams.csv"));
				teamWriter.write("frame,slot,credits,ai,difficulty,income_multiplier\n");
				if (obstacleWriter != null) {
					obstacleWriter.close();
					obstacleWriter = Files.newBufferedWriter(tracePath.resolveSibling("original-obstacles.csv"));
					obstacleWriter.write("frame,id,class,x,y,hp,dead,collidable,collision_group,radius\n");
				}
				objectIdWriter.close();
				objectIdWriter = Files.newBufferedWriter(tracePath.resolveSibling("original-object-ids.csv"));
				objectIdWriter.write("frame,id,class,thread\n");
			}
			if (frame == lastFrame || frame <= 0) {
				objectIdWriter.flush();
				return;
			}
			lastFrame = frame;
			Object units = access.units.get(null);
			Object[] snapshot = (Object[]) access.unitArray.invoke(units);
			int count = Math.min((Integer) access.unitCount.invoke(units), snapshot.length);
			StringBuilder batch = new StringBuilder();
			for (int index = 0; index < count; index++) {
				Object unit = snapshot[index];
				if (obstacleWriter != null && obstacleIds.contains(access.id.getLong(unit))) {
					Class<?> type = access.unitType;
					obstacleWriter.write(frame + "," + access.id.getLong(unit) + "," + unit.getClass().getName() + ","
						+ access.x.getFloat(unit) + "," + access.y.getFloat(unit) + "," + access.hp.getFloat(unit) + ","
						+ access.dead.getBoolean(unit) + "," + Access.field(type, "bT").getBoolean(unit) + ","
						+ Access.field(type, "bU").getInt(unit) + "," + Access.field(type, "cj").getFloat(unit) + "\n");
				}
				if (!access.mobileType.isInstance(unit)) {
					continue;
				}
				Object order = access.currentOrder.invoke(unit);
				int pathCount = access.pathCount.getInt(unit);
				Object[] points = (Object[]) access.pathPoints.get(unit);
				Object[] weapons = (Object[]) access.weapons.get(unit);
				Object leader = access.formationLeader.get(unit);
				StringBuilder path = new StringBuilder();
				StringBuilder candidates = new StringBuilder();
				Object[] neighbors = (Object[]) access.candidates.get(unit);
				if (neighbors != null) {
					for (int candidateIndex = 0; candidateIndex < access.candidateCount.getByte(unit); candidateIndex++) {
						if (candidateIndex > 0) {
							candidates.append('|');
						}
						candidates.append(access.id.getLong(neighbors[candidateIndex]));
					}
				}
				if (points != null) {
					for (int pointIndex = 0; pointIndex < Math.min(pathCount, points.length); pointIndex++) {
						Object point = points[pointIndex];
						if (point != null) {
							if (path.length() > 0) {
								path.append('|');
							}
							path.append(access.waypointX.getFloat(point)).append(':').append(access.waypointY.getFloat(point));
						}
					}
				}
				batch.append(frame).append(',').append(access.id.getLong(unit)).append(',')
					.append(access.unitName.invoke(access.unitDefinition.invoke(unit))).append(',')
					.append(access.x.getFloat(unit)).append(',').append(access.y.getFloat(unit)).append(',')
					.append(access.rotation.getFloat(unit)).append(',').append(access.speed.getFloat(unit)).append(',')
					.append(access.turnVelocity.getFloat(unit)).append(',').append(access.pushX.getFloat(unit)).append(',')
					.append(access.pushY.getFloat(unit)).append(',').append(access.build.getFloat(unit)).append(',')
					.append(access.hp.getFloat(unit)).append(',').append(access.dead.getBoolean(unit)).append(',')
					.append(order == null ? "" : access.orderKind.get(order)).append(',').append(pathCount).append(',')
					.append(path).append(',').append(access.pendingPath.get(unit) != null).append(',')
					.append(access.navigation.getBoolean(unit)).append(',').append(access.repathTimer.getFloat(unit)).append(',')
					.append(index).append(',').append(access.collisionActive.getBoolean(unit)).append(',')
					.append(access.collisionRefresh.getBoolean(unit)).append(',').append(access.nextRefresh.getInt(unit)).append(',')
					.append(access.movingPath.getBoolean(unit)).append(',').append(candidates).append(',')
					.append(weapons.length == 0 ? 0.0f : access.weaponWarmup.getFloat(weapons[0])).append(',')
					.append(access.factoryClearance.getFloat(unit)).append(',')
					.append(access.terrainBlockedTime.getFloat(unit)).append(',').append(access.terrainClearSteps.getInt(unit)).append(',')
					.append(access.waypointTime.getFloat(unit)).append(',')
					.append(access.slideX.getFloat(unit)).append(',').append(access.slideY.getFloat(unit)).append(',')
					.append(leader == null ? -1 : access.id.getLong(leader)).append(',')
					.append(access.formationX.getFloat(unit)).append(',').append(access.formationY.getFloat(unit)).append(',')
					.append(access.formationAngle.getFloat(unit)).append(',').append(access.formationSize.getShort(unit)).append(',')
					.append(leader == null ? 0 : access.simulationTime.getInt(engine) - access.formationAssignedTime.getInt(leader)).append(',')
					.append(access.formationRecovery.getFloat(unit)).append(',').append(access.formationLag.getFloat(unit)).append(',')
					.append(access.arrivalTime.getFloat(unit)).append('\n');
			}
			writer.write(batch.toString());
			writer.flush();
			if (obstacleWriter != null) {
				obstacleWriter.flush();
			}
			StringBuilder teams = new StringBuilder();
			for (int slot = 0; slot < access.teamSlots.getInt(null); slot++) {
				Object team = access.teamAt.invoke(null, slot);
				if (team != null) {
					teams.append(frame).append(',').append(slot).append(',').append(access.credits.getDouble(team)).append(',')
						.append(access.isAi.getBoolean(team)).append(',').append(access.difficulty.invoke(team)).append(',')
						.append(access.incomeMultiplier.invoke(team)).append('\n');
				}
			}
			teamWriter.write(teams.toString());
			teamWriter.flush();
			objectIdWriter.flush();
		} catch (Throwable failure) {
			recordFailure(failure);
		}
	}

	/** 从原版共享单位模板逐武器触发一次只读探针并记录真实弹体参数 */
	private static void captureNativeWeaponCatalog() {
		Object activeProjectiles = null;
		Method projectileCount = null;
		Method projectileGet = null;
		Method projectileRemove = null;
		try {
			Class<?> unitClass = Class.forName("com.corrodinggames.rts.game.units.am");
			Class<?> mobileClass = Class.forName("com.corrodinggames.rts.game.units.y");
			Class<?> projectileClass = Class.forName("com.corrodinggames.rts.game.f");
			Class<?> registryClass = Class.forName("com.corrodinggames.rts.game.units.ar");
			Object prototypesValue = unitClass.getField("bF").get(null);
			if (!(prototypesValue instanceof Map)) {
				throw new IllegalStateException("Original native unit template map is unavailable");
			}
			Map<?, ?> prototypes = (Map<?, ?>) prototypesValue;
			Field activeField = projectileClass.getField("a");
			activeProjectiles = activeField.get(null);
			projectileCount = activeProjectiles.getClass().getMethod("size");
			projectileGet = activeProjectiles.getClass().getMethod("get", int.class);
			projectileRemove = activeProjectiles.getClass().getMethod("remove", int.class);
			Method typeNameMethod = registryClass.getMethod("i");
			Method turretCountMethod = mobileClass.getMethod("bl");
			Method shootMethod = mobileClass.getMethod("a", unitClass, int.class);
			Method rangeMethod = mobileClass.getMethod("m");
			Method delayMethod = mobileClass.getMethod("b", int.class);
			Object values = registryClass.getMethod("values").invoke(null);
			for (int index = 0; index < Array.getLength(values); index++) {
				Object registry = Array.get(values, index);
				Object prototype = prototypes.get(registry);
				if (prototype == null || !mobileClass.isInstance(prototype)) {
					continue;
				}
				String unitName = String.valueOf(typeNameMethod.invoke(registry));
				int turretCount = ((Number) turretCountMethod.invoke(prototype)).intValue();
				for (int weaponIndex = 0; weaponIndex < turretCount; weaponIndex++) {
					int before = ((Number) projectileCount.invoke(activeProjectiles)).intValue();
					try {
						shootMethod.invoke(prototype, prototype, weaponIndex);
						int after = ((Number) projectileCount.invoke(activeProjectiles)).intValue();
						for (int projectileIndex = before; projectileIndex < after; projectileIndex++) {
							Object projectile = projectileGet.invoke(activeProjectiles, projectileIndex);
						weaponWriter.write("{\"unit\":\"" + jsonEscape(unitName) + "\",\"class\":\""
								+ jsonEscape(prototype.getClass().getName()) + "\",\"weapon_index\":" + weaponIndex
								+ ",\"unit_range\":" + rangeMethod.invoke(prototype)
								+ ",\"shoot_delay\":" + delayMethod.invoke(prototype, weaponIndex)
								+ ",\"projectile\":" + scalarFields(projectile)
								+ ",\"settings\":" + scalarFields(Access.field(projectile.getClass(), "g").get(projectile)) + "}\n");
						}
						weaponWriter.flush();
					} finally {
						int after = ((Number) projectileCount.invoke(activeProjectiles)).intValue();
						for (int projectileIndex = after - 1; projectileIndex >= before; projectileIndex--) {
							projectileRemove.invoke(activeProjectiles, projectileIndex);
						}
					}
				}
			}
		} catch (Throwable failure) {
			try {
				weaponWriter.write("{\"probe_error\":\"" + jsonEscape(failure.toString()) + "\"}\n");
				weaponWriter.flush();
			} catch (Throwable writeFailure) {
				failure.addSuppressed(writeFailure);
			}
			failure.printStackTrace();
		}
	}

	/** 按首次出现的对象编号记录原版实战弹体配置 */
	private static void captureLiveProjectiles(int frame) {
		try {
			Class<?> projectileClass = Class.forName("com.corrodinggames.rts.game.f");
			Class<?> unitClass = Class.forName("com.corrodinggames.rts.game.units.am");
			Object activeProjectiles = projectileClass.getField("a").get(null);
			Method count = activeProjectiles.getClass().getMethod("size");
			Method get = activeProjectiles.getClass().getMethod("get", int.class);
			Field id = unitClass.getField("eh");
			Field ownerField = projectileClass.getField("j");
			Field targetField = projectileClass.getField("l");
			Method typeMethod = unitClass.getMethod("r");
			Method nameMethod = typeMethod.getReturnType().getMethod("i");
			int projectileCount = ((Number) count.invoke(activeProjectiles)).intValue();
			for (int index = 0; index < projectileCount; index++) {
				Object projectile = get.invoke(activeProjectiles, index);
				long objectId = id.getLong(projectile);
				if (!projectileTraceEveryFrame && !capturedProjectileIds.add(objectId)) {
					continue;
				}
				capturedProjectileIds.add(objectId);
				Object owner = ownerField.get(projectile);
				Object target = targetField.get(projectile);
				String ownerName = owner == null ? "" : String.valueOf(nameMethod.invoke(typeMethod.invoke(owner)));
				String targetName = target == null ? "" : String.valueOf(nameMethod.invoke(typeMethod.invoke(target)));
				long ownerId = owner == null ? -1L : id.getLong(owner);
				long targetId = target == null ? -1L : id.getLong(target);
				projectileWriter.write("{\"frame\":" + frame + ",\"id\":" + objectId + ",\"owner_id\":" + ownerId
					+ ",\"target_id\":" + targetId + ",\"owner\":\""
					+ jsonEscape(ownerName) + "\",\"target\":\"" + jsonEscape(targetName) + "\",\"weapon_index\":"
					+ projectileClass.getField("k").getShort(projectile) + ",\"projectile\":" + scalarFields(projectile)
					+ ",\"settings\":" + scalarFields(Access.field(projectile.getClass(), "g").get(projectile)) + "}\n");
			}
			projectileWriter.flush();
		} catch (Throwable failure) {
			failure.printStackTrace();
		}
	}

	private static String scalarFields(Object value) throws Exception {
		StringBuilder result = new StringBuilder("{");
		boolean first = true;
		for (Class<?> type = value.getClass(); type != null; type = type.getSuperclass()) {
			for (Field field : type.getDeclaredFields()) {
				if (Modifier.isStatic(field.getModifiers()) || !(field.getType().isPrimitive() || field.getType() == String.class)) {
					continue;
				}
				field.setAccessible(true);
				Object fieldValue = field.get(value);
				if (!first) {
					result.append(',');
				}
				first = false;
				result.append('"').append(jsonEscape(field.getName())).append("\":");
				if (fieldValue instanceof String) {
					result.append('"').append(jsonEscape(String.valueOf(fieldValue))).append('"');
				} else {
					result.append(fieldValue);
				}
			}
		}
		return result.append('}').toString();
	}

	private static String jsonEscape(String value) {
		return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\r", "\\r").replace("\n", "\\n");
	}

	private static void recordFailure(Throwable failure) {
		failed = true;
		failure.printStackTrace();
		try {
			Files.writeString(tracePath.resolveSibling("original-probe-failure.txt"), failure.toString());
		} catch (Exception reportFailure) {
			reportFailure.printStackTrace();
		}
	}

	private static final class Access {
		final Class<?> mobileType = Class.forName("com.corrodinggames.rts.game.units.y");
		final Class<?> unitType = Class.forName("com.corrodinggames.rts.game.units.am");
		final Class<?> objectType = Class.forName("com.corrodinggames.rts.gameFramework.w");
		final Class<?> engineType = Class.forName("com.corrodinggames.rts.gameFramework.l");
		final Class<?> waypointType = Class.forName("com.corrodinggames.rts.game.units.af");
		final Class<?> teamType = Class.forName("com.corrodinggames.rts.game.n");
		final Field teamSlots = teamType.getField("f");
		final Method teamAt = teamType.getMethod("k", int.class);
		final Field credits = teamType.getField("o");
		final Field isAi = teamType.getField("w");
		final Method difficulty = teamType.getMethod("C");
		final Method incomeMultiplier = teamType.getMethod("E");
		final Method engineInstance = engineType.getMethod("B");
		final Method unitDefinition = unitType.getMethod("r");
		final Method unitName = unitDefinition.getReturnType().getMethod("i");
		final Method unitArray = unitType.getField("bE").get(null).getClass().getMethod("a");
		final Method unitCount = unitType.getField("bE").get(null).getClass().getMethod("size");
		final Method currentOrder = mobileType.getMethod("ar");
		final Field units = unitType.getField("bE");
		final Field frame = engineType.getField("bx");
		final Field arrivalTime = field(mobileType, "Y");
		final Field attackTarget = mobileType.getField("R");
		final Field attackTargetSearchTimer = field(mobileType, "S");
		final Field attackTargetRefreshTimer = field(mobileType, "T");
		final Field id = objectType.getField("eh");
		final Field x = objectType.getField("eo");
		final Field y = objectType.getField("ep");
		final Field rotation = unitType.getField("cg");
		final Field speed = unitType.getField("cf");
		final Field factoryClearance = unitType.getField("cl");
		final Field turnVelocity = unitType.getField("ce");
		final Field pushX = unitType.getField("bZ");
		final Field pushY = unitType.getField("ca");
		final Field build = unitType.getField("cm");
		final Field hp = unitType.getField("cu");
		final Field dead = unitType.getField("bV");
		final Field pathCount = field(mobileType, "aw");
		final Field pathPoints = field(mobileType, "av");
		final Field pendingPath = field(mobileType, "aU");
		final Field navigation = field(mobileType, "k");
		final Field repathTimer = field(mobileType, "s");
		final Field terrainBlockedTime = field(mobileType, "b");
		final Field terrainClearSteps = field(mobileType, "a");
		final Field waypointTime = mobileType.getField("W");
		final Field slideX = unitType.getField("cc");
		final Field slideY = unitType.getField("cd");
		final Field candidates = mobileType.getField("aJ");
		final Field candidateCount = mobileType.getField("aI");
		final Field nextRefresh = mobileType.getField("aL");
		final Field collisionActive = mobileType.getField("ay");
		final Field collisionRefresh = unitType.getField("cb");
		final Field movingPath = unitType.getField("cK");
		final Field formationLeader = mobileType.getField("ad");
		final Field formationX = mobileType.getField("ak");
		final Field formationY = mobileType.getField("al");
		final Field formationAngle = mobileType.getField("am");
		final Field formationSize = mobileType.getField("ah");
		final Field formationAssignedTime = mobileType.getField("an");
		final Field simulationTime = engineType.getField("by");
		final Field formationRecovery = field(mobileType, "c");
		final Field formationLag = field(mobileType, "d");
		final Field weapons = unitType.getField("cL");
		final Field weaponWarmup = Class.forName("com.corrodinggames.rts.game.units.ap").getField("f");
		final Field waypointX = waypointType.getField("a");
		final Field waypointY = waypointType.getField("b");
		final Field orderKind = field(Class.forName("com.corrodinggames.rts.game.units.au"), "a");

		Access() throws Exception {}

		private static Field field(Class<?> type, String name) throws Exception {
			Field result = type.getDeclaredField(name);
			result.setAccessible(true);
			return result;
		}
	}
}
