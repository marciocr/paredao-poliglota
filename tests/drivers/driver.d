
// Driver de teste (D): anexado ao fim do app.d, cujo main() foi renomeado.
int main(string[] args)
{
    import std.algorithm : count;
    import std.stdio : File, writefln;
    import std.string : split, strip;

    Game g;
    g.newGame();
    foreach (line; File(args[1]).byLine)
    {
        auto p = line.strip.split;
        ubyte[512] keys;
        if (p[1] != "-") foreach (k; p[1].split(",")) keys[k.to!int] = 1;
        foreach (_; 0 .. p[0].to!long) g.update(keys.ptr, STEP);
    }
    writefln("score=%d lives=%d state=%d paddle_x=%.4f paddle_w=%d bx=%.4f by=%.4f vx=%.4f vy=%.4f level=%d bricks=%d",
             g.score, g.lives, cast(int) g.state, g.paddleX, g.paddleW, g.bx, g.by, g.vx, g.vy, g.level,
             g.bricks[].count(true));
    return 0;
}
