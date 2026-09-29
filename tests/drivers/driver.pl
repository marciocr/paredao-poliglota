# Driver de teste (Perl): o script foi cortado antes do SDL_Init.
new_game();
open my $fh, '<', $ARGV[0] or die;
while (<$fh>) {
    my ($steps, $ks) = split;
    my @keys = (0) x 512;
    $keys[$_] = 1 for $ks eq '-' ? () : split /,/, $ks;
    update(\@keys, STEP) for 1 .. $steps;
}
printf "score=%d lives=%d state=%d paddle_x=%.4f paddle_w=%d bx=%.4f by=%.4f vx=%.4f vy=%.4f level=%d bricks=%d\n",
    @g{qw(score lives state paddle_x paddle_w bx by vx vy level)}, scalar grep { $_ } @{ $g{bricks} };
