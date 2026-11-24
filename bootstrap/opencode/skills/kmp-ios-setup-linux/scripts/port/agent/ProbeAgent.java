import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;
import java.util.jar.JarFile;
import org.jetbrains.org.objectweb.asm.ClassReader;
import org.jetbrains.org.objectweb.asm.ClassWriter;
import org.jetbrains.org.objectweb.asm.ClassVisitor;
import org.jetbrains.org.objectweb.asm.MethodVisitor;
import org.jetbrains.org.objectweb.asm.Opcodes;

/** Transformer only; Kotlin classes are never resolved in premain. */
public final class ProbeAgent {
    private static boolean installed;

    public static synchronized void premain(String helperJar, Instrumentation instrumentation) throws Exception {
        // KGP forwards system properties to new compiler JVMs. A property marker
        // would incorrectly tell a fresh JVM that instrumentation is installed.
        if (installed) {
            System.err.println("PROBE3: duplicate agent option ignored in same JVM");
            return;
        }
        installed = true;
        // -Dprobe.root is the toolchain root from the machine record. Every agent path must stay inside it.
        String root = System.getProperty("probe.root");
        if (root == null || helperJar == null || !helperJar.startsWith(root + "/")) throw new IllegalArgumentException("Bounded bootstrap helper jar required");
        instrumentation.appendToBootstrapClassLoaderSearch(new JarFile(helperJar));
        Class<?> bridge = Class.forName("ProbeBridge", true, null);
        if (bridge.getClassLoader() != null) throw new IllegalStateException("Bridge is not bootstrap-loaded");
        if (!instrumentation.isRetransformClassesSupported()) throw new IllegalStateException("Retransform-capable ordering is required after Gradle's stored-byte replacement transformer");
        instrumentation.addTransformer(new ClassFileTransformer() {
            public byte[] transform(ClassLoader loader, String name, Class<?> type, ProtectionDomain domain, byte[] bytes) {
                if (!name.equals("org/jetbrains/kotlin/konan/target/HostManager")) return null;
                ClassReader reader = new ClassReader(bytes);
                ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_MAXS);
                reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
                    public MethodVisitor visitMethod(int access, String name, String descriptor, String signature, String[] exceptions) {
                        MethodVisitor original = super.visitMethod(access, name, descriptor, signature, exceptions);
                        if (!name.equals("<init>")) return original;
                        return new MethodVisitor(Opcodes.ASM9, original) {
                            public void visitInsn(int opcode) {
                                if (opcode == Opcodes.RETURN) {
                                    super.visitVarInsn(Opcodes.ALOAD, 0);
                                    super.visitMethodInsn(Opcodes.INVOKESTATIC, "ProbeBridge", "enable", "(Ljava/lang/Object;)V", false);
                                }
                                super.visitInsn(opcode);
                            }
                        };
                    }
                }, 0);
                System.err.println("PROBE3: transformed HostManager constructors; loader=" + loader + "; source=" + domain.getCodeSource().getLocation());
                return writer.toByteArray();
            }
        }, true);
        System.err.println("PROBE3: installed lazy transformer; bootstrap helper only; os.name=" + System.getProperty("os.name"));
    }
}
