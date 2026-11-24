import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Path;
import java.util.Map;
import java.util.Set;

public final class IsolatedLoaderCheck {
    public static void main(String[] arguments) throws Exception {
        boolean expected = Boolean.parseBoolean(arguments[1]);
        for (int index = 0; index < 2; index++) {
            try (URLClassLoader loader = new URLClassLoader(new URL[]{Path.of(arguments[0]).toUri().toURL()}, null)) {
                Class<?> hostClass = Class.forName("org.jetbrains.kotlin.konan.target.HostManager", true, loader);
                Object manager = hostClass.getConstructor().newInstance();
                Object ios = Class.forName("org.jetbrains.kotlin.konan.target.KonanTarget$IOS_ARM64", true, loader).getField("INSTANCE").get(null);
                boolean enabled = (boolean) hostClass.getMethod("isEnabled", Class.forName("org.jetbrains.kotlin.konan.target.KonanTarget", true, loader)).invoke(manager, ios);
                if (enabled != expected) throw new AssertionError("IOS_ARM64 enabled=" + enabled + "; expected=" + expected);
                Object host = hostClass.getMethod("getHost").invoke(null);
                if (!host.toString().equals("linux_x64")) throw new AssertionError("Host spoofed");
                Map<?, ?> map = (Map<?, ?>) hostClass.getMethod("getEnabledByHost").invoke(manager);
                Set<?> enabledTargets = (Set<?>) map.get(host);
                long appleTargets = enabledTargets.stream().filter(target -> {
                    String name = target.toString();
                    return name.startsWith("ios_") || name.startsWith("macos_") || name.startsWith("watchos_") || name.startsWith("tvos_");
                }).count();
                if (appleTargets != (expected ? 1 : 0)) throw new AssertionError("Unexpected Apple target additions: " + enabledTargets);
                if (expected) {
                    Class<?> xcode = Class.forName("org.jetbrains.kotlin.konan.target.Xcode", true, loader);
                    Object companion = xcode.getField("Companion").get(null);
                    if (companion.getClass().getMethod("getXcodeOverride").invoke(companion) == null) throw new AssertionError("Per-loader Xcode override missing");
                    if (Class.forName("ProbeBridge", false, loader).getClassLoader() != null) throw new AssertionError("Bridge not shared through bootstrap");
                }
                System.out.println("PASS: isolated loader " + index + "; host=" + host + "; iosEnabled=" + enabled + "; Apple targets=" + appleTargets);
            }
        }
    }
}
