public final class Rw115NativeEnumProbe {
    public static void main(String[] args) throws Exception {
        Class<?> type = Class.forName("com.corrodinggames.rts.game.units.ar");
        for (Object value : type.getEnumConstants()) {
            Enum<?> item = (Enum<?>) value;
            System.out.println(item.ordinal() + ":" + item.name());
        }
    }
}
