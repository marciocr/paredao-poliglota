-- Driver de teste (Lua): aplica um roteiro à lógica do jogo, sem janela.
package.path = arg[1] .. "/?.lua;" .. package.path
local ffi = require("ffi")
local game = require(os.getenv("GAME"))

local g = game.Game.new(0)
g.play = function() end
for line in io.lines(arg[2]) do
    local steps, ks = line:match("^(%S+)%s+(%S+)")
    local keys = ffi.new("uint8_t[512]")
    if ks ~= "-" then for k in ks:gmatch("%d+") do keys[tonumber(k)] = 1 end end
    for _ = 1, tonumber(steps) do g:update(keys, game.STEP) end
end
local alive = 0
for i = 0, 111 do if g.bricks[i] then alive = alive + 1 end end
print(string.format("score=%d lives=%d state=%d paddle_x=%.4f paddle_w=%d bx=%.4f by=%.4f vx=%.4f vy=%.4f level=%d bricks=%d",
    g.score, g.lives, g.state, g.paddle_x, g.paddle_w, g.bx, g.by, g.vx, g.vy, g.level, alive))
