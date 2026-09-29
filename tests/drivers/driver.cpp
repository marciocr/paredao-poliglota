// Driver de teste (C++): inclui o jogo, renomeando o main() dele.
#define main jogo_main
#include "main.cpp"
#undef main
#include <cstdio>
#include <fstream>
#include <sstream>

int main(int, char** argv) {
    Game g;
    std::ifstream f(argv[1]);
    std::string line;
    while (std::getline(f, line)) {
        std::istringstream ss(line);
        long steps;
        std::string ks;
        ss >> steps >> ks;
        Uint8 keys[512] = {};
        if (ks != "-") {
            std::stringstream k(ks);
            std::string n;
            while (std::getline(k, n, ',')) keys[std::stoi(n)] = 1;
        }
        for (long i = 0; i < steps; ++i) g.update(keys, STEP);
    }
    int alive = 0;
    for (bool b : g.bricks) alive += b;
    std::printf("score=%d lives=%d state=%d paddle_x=%.4f paddle_w=%d bx=%.4f by=%.4f vx=%.4f vy=%.4f level=%d bricks=%d\n",
                g.score, g.lives, g.state, g.paddle_x, g.paddle_w, g.bx, g.by, g.vx, g.vy, g.level, alive);
}
