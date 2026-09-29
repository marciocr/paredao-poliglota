import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;

/** Driver de teste (Java): aplica um roteiro à lógica do jogo, sem janela. */
public class Drv {
    public static void main(String[] a) throws Exception {
        var g = new @CLASS@.Game(s -> {});
        for (String line : Files.readAllLines(Path.of(a[0]))) {
            String[] p = line.trim().split("\\s+");
            boolean[] k = new boolean[512];
            if (!p[1].equals("-")) for (String s : p[1].split(",")) k[Integer.parseInt(s)] = true;
            @CLASS@.Keys keys = sc -> k[sc];
            for (long i = 0, n = Long.parseLong(p[0]); i < n; i++) g.update(keys, @CLASS@.STEP);
        }
        int alive = 0;
        for (boolean b : g.bricks) if (b) alive++;
        System.out.println(String.format(Locale.ROOT,
            "score=%d lives=%d state=%d paddle_x=%.4f paddle_w=%d bx=%.4f by=%.4f vx=%.4f vy=%.4f level=%d bricks=%d",
            g.score, g.lives, g.state.ordinal(), g.paddleX, g.paddleW, g.bx, g.by, g.vx, g.vy, g.level, alive));
    }
}
