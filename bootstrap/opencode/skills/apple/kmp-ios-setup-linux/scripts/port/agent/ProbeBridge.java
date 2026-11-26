import java.lang.reflect.Proxy;
import java.net.URL;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;

/** Bootstrap-only bridge. It has no Kotlin or ASM linkage. */
public final class ProbeBridge {
    private static final Map<ClassLoader, Boolean> configured = Collections.synchronizedMap(new WeakHashMap<>());

    @SuppressWarnings({"rawtypes", "unchecked"})
    public static void enable(Object manager) {
        try {
            if (!"Linux".equals(System.getProperty("os.name"))) throw new IllegalStateException("Actual host must remain Linux");
            ClassLoader loader = manager.getClass().getClassLoader();
            Class<?> hostClass = Class.forName("org.jetbrains.kotlin.konan.target.HostManager", false, loader);
            Object host = hostClass.getMethod("getHost").invoke(null);
            if (!host.toString().equals("linux_x64")) throw new IllegalStateException("Unexpected actual host " + host);
            Object ios = Class.forName("org.jetbrains.kotlin.konan.target.KonanTarget$IOS_ARM64", true, loader).getField("INSTANCE").get(null);
            Map map = (Map) hostClass.getMethod("getEnabledByHost").invoke(manager);
            Set previous = (Set) map.get(host);
            Set enabled = new LinkedHashSet(previous);
            enabled.add(ios);
            Set added = new LinkedHashSet(enabled);
            added.removeAll(previous);
            if (!added.isEmpty() && !(added.size() == 1 && added.contains(ios))) throw new IllegalStateException("Unexpected additional targets");
            map.put(host, enabled);
            synchronized (configured) {
                if (!configured.containsKey(loader)) {
                    configureXcode(loader);
                    configured.put(loader, Boolean.TRUE);
                    URL source = hostClass.getProtectionDomain().getCodeSource().getLocation();
                    System.err.println("PROBE3: enabled IOS_ARM64 only; actual host=" + host + "; loader=" + loader + "; codeSource=" + source + "; helperLoader=" + ProbeBridge.class.getClassLoader());
                }
            }
        } catch (ReflectiveOperationException error) {
            throw new IllegalStateException("Probe3 host compatibility callback failed", error);
        }
    }

    private static void configureXcode(ClassLoader loader) throws ReflectiveOperationException {
        Class<?> xcode;
        try {
            xcode = Class.forName("org.jetbrains.kotlin.konan.target.Xcode", true, loader);
        } catch (ClassNotFoundException absent) {
            System.err.println("PROBE3: Xcode interface absent in configuration loader=" + loader);
            return;
        }
        String toolchain = requiredPath("probe.toolchain");
        String sysroot = requiredPath("probe.sysroot");
        Object companion = xcode.getField("Companion").get(null);
        Object override = Proxy.newProxyInstance(loader, new Class<?>[]{xcode}, (proxy, method, arguments) -> {
            String name = method.getName();
            if (name.equals("getVersion")) return Class.forName("org.jetbrains.kotlin.konan.target.XcodeVersion", true, loader).getConstructor(int.class, int.class).newInstance(26, 4);
            if (name.equals("getToolchain") || name.equals("getAdditionalTools")) return toolchain;
            if (name.endsWith("Sdk") || name.equals("pathToPlatformSdk")) return sysroot;
            if (name.equals("toString")) return "Gate3 Linux tools and empty sysroot; NOT installed Xcode";
            if (name.equals("hashCode")) return System.identityHashCode(proxy);
            if (name.equals("equals")) return proxy == arguments[0];
            throw new UnsupportedOperationException(name);
        });
        companion.getClass().getMethod("setXcodeOverride", xcode).invoke(companion, override);
        System.err.println("PROBE3: Xcode override installed for loader=" + loader + "; toolchain=" + toolchain + "; emptySysroot=" + sysroot);
    }

    private static String requiredPath(String name) {
        String root = System.getProperty("probe.root");
        String value = System.getProperty(name);
        if (root == null || value == null || !value.startsWith(root + "/")) throw new IllegalStateException("Missing bounded path " + name);
        return value;
    }
}
