import VersoBlog

open Verso Genre Blog

#doc (Post) "Teaching 3D geometry with Pyxel" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2025, month := 11, day := 8 }
%%%

![Grisly Adventure](static/projects/adventure/sprites.png)

My kids are between five and eleven, so I usually keep their screen time short—unless they are building the experience themselves. What started as a throwaway line quickly became a pact, and they held me to it. We pulled out sketchbooks, drew some ideas, and soon we were designing a small 3D game together.
![Grisly Adventure](static/projects/adventure/design.jpeg)
We eventually coded it in [Pyxel](https://github.com/kitao/pyxel), a very nice and simple Python framework.
The goal was to build a playground where we could tinker with programming and 3D geometry side by side. Pyxel turned out to be perfect for spinning up a mini arcade project, so we leaned all the way in.

Et Voilà! It is called [*Grisly Adventure*](static/projects/adventure/adventure.html).
![Grisly Adventure](static/projects/adventure/play.jpeg)
You can play it, just click on the [link](static/projects/adventure/adventure.html).
Use the arrow keys to move and the space bar to shoot.

Here are a few moments from the game:
![Grisly Adventure](static/projects/adventure/adventure_1.png)
A few trees burned along the way:
![Grisly Adventure](static/projects/adventure/adventure_2.png)
And of course, the monsters are coming! 😱
![Grisly Adventure](static/projects/adventure/adventure_3.png)

The code is quite short:
```
import pyxel

WIDTH = 640
HEIGHT = 400
FOCUS = 200
TRANSPARENT_COLOR = 1
BACKGROUND_COLOR = 0
SKY_COLOR = 1
GROUND_COLOR = 3
TEXT_COLOR = 7
SPRITES = 0
PLAYER_SPEED = 5
PLAYER_ROTATION_SPEED = 5
BULLET_SPEED = 10
MONSTER_SPEED = 30
NUM_TREES = 500
NUM_ROCKS = 100
NUM_CLOUDS = 50
NUM_MOUNTAINS = 50
NUM_MONSTERS = 10
AREA_SIZE_MULTIPLIER = 1

stage = [0]
player = [None]
bullets = []
monsters = []
trees = []
fireballs = []
rocks = []
clouds = []
mountains = []


class Player:
    def __init__(self, x, y, z=16, angle=0):
        self.x = x
        self.y = y
        self.z = z
        self.w = 16
        self.h = 16
        self.d = FOCUS
        self.angle = angle
        self.score = 0
        player[0] = self

    def project(self, x, y, z):
        translated_x = x - self.x
        translated_y = y - self.y
        translated_z = z - self.z
        rotated_x = translated_x * pyxel.cos(self.angle) + translated_y * pyxel.sin(
            self.angle
        )
        rotated_y = -translated_x * pyxel.sin(self.angle) + translated_y * pyxel.cos(
            self.angle
        )
        rotated_z = translated_z
        scale = self.d / rotated_x if rotated_x > 0 else 0
        u = -scale * rotated_y
        v = -scale * rotated_z
        return u, v, scale

    def draw_drawables(self, drawables):
        projected_entities = []
        for drawable in drawables:
            u, v, scale = self.project(drawable.x, drawable.y, drawable.z)
            projected_entities.append((drawable, u, v, scale))
        projected_entities.sort(key=lambda x: x[3])
        for entity, u, v, scale in projected_entities:
            entity.draw(u, v, scale)

    def update(self):
        if pyxel.btn(pyxel.KEY_LEFT):
            self.angle += PLAYER_ROTATION_SPEED
        if pyxel.btn(pyxel.KEY_RIGHT):
            self.angle -= PLAYER_ROTATION_SPEED
        if pyxel.btn(pyxel.KEY_UP):
            self.x += pyxel.cos(self.angle) * PLAYER_SPEED
            self.y += pyxel.sin(self.angle) * PLAYER_SPEED
        if pyxel.btn(pyxel.KEY_DOWN):
            self.x -= pyxel.cos(self.angle) * PLAYER_SPEED
            self.y -= pyxel.sin(self.angle) * PLAYER_SPEED
        if pyxel.btn(pyxel.KEY_Z):
            if pyxel.btn(pyxel.KEY_UP):
                self.x += pyxel.cos(self.angle) * PLAYER_SPEED * 10
                self.y += pyxel.sin(self.angle) * PLAYER_SPEED * 10
            if pyxel.btn(pyxel.KEY_DOWN):
                self.x -= pyxel.cos(self.angle) * PLAYER_SPEED * 10
                self.y -= pyxel.sin(self.angle) * PLAYER_SPEED * 10
        if pyxel.btn(pyxel.KEY_SPACE):
            if pyxel.frame_count % 5 == 0:
                Bullet(
                    self.x,
                    self.y,
                    self.z / 2,
                    pyxel.cos(self.angle) * BULLET_SPEED,
                    pyxel.sin(self.angle) * BULLET_SPEED,
                    0,
                    0,
                )

    def draw(self):
        pyxel.text(10, 10, f"Score: {self.score}", TEXT_COLOR)


class Bullet:
    def __init__(self, x, y, z, vx, vy, vz, t, lifetime=1000):
        self.x = x
        self.y = y
        self.z = z
        self.vx = vx
        self.vy = vy
        self.vz = vz
        self.t = t
        self.w = 16
        self.h = 16
        self.sprite = pyxel.images[SPRITES]
        self.sprite_u = [32, 48, 32, 48]
        self.sprite_v = [0, 0, 16, 16]
        self.lifetime = lifetime
        bullets.append(self)

    def update(self):
        self.x += self.vx
        self.y += self.vy
        self.z += self.vz
        self.t += 1
        if self.t > self.lifetime:
            bullets.remove(self)

    def draw(self, u, v, scale):
        pyxel.blt(
            WIDTH / 2 + u - self.w / 2,
            HEIGHT / 2 + v - self.h / 2,
            self.sprite,
            self.sprite_u[self.t % 4],
            self.sprite_v[self.t % 4],
            self.w,
            self.h,
            TRANSPARENT_COLOR,
            rotate=0,
            scale=scale,
        )


class Fireball:
    def __init__(self, x, y, z, vx, vy, vz, t, lifetime=1000):
        self.x = x
        self.y = y
        self.z = z
        self.vx = vx
        self.vy = vy
        self.vz = vz
        self.t = t
        self.w = 16
        self.h = 16
        self.sprite = pyxel.images[SPRITES]
        self.sprite_u = [32, 48, 32, 48]
        self.sprite_v = [0, 0, 16, 16]
        self.lifetime = lifetime
        fireballs.append(self)

    def update(self):
        self.x += self.vx
        self.y += self.vy
        self.z += self.vz
        self.t += 1
        if self.t > self.lifetime:
            fireballs.remove(self)

    def draw(self, u, v, scale):
        pyxel.dither(1 - self.t / self.lifetime)
        pyxel.blt(
            WIDTH / 2 + u - self.w / 2,
            HEIGHT / 2 + v - self.h / 2,
            self.sprite,
            self.sprite_u[self.t % 4],
            self.sprite_v[self.t % 4],
            self.w,
            self.h,
            TRANSPARENT_COLOR,
            rotate=0,
            scale=scale * (1 + self.t / self.lifetime),
        )
        pyxel.dither(1)


class Monster:
    def __init__(self, x, y, z=16, t=0):
        self.x = x
        self.y = y
        self.z = z
        self.t = t
        self.w = 32
        self.h = 32
        self.sprite = pyxel.images[SPRITES]
        self.status = 0
        monsters.append(self)

    def update(self):
        if self.status == 0:
            norm = pyxel.sqrt(player[0].x - self.x) ** 2 + (player[0].y - self.y) ** 2
            self.x += (player[0].x - self.x) * MONSTER_SPEED / norm
            self.y += (player[0].y - self.y) * MONSTER_SPEED / norm
        if self.status > 0 and self.status < 100:
            self.status += 1
            # Create fireballs
            Fireball(
                self.x,
                self.y,
                self.z / 2,
                pyxel.rndf(-1, 1),
                pyxel.rndf(-1, 1),
                pyxel.rndf(1, 5),
                0,
                20,
            )
        if self.status == 100:
            monsters.remove(self)

    def draw(self, u, v, scale):
        pyxel.blt(
            WIDTH / 2 + u - self.w / 2,
            HEIGHT / 2 + v - self.h / 2,
            self.sprite,
            0,
            0,
            self.w,
            self.h,
            TRANSPARENT_COLOR,
            rotate=0,
            scale=scale,
        )


class Tree:
    def __init__(self, x, y, z=24, t=0):
        self.scale = pyxel.rndf(0.5, 1.5)
        self.x = x
        self.y = y
        self.z = z * self.scale
        self.w = 32
        self.h = 48
        self.sprite = pyxel.images[SPRITES]
        self.status = 0
        self.sprite_u = [32, 0, 32]
        self.sprite_v = [32, 80, 80]
        trees.append(self)

    def update(self):
        if self.status > 0 and self.status < 100:
            self.status += 1
            # Create fireballs
            Fireball(
                self.x,
                self.y,
                self.z / 2,
                pyxel.rndf(-1, 1),
                pyxel.rndf(-1, 1),
                pyxel.rndf(1, 5),
                0,
                20,
            )

    def draw(self, u, v, scale):
        if self.status == 0:
            pyxel.blt(
                WIDTH / 2 + u - self.w / 2,
                HEIGHT / 2 + v - self.h / 2,
                self.sprite,
                self.sprite_u[0],
                self.sprite_v[0],
                self.w,
                self.h,
                TRANSPARENT_COLOR,
                rotate=0,
                scale=scale * self.scale,
            )
        elif self.status < 100:
            pyxel.blt(
                WIDTH / 2 + u - self.w / 2,
                HEIGHT / 2 + v - self.h / 2,
                self.sprite,
                self.sprite_u[1],
                self.sprite_v[1],
                self.w,
                self.h,
                TRANSPARENT_COLOR,
                rotate=0,
                scale=scale * self.scale,
            )
        else:
            pyxel.blt(
                WIDTH / 2 + u - self.w / 2,
                HEIGHT / 2 + v - self.h / 2,
                self.sprite,
                self.sprite_u[2],
                self.sprite_v[2],
                self.w,
                self.h,
                TRANSPARENT_COLOR,
                rotate=0,
                scale=scale * self.scale,
            )


class Rock:
    def __init__(self, x, y, z=8):
        self.x = x
        self.y = y
        self.z = z
        self.w = 16
        self.h = 16
        self.sprite = pyxel.images[SPRITES]
        self.sprite_u = 16
        self.sprite_v = 64
        rocks.append(self)

    def draw(self, u, v, scale):
        pyxel.blt(
            WIDTH / 2 + u - self.w / 2,
            HEIGHT / 2 + v - self.h / 2,
            self.sprite,
            self.sprite_u,
            self.sprite_v,
            self.w,
            self.h,
            TRANSPARENT_COLOR,
            rotate=0,
            scale=scale,
        )


class Cloud:
    multiplier = 1000

    def __init__(self, x, y, z=128):
        self.x = x * self.multiplier
        self.y = y * self.multiplier
        self.z = pyxel.rndf(0, 1) * z * self.multiplier
        self.w = 32
        self.h = 16
        self.sprite = pyxel.images[SPRITES]
        self.sprite_u = 0
        self.sprite_v = 32
        self.scale = 2
        clouds.append(self)

    def draw(self, u, v, scale):
        pyxel.blt(
            WIDTH / 2 + u - self.w / 2,
            HEIGHT / 2 + v - self.h / 2,
            self.sprite,
            self.sprite_u,
            self.sprite_v,
            self.w,
            self.h,
            TRANSPARENT_COLOR,
            rotate=0,
            scale=self.multiplier * scale * self.scale,
        )


class Mountain:
    multiplier = 10000

    def __init__(self, x, y, z=16):
        self.x = x * self.multiplier
        self.y = y * self.multiplier
        self.z = z * self.multiplier
        self.t = pyxel.rndi(0, 1)
        self.w = [32, 16][self.t]
        self.h = [16, 16][self.t]
        self.sprite = pyxel.images[SPRITES]
        self.sprite_u = [0, 0][self.t]
        self.sprite_v = [48, 64][self.t]
        self.scale = 2
        mountains.append(self)

    def draw(self, u, v, scale):
        pyxel.blt(
            WIDTH / 2 + u - self.w / 2,
            HEIGHT / 2 + v - self.h / 2,
            self.sprite,
            self.sprite_u,
            self.sprite_v,
            self.w,
            self.h,
            TRANSPARENT_COLOR,
            rotate=0,
            scale=self.multiplier * scale * self.scale,
        )


class App:
    def __init__(self):
        pyxel.init(WIDTH, HEIGHT, title="Grisly Journey")
        pyxel.load("assets/sprites.pyxres")
        # self.cleanup()
        self.setup()
        pyxel.run(self.update, self.draw)

    def cleanup(self):
        stage[0] = 0
        player[0] = None
        monsters.clear()
        trees.clear()
        bullets.clear()
        fireballs.clear()
        rocks.clear()
        clouds.clear()
        mountains.clear()

    def setup(self):
        Player(0, 0, 16, 0)
        # Create monsters
        for i in range(NUM_MONSTERS):
            x = sum(
                [
                    pyxel.rndf(
                        -NUM_TREES * AREA_SIZE_MULTIPLIER,
                        NUM_TREES * AREA_SIZE_MULTIPLIER,
                    )
                    for i in range(4)
                ]
            )
            y = sum(
                [
                    pyxel.rndf(
                        -NUM_TREES * AREA_SIZE_MULTIPLIER,
                        NUM_TREES * AREA_SIZE_MULTIPLIER,
                    )
                    for i in range(4)
                ]
            )
            Monster(x, y)
        # Create trees
        for i in range(NUM_TREES):
            x = sum(
                [
                    pyxel.rndf(
                        -NUM_TREES * AREA_SIZE_MULTIPLIER,
                        NUM_TREES * AREA_SIZE_MULTIPLIER,
                    )
                    for i in range(4)
                ]
            )
            y = sum(
                [
                    pyxel.rndf(
                        -NUM_TREES * AREA_SIZE_MULTIPLIER,
                        NUM_TREES * AREA_SIZE_MULTIPLIER,
                    )
                    for i in range(4)
                ]
            )
            Tree(x, y)
        # Create rocks
        for i in range(NUM_ROCKS):
            x = sum(
                [
                    pyxel.rndf(
                        -NUM_TREES * AREA_SIZE_MULTIPLIER,
                        NUM_TREES * AREA_SIZE_MULTIPLIER,
                    )
                    for i in range(4)
                ]
            )
            y = sum(
                [
                    pyxel.rndf(
                        -NUM_TREES * AREA_SIZE_MULTIPLIER,
                        NUM_TREES * AREA_SIZE_MULTIPLIER,
                    )
                    for i in range(4)
                ]
            )
            Rock(x, y)
        # Create clouds
        for i in range(NUM_CLOUDS):
            x = sum(
                [
                    pyxel.rndf(
                        -NUM_TREES * AREA_SIZE_MULTIPLIER,
                        NUM_TREES * AREA_SIZE_MULTIPLIER,
                    )
                    for i in range(4)
                ]
            )
            y = sum(
                [
                    pyxel.rndf(
                        -NUM_TREES * AREA_SIZE_MULTIPLIER,
                        NUM_TREES * AREA_SIZE_MULTIPLIER,
                    )
                    for i in range(4)
                ]
            )
            Cloud(x, y)
        # Create mountains
        for i in range(NUM_MOUNTAINS):
            x = sum(
                [
                    pyxel.rndf(
                        -NUM_TREES * AREA_SIZE_MULTIPLIER,
                        NUM_TREES * AREA_SIZE_MULTIPLIER,
                    )
                    for i in range(4)
                ]
            )
            y = sum(
                [
                    pyxel.rndf(
                        -NUM_TREES * AREA_SIZE_MULTIPLIER,
                        NUM_TREES * AREA_SIZE_MULTIPLIER,
                    )
                    for i in range(4)
                ]
            )
            Mountain(x, y)

    def update(self):
        if pyxel.btnp(pyxel.KEY_Q):
            pyxel.quit()

        if stage[0] == -1:
            if pyxel.btnp(pyxel.KEY_RETURN):
                self.cleanup()
                self.setup()
        elif stage[0] == 0:
            if pyxel.frame_count % 600 == 0:
                x = sum(
                    [
                        pyxel.rndf(
                            -NUM_TREES * AREA_SIZE_MULTIPLIER,
                            NUM_TREES * AREA_SIZE_MULTIPLIER,
                        )
                        for i in range(4)
                    ]
                )
                y = sum(
                    [
                        pyxel.rndf(
                            -NUM_TREES * AREA_SIZE_MULTIPLIER,
                            NUM_TREES * AREA_SIZE_MULTIPLIER,
                        )
                        for i in range(4)
                    ]
                )
                Monster(x, y)

            # Update entities
            player[0].update()
            for monster in monsters:
                monster.update()
            for tree in trees:
                tree.update()
            for bullet in bullets:
                bullet.update()
            for fireball in fireballs:
                fireball.update()

            # Find collisions of bullets with monsters and trees
            for bullet in bullets:
                for monster in monsters:
                    if (
                        bullet.x > monster.x - monster.w / 2
                        and bullet.x < monster.x + monster.w / 2
                        and bullet.y > monster.y - monster.h / 2
                        and bullet.y < monster.y + monster.h / 2
                    ):
                        monster.status += 1
                        player[0].score += 10
                        try:
                            bullets.remove(bullet)
                        except:
                            pass
                for tree in trees:
                    if (
                        bullet.x > tree.x - tree.w / 2
                        and bullet.x < tree.x + tree.w / 2
                        and bullet.y > tree.y - tree.h / 2
                        and bullet.y < tree.y + tree.h / 2
                        and tree.status == 0
                    ):
                        tree.status += 1
                        player[0].score += 1
                        try:
                            bullets.remove(bullet)
                        except:
                            pass

            # Find collisions of monsters with player
            for monster in monsters:
                if (
                    monster.x > player[0].x - player[0].w / 2
                    and monster.x < player[0].x + player[0].w / 2
                    and monster.y > player[0].y - player[0].h / 2
                    and monster.y < player[0].y + player[0].h / 2
                ):
                    stage[0] = -1
                    return

    def burn_factor(self):
        return sum([tree.status > 0 for tree in trees]) / len(trees)

    def draw(self):
        if stage[0] == -1:
            # Draw the game over screen
            pyxel.cls(8)
            pyxel.text(WIDTH // 2, HEIGHT // 2, "Game Over", TEXT_COLOR)
            pyxel.text(
                WIDTH // 2, HEIGHT // 2 + 10, "Press Enter to restart", TEXT_COLOR
            )
        elif stage[0] == 0:
            # Draw the sky
            pyxel.cls(BACKGROUND_COLOR)
            pyxel.dither(0.5)
            pyxel.rect(0, 0, WIDTH, HEIGHT // 2, SKY_COLOR)
            for i, c in enumerate([10, 9, 8, 2]):
                pyxel.rect(0, HEIGHT // 2 - 4 * (i + 1), WIDTH, 4, c)
            player[0].draw_drawables(clouds)
            player[0].draw_drawables(mountains)
            # Draw the ground
            pyxel.dither(1)
            pyxel.rect(0, HEIGHT // 2, WIDTH, HEIGHT, 0)
            pyxel.dither(1 - self.burn_factor())
            pyxel.rect(0, HEIGHT // 2, WIDTH, HEIGHT, GROUND_COLOR)
            pyxel.dither(1)
            player[0].draw_drawables(bullets + monsters + trees + fireballs + rocks)
            player[0].draw()


App()
```
