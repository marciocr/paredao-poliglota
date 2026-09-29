// Driver de teste (C#): completa a classe do jogo (agora "partial") com um Main.
using System;
using System.Globalization;
using System.IO;
using System.Linq;

unsafe partial class @CLASS@
{
    static int Main(string[] args)
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var g = new Game(_ => { });
        byte* keys = stackalloc byte[512];
        foreach (var line in File.ReadAllLines(args[0]))
        {
            var p = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            for (int i = 0; i < 512; i++) keys[i] = 0;
            if (p[1] != "-") foreach (var s in p[1].Split(',')) keys[int.Parse(s)] = 1;
            for (long i = 0, n = long.Parse(p[0]); i < n; i++) g.Update(keys, STEP);
        }
        Console.WriteLine($"score={g.Score} lives={g.Lives} state={(int)g.State} paddle_x={g.PaddleX:F4} paddle_w={g.PaddleW} bx={g.Bx:F4} by={g.By:F4} vx={g.Vx:F4} vy={g.Vy:F4} level={g.Level} bricks={g.Bricks.Count(b => b)}");
        return 0;
    }
}
