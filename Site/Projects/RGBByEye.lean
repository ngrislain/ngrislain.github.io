import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "RGB by eye" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 11, day := 8 }
%%%

Every screen color is a mix of red, green and blue light. We use hex codes like `#3fa7d6` all day, but could you tell how much red is in that blue just by looking at it? I could not, so I made a small game to practice.

The rules are simple. The game shows a color. You set three sliders, one for red, one for green and one for blue, each between 0% and 100%. You get no preview of your mix. You only see it when you submit, next to the real color, with your score.

:::figframe "static/projects/rgb-by-eye/rgb-by-eye.html" "980"
:::

You can also open it on [its own page](static/projects/rgb-by-eye/rgb-by-eye.html), which works better on a phone.

# Scoring

Write the target color as $`t = (t_r, t_g, t_b)` and your guess as $`g = (g_r, g_g, g_b)`, each component scaled to the range 0 to 1. The score is

$$`\text{score} = \frac{100}{1 + 5\,\lVert t - g \rVert_2}`

A perfect guess gives 100. Being off by 5 points on a single channel gives 80. Being off by 10 points on all three channels gives about 54. Black instead of white, the worst possible answer, still gets about 10. The factor 5 is there to spread the scores. Without it, a random guess already scores around 60, and you cannot tell a good eye from a lucky one.

The L2 distance in RGB space is not how humans see color. We are much more sensitive to some differences than others, and a perceptual space like CIELAB would be fairer. But the point of the game is to learn to read RGB values, so the distance is measured in the same space you are guessing in.

# Two modes

In *Solo* mode you play as many colors as you like. The game keeps your average and your best score.

In *Battle* mode two players share one screen. Both mix the same color one after the other, and the sliders reset in between, so the second player does not see the first answer. After both answers are in, the round is revealed. The best total over 3 to 10 rounds wins.

The game is in English and French. It picks the language of your browser, and you can switch at any time.

# The referee

A small 3D robot called Pixel comments on every round. It cheers when you are close, laughs at you when you are far off, turns to the player whose turn it is, and points at the winner at the end of a battle. It is plain CSS 3D: six faces of a cube, a pair of eyes and a mouth that change shape with the mood. Its antenna glows with the color you are trying to guess.

The whole game is a single HTML file with no dependencies, so it also works offline.
