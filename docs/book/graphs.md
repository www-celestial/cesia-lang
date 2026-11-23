# Graphs

In this chapter you draw data with [std/plot]: lines, points, bars, histograms, heatmaps, densities and bands, texts
and rules, graphs in a circle, surfaces and lines in 3D, and animations of them. A graph is a value, as a number or a list is: you make it, put several on shared axes, and draw it to
an SVG file, or Cemacs draws it on its screen. Each step from the data to the pixels follows a published method, named here with its paper, and the
tests of Cesia check what each step promises.

> [!NOTE]
> The first graphs have tabs: the same graph in Python with matplotlib and in R with its own graphics. Each tab runs when
> the book is checked and must end well, printing what the Cesia version shows: here nothing, as `Ok(missing)` says. They
> have no MATLAB tab yet. See [Tabs in other languages](tests.md#tabs-in-other-languages).

## A first graph

[plot.Line] makes a line through points, [plot.Of] puts several layers on shared axes with a title and the names of the
axes, and [plot.Save] writes the graph to a file:

```cesia allow=read,write
use std/plot
use std/num
use std/math
use std/result
t = num.Linspace(0.0, 10.0, 200)
waves = plot.Of([plot.Line(t, math.Sin(t), label = "sin"), plot.Line(t, math.Cos(t), label = "cos", dash = "dashed")],
  title = "Two waves", x = "time (s)", y = "value")
plot.Save(waves, "waves.svg") -->
```

```python
import numpy as np
import matplotlib.pyplot as plt
t = np.linspace(0.0, 10.0, 200)
fig, ax = plt.subplots(figsize=(6.4, 4.0))
ax.plot(t, np.sin(t), label="sin")
ax.plot(t, np.cos(t), label="cos", linestyle="dashed")
ax.set(title="Two waves", xlabel="time (s)", ylabel="value")
ax.legend()
fig.savefig("waves.svg")
```

```r
t <- seq(0, 10, length.out = 200)
svg("waves.svg", width = 6.4, height = 4)
plot(t, sin(t), type = "l", main = "Two waves", xlab = "time (s)", ylab = "value")
lines(t, cos(t), lty = "dashed")
legend("topright", legend = c("sin", "cos"), lty = c("solid", "dashed"))
invisible(dev.off())
```

`waves.svg` is an image of 640 by 400 pixels in *SVG*, Scalable Vector Graphics, the format of drawings that every web
browser opens and that stays sharp at any zoom. It is black on white: the two lines are black, the first solid and the
second dashed, and the texts are in JetBrains Mono, the font of the code in Cemacs, which draws the graph the same. The
legend shows because the layers have a label.

## A graph is a value

Nothing is drawn when a graph is made. [plot.Line] gives a [plot.Graph] of one layer, and a layer alone is a graph: it
shows with axes of its own. [plot.Of] joins the layers of the graphs it is given, the later on top; [plot.Grid] sets
graphs side by side, each with its own axes, as `subplot` does in MATLAB. Three functions draw a graph: [plot.Svg] gives
its SVG text, [plot.Save] writes that text to a file, and [plot.Scene] gives the shapes it is made of, in pixels, which
Cemacs draws, as [Scenes](#scenes-for-a-back-end) shows. Here are the labels of the ticks of the time axis above:

```cesia
scene = result.Unwrap(plot.Scene(waves, 640, 400))
[item.Text for item in scene.Items if item.Role == "xlabel"] -->
```

| Function | What it draws |
|---|---|
| [plot.Line] `(x, y, label, color, width, dash)` | a line through the points, cut at each NaN |
| [plot.Points] `(x, y, label, color, size, shape)` | a marker at each point, up to 200,000 |
| [plot.Bars] `(names, heights, label, color)` | a bar for each name, or a group of bars with a list of lists |
| [plot.Histogram] `(values, bins, label, color)` | the values counted in bins |
| [plot.Heatmap] `(values, x, y, colors)` | a matrix as colored cells, with a color bar |
| [plot.Density] `(x, y, bins)` | points of any number counted per cell, a 2D histogram |
| [plot.Area] `(x, low, high, label, color)` | the band between two curves |
| [plot.Surface] `(z, x, y, colors)` | a surface in 3D, the height `z[i, j]` over `(x[j], y[i])` |
| [plot.Text] `(x, y, texts, color, size, anchor, dx, dy)` | texts beside points of the data |
| [plot.Rule] `(x, y, label, dash, color)` | a line of reference across the plot |
| [plot.Line3] `(x, y, z, label, color, width, dash)` | a line in 3D |
| [plot.Of] `(layers, title, x, y, xscale, yscale, xlim, ylim, legend, size, z, zlim, view, note, noteAt, xticks, xlabels, yticks, ylabels, polar)` | layers on shared axes |
| [plot.Grid] `(graphs, columns)` | graphs side by side |
| [plot.Frames] `(graphs, fps)` | graphs one after the other: an animation |
| [plot.Svg] `(g)`, [plot.Save] `(g, path)`, [plot.Scene] `(g, width, height, frame, view, mark, xlim, ylim, points)` | the drawing |

A color is written `"#rrggbb"`, the red, green and blue of a color in two hexadecimal digits each, as in CSS. A layer
without a color is black, as [Colors](#colors) says: lines told apart by their dash, points by their shape, bars by
their shade of grey. Any layer takes a color of its own, each its own, to tell curves apart by color or to bring one
forward.

### Lines and points

[plot.Line] joins the points in the order given. A NaN, *not a number*, or an infinity in `x` or `y` cuts the line: it
leaves a gap there, as matplotlib does, so a missing measure doesn't draw a false segment. A line is 1 pixel wide unless
`width` says otherwise. `dash` is `"dashed"`, `"dotted"` or `"dashdot"`, with the patterns of matplotlib's default style
scaled by the width: 3.7 on and 1.6 off, 1 and 1.65, and 6.4, 1.6, 1, 1.6 widths.

[plot.Points] draws a marker at each point, `"circle"`, `"square"`, `"triangle"`, `"diamond"`, `"cross"` or `"plus"`, of
`size` pixels across; without `shape`, the next of the turn of [Colors](#colors). A point with a NaN or an infinity is left out, and the scene counts it in `Dropped`. At most 200,000
points are drawn one by one: past that, a cloud of markers hides its own shape, and the file grows by about 20 bytes a
point, so [plot.Points] gives an `Err` that names [plot.Density], which counts any number of points per cell.

```cesia
noisy = plot.Points([1, 2, 3, 4], [2.0, math.Nan, 3.5, 1.0], shape = "diamond")
result.Unwrap(plot.Scene(noisy, 640, 400)).Dropped -->
```

### Bars and histograms

[plot.Bars] draws a bar from 0 to each height, one for each name. With a list of lists, the bars of a name stand side by
side, one series for each list, and `label` and `color` are lists, one for each series:

```cesia norun
plot.Bars(["north", "south", "west"], [[12, 9, 4], [14, 7, 6]], label = ["2025", "2026"])
```

```python
import numpy as np
import matplotlib.pyplot as plt
names = ["north", "south", "west"]
x = np.arange(len(names))
fig, ax = plt.subplots()
ax.bar(x - 0.2, [12, 9, 4], width=0.4, label="2025")
ax.bar(x + 0.2, [14, 7, 6], width=0.4, label="2026")
ax.set_xticks(x, names)
ax.legend()
fig.savefig("bars.svg")
```

```r
svg("bars.svg")
barplot(rbind(c(12, 9, 4), c(14, 7, 6)), beside = TRUE, names.arg = c("north", "south", "west"),
  legend.text = c("2025", "2026"))
invisible(dev.off())
```

A graph holds one [plot.Bars]. Other layers can share its axes: the first name is at `x = 1`, the second at `x = 2`, and
on, so a line through `[1, 2, 3]` crosses the bars at their middles. A name too wide for its bar turns its label upright.

[plot.Histogram] counts values in *bins*, intervals side by side, and draws a bar for each. `bins` is missing for the rule
of Freedman and Diaconis, a count for that many bins of equal width from the least value to the greatest, or a list of
edges, increasing. A bin holds the values from its left edge, included, to its right edge, left out, and the last bin holds
its right edge too, as numpy does. NaNs, infinities and values outside the edges are left out.

The rule of Freedman and Diaconis (1981) makes bins of width $h = 2 \cdot IQR \cdot n^{-1/3}$, where $n$ is the
number of values and the IQR, the *interquartile range*, is the distance between the first quartile, the value below which
a quarter of the values lie, and the third, below which three quarters lie. Their paper shows that the error of a
histogram as an estimate of the density of the values, measured in $L^2$, is least for bins of a width that shrinks as
$n^{-1/3}$, and proposes $2 \cdot IQR$ for the factor: the IQR keeps the width from following a few far
values. The count of bins is $\lceil (\max - \min) / h \rceil$, at most 10,000. When the IQR is 0, as when most values are
equal, the width would be 0, and the rule of Sturges (1926), $\lceil \log_2 n \rceil + 1$ bins, takes its place. The
quartiles interpolate between the two nearest sorted values, the *type 7* of Hyndman and Fan, which numpy and R use by
default. The counts come from the sorted values, by a binary search for each edge.

### Heatmaps and densities

[plot.Heatmap] colors each cell of a matrix by its value, and puts a *color bar*, the scale from colors to values,
beside it. `x` gives the value of each column and `y` of each row, increasing; a cell reaches halfway to its neighbors.
Without `y`, row 1 is at the top, as the matrix is written, and the rows are numbered down. A NaN leaves its cell empty.

```cesia norun
m = [-2.0, 0.5, 1.0; 1.5, -0.5, 3.0]
plot.Heatmap(m, colors = "diverging")
```

```python
import numpy as np
import matplotlib.pyplot as plt
m = np.array([[-2.0, 0.5, 1.0], [1.5, -0.5, 3.0]])
fig, ax = plt.subplots()
cells = ax.imshow(m, cmap="RdBu_r", vmin=-3.0, vmax=3.0)
fig.colorbar(cells)
fig.savefig("heatmap.svg")
```

```r
m <- matrix(c(-2, 0.5, 1, 1.5, -0.5, 3), nrow = 2, byrow = TRUE)
svg("heatmap.svg")
image(t(m[nrow(m):1, ]), col = hcl.colors(21, "Blue-Red"), zlim = c(-3, 3), axes = FALSE)
invisible(dev.off())
```

[plot.Density] is a *2D histogram*: it splits the range of the points into `bins` by `bins` cells, 100 by 100 by
default, counts the points of each cell, and colors the cells by their count. Every point is counted, none is sampled,
so a cloud of ten million points shows as it is. An empty cell stays empty.

A plot of 640 pixels can't show 1,000 columns: past one cell per pixel along an axis, the cells merge in blocks, as many
as needed to fit, by their mean for a heatmap and their sum for a density, so that no cell is skipped. A heatmap without
NaN merges by two matrix products, $a \cdot m \cdot b$, where $a$ and $b$ hold a 1 for each row or column of a block.

### Bands

[plot.Area] fills the band from `low` to `high` along `x`, at 30 % opacity so that what lies below shows through: a
confidence interval, the envelope of a signal. A NaN in any of the three cuts the band.

```cesia norun
mean = math.Sin(t)
spread = 0.2 + 0.1 * math.Cos(t)
plot.Of([plot.Area(t, mean - spread, mean + spread, label = "±1 σ"), plot.Line(t, mean, label = "mean")])
```

```python
import numpy as np
import matplotlib.pyplot as plt
t = np.linspace(0.0, 10.0, 200)
mean = np.sin(t)
spread = 0.2 + 0.1 * np.cos(t)
fig, ax = plt.subplots()
ax.fill_between(t, mean - spread, mean + spread, alpha=0.3, label="±1 σ")
ax.plot(t, mean, label="mean")
ax.legend()
fig.savefig("band.svg")
```

```r
t <- seq(0, 10, length.out = 200)
middle <- sin(t)
spread <- 0.2 + 0.1 * cos(t)
band <- adjustcolor("steelblue", alpha.f = 0.3)
svg("band.svg")
plot(t, middle, type = "n", ylim = range(middle - spread, middle + spread), xlab = "", ylab = "")
polygon(c(t, rev(t)), c(middle - spread, rev(middle + spread)), col = band, border = NA)
lines(t, middle)
legend("topright", legend = c("±1 σ", "mean"), fill = c(band, NA), border = NA, lty = c(NA, 1))
invisible(dev.off())
```

### Options of a graph

[plot.Of] takes the options of the axes: `title`; `x` and `y`, the names of the axes; `xscale` and `yscale`, `"linear"`
or `"log"` for a logarithmic axis in base 10, where each power of ten takes the same length; `xlim` and `ylim`, the range
of an axis as `[low, high]`; `legend = false` to hide the legend, `legend = "ends"` to name each line at its end;
`size = [width, height]` in pixels, 640 by 400 by default, 100 by 80 at least; `note` and `noteAt`, a box of text at a
corner; `xticks`, `xlabels`, `yticks` and `ylabels`, ticks of your own; `polar = true`, a graph in a circle. The sections
below show each. The options of an [plot.Of] given as a layer are left aside: those of the outer one apply. A 3D graph
takes `z`, `zlim` and `view` too, as [3D](#3d) shows; on a graph of 2D they are an error.

### Texts and rules

[plot.Text] writes texts on the graph, each beside its point of the data: `texts[i]` at `(x[i], y[i])`, moved `dx`
pixels to the right and `dy` down, 4 and -4 by default, so that it sits above and right of a marker. `anchor` is the side
of the text at that place, `"left"`, `"middle"` or `"right"`; `size` is in pixels, 11 by default, from 4 to 96. It is a
layer as the others: it follows the axes, a text whose point is past `xlim` is left out, and it has no entry in the
legend. At most 100,000 texts, so that a scene stays small enough for Cemacs; past that, an `Err` says how many.

```cesia
hour = [7, 8, 9, 10, 11]
height = [5.0, 14.0, 21.0, 26.0, 28.0]
morning = plot.Of([plot.Line(hour, height), plot.Points(hour, height, size = 4), plot.Text(hour, height, ["$h h" for h in hour])])
[x.Text for x in result.Unwrap(plot.Scene(morning, 640, 400)).Items if x.Kind == "text" and x.Role == "data"] -->
```

The texts are a list comprehension, `["$h h" for h in hour]`, the short form of [list.Map]`(h -> "$h h", hour)`.

[plot.Rule] draws a line of reference across the plot: `x = 180` upright at 180, `y = 0` across at 0, exactly one of
the two. It is grey unless `color` says otherwise, takes a `dash` as a line does, and writes its `label` at its end,
inside the plot. The range of its axis grows to hold it, as for the data; the other axis is left to the other layers.

```cesia
noon = plot.Of([plot.Line([0, 90, 180, 270, 360], [0, 30, 60, 30, 0]), plot.Rule(x = 180, label = "S"), plot.Rule(y = 0, label = "horizon", dash = "dashed")])
[x.Text for x in result.Unwrap(plot.Scene(noon, 640, 400)).Items if x.Kind == "text" and x.Role == "data"] -->
```

### A note, and names at the ends

`note` puts a box of text at a corner of the plot, a line for each line of the text, as the name, the place and the date
of what is drawn; `noteAt` is `"top left"`, the default, `"top right"`, `"bottom left"` or `"bottom right"`. The box has
no frame: its lines are in the ink of the axes, on the *paper*, the background, which hides the grid behind them. Spaces
are kept, so that the colons of the lines can stand one under the other:

```cesia
place = plot.Of([plot.Line(hour, height)], note = "name: essai\n  lat: 40.76\n  lon: -73.984")
[x.Text for x in result.Unwrap(plot.Scene(place, 640, 400)).Items if x.Role == "info" and x.Kind == "text"] -->
```

`legend = "ends"` names each line at its end, in place of the box of the legend: its label right of its last point
inside the plot, in its color, as a printed chart names its curves. Two labels that would overlap are moved apart a line,
by a pass from the top, then by a pass from the bottom for those that would leave the plot: a greedy layout, the
simplest that keeps the labels in the order of the lines. The margin on the right grows to hold them. Points and bands
are named at their last point too; bars and histograms have no end, and with `"ends"` they are an `Err`.

```cesia
three = plot.Of([plot.Line(hour, height * k, label = "×$k") for k in [1, 2, 3]], legend = "ends")
[x.Text for x in result.Unwrap(plot.Scene(three, 640, 400)).Items if x.Role == "legend"] -->
```

### Ticks of your own

`xticks` and `yticks` give the ticks of an axis in place of those of the search that [Ticks](#ticks) describes: a list of
numbers, increasing, at most 1,000; those inside the range of the axis are drawn, each with its line of the grid.
`xlabels` and `ylabels` give their labels, as many texts as ticks, else an `Err`; without them, the numbers are written
as the computed ticks are, each the shortest decimal that reads back to it. A log axis takes ticks above 0. Without these
options nothing changes.

```cesia
use std/list
compass = plot.Of([plot.Line([0, 90, 180, 270, 360], [1, 3, 2, 4, 1])], xticks = list.Range(0, 360, step = 90), xlabels = ["N", "E", "S", "W", "N"])
[x.Text for x in result.Unwrap(plot.Scene(compass, 640, 400)).Items if x.Role == "xlabel"] -->
```

[list.Range]`(0, 360, step = 90)` is `[0, 90, 180, 270, 360]`; `0..360`, its short form without a step, would be every
integer.

### Polar graphs

`polar = true` draws the graph in a circle, as a compass or the path of the sun: `x` is an angle in degrees, 0 at the
top, turning clockwise, so that 90 is on the right, as the east on a map; `y` is the distance from the center. `ylim` is
`[center, rim]`, in either order: `[90, 0]` puts 90 at the center and 0 on the rim, as the height of the sun, straight up
at 90 and on the horizon at 0. Without it, 0, or the least `y` below it, is at the center, and the greatest `y` and 5 %
more on the rim. Rings stand at the ticks of `y`, written along the ray of 0, and rays at the ticks of `x`, every 30
degrees unless `xticks` gives them, written outside the rim with a degree sign, as matplotlib's polar axes write them.

```cesia
dome = plot.Of([plot.Line([60, 120, 180, 240, 300], [0, 40, 60, 40, 0])], polar = true, ylim = [90, 0])
[x.Text for x in result.Unwrap(plot.Scene(dome, 500, 500)).Items if x.Role == "ylabel"] -->
```

A polar graph is square, its disc in the middle of the room that the texts leave. It draws [plot.Line], [plot.Points],
[plot.Text] and [plot.Rule], a rule at `x` as a ray and at `y` as a ring. A line joins its points by straight segments,
as matplotlib's polar axes join them, and is cut where it crosses the rim, the crossing computed so that the line ends on
it; points and texts outside the disc are left out. A line that ends on the right of the rim is named, with `"ends"`,
past the labels of the angles. With a 3D graph, a log axis or `xlim`, `polar` is an `Err`.

### The size of a graph

A graph is 640 by 400 pixels unless `size = [width, height]` gives its own, and a polar graph 500 by 500, as much room
as 640 by 400 in a square; [plot.Svg] and [plot.Save] write it at that size. Under a cell, Cemacs draws it as wide as the
pane, never wider than the graph itself, and as high as the shape of its own size asks: a graph of 640 by 400 in a pane
of 500 pixels is 500 by 313, and a polar graph stays square. [plot.Scene] gives a back-end that size when its height is
missing:

```cesia
[result.Unwrap(plot.Scene(dome, 900, missing)).Width, result.Unwrap(plot.Scene(waves, 500, missing)).Height] -->
```

## A sun path from simple formulas

The page *position of the sun* of SunEarthTools draws the path of the sun across the sky of a place, a curve for the 21st
of each month, the day of today among them in orange with its hours, its name, its place and its date in a corner, and
each curve named at its end: on a flat grid and in a circle. This section draws a chart in its spirit, from invented
smooth days rather than from astronomy. A day here is three numbers: the azimuth where the sun rises, east of north, its
height at noon, due south, and its hours of light. The sun turns at an even pace from its rise to its setting at
`360 - rise`, its height half a sine:

```cesia allow=read,write
defn sun(rise, noon, light, t)
  (** The sun of an invented day at the times t, in hours: its azimuth and its height, in degrees. *)
  f = (t - (12.0 - light / 2.0)) / light
  {Az: rise + (360.0 - 2.0 * rise) * f, El: noon * math.Sin(math.Pi * f)}
end
day(rise, noon, light) = sun(rise, noon, light, num.Linspace(12.0 - light / 2.0, 12.0 + light / 2.0, 61))
days = [day(58, 72.6, 15.0), day(61, 69.5, 14.6), day(74, 61, 13.4), day(90, 49.2, 12.1), day(106, 38, 10.9), day(118, 29.5, 9.8), day(122, 25.8, 9.3)]
names = ["21 Jun solstice", "21 May-Jul", "21 Apr-Aug", "21 Mar-Sep equinox", "21 Feb-Oct", "21 Jan-Nov", "21 Dec solstice"]
today = day(117, 28, 9.6)
clock = 8..16
hours = sun(117, 28, 9.6, clock)
orange = "#e07000"
where = "name: essai\n  lat: 40.76\n  lon: -73.984\n date: 23/11/2026"
flat = plot.Of(list.Concat([plot.Line(days[k].Az, days[k].El, label = names[k]) for k in 1..7],
  [plot.Line(today.Az, today.El, color = orange, label = "23/11/2026"), plot.Points(hours.Az, hours.El, color = orange, size = 4),
   plot.Text(hours.Az, hours.El, ["$h" for h in clock], color = orange), plot.Rule(x = 180, label = "S")]),
  x = "azimuth", y = "elevation", xlim = [0, 360], ylim = [0, 90], xticks = list.Range(0, 360, step = 45),
  xlabels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "N"], yticks = list.Range(0, 90, step = 10), note = where,
  size = [760, 420], title = "Sun path")
plot.Save(flat, "sunpath.svg") -->
```

The seven days are black, told apart by their dash; today alone has a color, as on the page. Its hours are a
[plot.Text] beside a [plot.Points]: `clock` is `8..16`, the short form of [list.Range]`(8, 16)`, and the texts
`["$h" for h in clock]` that of [list.Map]`(h -> "$h", clock)`. The legend is the box: the days all end on the horizon,
where names at their ends would stand in a heap.

In a circle, the azimuth is the angle and the height the distance from the rim, `ylim = [90, 0]`. Each day is read from
its setting back to its rise, so that it ends in the east, on the right of the disc, where `legend = "ends"` writes its
name, past the labels of the rim:

```cesia allow=read,write
east(d) = {Az: list.Reverse(d.Az), El: list.Reverse(d.El)}
dial = plot.Of(list.Concat([plot.Line(east(days[k]).Az, east(days[k]).El, label = names[k]) for k in 1..7],
  [plot.Line(east(today).Az, east(today).El, color = orange, label = "23/11/2026"), plot.Points(hours.Az, hours.El, color = orange, size = 4),
   plot.Text(hours.Az, hours.El, ["$h" for h in clock], color = orange), plot.Rule(x = 180, label = "S")]),
  polar = true, ylim = [90, 0], xticks = list.Range(0, 350, step = 10), yticks = list.Range(0, 90, step = 10),
  legend = "ends", note = where, size = [760, 560], title = "Sun path")
plot.Save(dial, "sundial.svg") -->
[x.Text for x in result.Unwrap(plot.Scene(dial, 760, 560)).Items if x.Role == "legend"] -->
```

The page draws a picture made on its server; here the chart is a value, drawn the same by [plot.Save] and by Cemacs, in
the font of the code, black on white with the one color that says something.

## Animations

[plot.Frames] makes an *animation*: graphs shown one after the other, `fps` of them a second (*frames per second*), from
the first to the last and then again. Here a wave moves to the right, 60 frames at 30 a second, two seconds in all:

```cesia allow=read,write
use std/text
x = num.Linspace(0.0, 10.0, 200)
wave = plot.Frames([plot.Of([plot.Line(x, math.Sin(x - t))], title = "t = $(text.Decimals(1, t))") for t in num.Linspace(0.0, 6.0, 60)], fps = 30)
plot.Save(wave, "wave.svg") -->
```

The list of frames is written as a *list comprehension*, `[f(t) for t in ts]`, the short form of [list.Map]:

```cesia
use std/list
plain = plot.Frames(list.Map(t -> plot.Of([plot.Line(x, math.Sin(x - t))], title = "t = $(text.Decimals(1, t))"), num.Linspace(0.0, 6.0, 60)), fps = 30)
plot.Svg(plain) == plot.Svg(wave) -->
```

An animation is a graph: [plot.Svg] and [plot.Save] write it whole, and [plot.Scene] draws one of its frames, `frame`
from 1, with two fields more in the scene, `Frames`, their number, and `Fps`:

```cesia
one = result.Unwrap(plot.Scene(wave, 640, 400, frame = 30))
[one.Frames, one.Fps, [item.Text for item in one.Items if item.Role == "title"]] -->
```

### What a frame changes

The frames share one set of axes, so that the axes never jump while it plays. [plot.Frames] checks every frame once,
when it is made, and keeps the range of each layer over all of them: each frame is drawn on the union of these ranges,
the colors of a heatmap too, unless `xlim` and `ylim` give the axes. A frame changes only its data and its title; its
layers, in kind and number, their options, such as a color or a label, and the options of [plot.Of] are those of the
first frame, or the animation is an `Err` that names the first frame that differs:

```cesia
plot.Svg(plot.Frames([plot.Line([1, 2], [1, 2]), plot.Line([1, 2], [2, 1], color = "#000000")])) -->
```

An animation holds 1 to 300 frames, 10 seconds at 30 a second, and `fps` is from 1 to 60. All the frames are in
memory: they are values, made once, and play at their own rate whatever they cost to compute. A frame is no grid and no
animation, and an animation goes in no [plot.Of] and no [plot.Grid].

### In a web page: frames of CSS

*CSS*, Cascading Style Sheets, is the language of the style of a web page, which every browser runs without a script.
The SVG of an animation writes the axes once, and the data and the title of each frame in a group of its own. One rule
of CSS hides every group, and an *animation of CSS*, a change of style over time, shows each in turn:

```css
.a60-200000 { visibility: hidden; animation: s60 2000ms step-end infinite; }
@keyframes s60 { 0% { visibility: visible; } 1.6667% { visibility: hidden; } }
```

The loop lasts $N / fps$ seconds, here 60 frames at 30 a second, 2 seconds. Each group is visible during the first
$100 / N$ percent of the loop, rounded up at the fourth decimal so that a frame always shows, and starts after a delay of
$(k - 1) / fps$ seconds, `style="animation-delay:33.33ms"` for frame 2: frame $k$ shows from $(k - 1) / fps$ to $k / fps$
of each loop. `step-end` makes each change a jump, not a fade. The names of the rules hold only numbers, the count of
frames and the length of the loop, so that two animations of one page each keep their own, and no text of a graph goes
into the CSS.

An SVG alone, opened in a browser, plays at once and loops; for a reader who asked the system for less motion, the
setting `prefers-reduced-motion`, it stays on frame 1. The page of a file of cells, [cells.Html], starts it paused on
frame 1, under a box *Play*, a check box of the page that the mouse, or Tab then Space, checks; see
[A page to share](cells.md#a-page-to-share). This follows WCAG 2.2, the rules of the W3C for accessible pages, whose
criterion 2.2.2 asks that what moves for more than 5 seconds can be paused. A test checks in Chromium and in Firefox
that frame $k$ alone shows on its interval, that a page starts on frame 1, and that the box of one animation leaves the
others still; Safari is not checked.

An SVG keeps at most 8 MB of frames, so that a page loads fast: past that, it keeps every $k$-th frame, $k$ the least
that fits, at $fps / k$ a second so that it lasts as long, and a note under the graph says so, `100 of 300 frames kept`.
300 frames of a wave of 500 points take 2.1 MB; 300 frames of the Lorenz curve of 5,000 points would take 20 MB, so its
SVG keeps 100. Cemacs never thins: it asks for each frame when it shows it.

### Compared with matplotlib, plotly and MATLAB

| | Cesia | matplotlib `FuncAnimation` | plotly | MATLAB, Octave |
|---|---|---|---|---|
| frames | values, made once, at most 300 | made by a function at each frame, as many as wanted, without end for `frames=None` | a list of frames in the figure | images captured by `getframe` |
| axes | the union of all frames, computed | those the function and the figure set | Plotly Express "will not automatically compute the union of all x/y/color ranges": they are given by hand | those of the figure at each capture |
| playing | Cemacs, and a page with no script | a window, or `to_jshtml`, a page with a script | in the browser, with plotly.js and the buttons and slider it draws | `movie(M, n, fps)`, 12 a second by default |
| files | SVG, 8 MB at most | movies and GIFs: `save` with FFmpeg or Pillow | HTML with its script | `VideoWriter`: Motion JPEG AVI, MPEG-4 and others |

Where they win: all three write video or GIF files, which Cesia doesn't; matplotlib computes frames as they play, so an
animation has no length and no cap; plotly moves from one frame to the next by a smooth transition, for its scatter and
bar charts, and its page can go to any frame with a slider, with a script. Where Cesia wins: the axes are shared by
itself, a frame that changes more than its data is an error that names it, and the page plays with no script.

## 3D

[plot.Surface] draws a *surface*, a height over a grid: `z[i, j]` is the height over the point `(x[j], y[i])`, so the
rows of the matrix go along y and its columns along x, as MATLAB's `surf` takes them. [plot.Line3] draws a line through
points in space, as [plot.Line] does in the plane. Here a ripple, $\sin(2r) / (1 + r)$ at the distance $r$ from the
middle, on a grid of 61 by 61 points:

```cesia allow=read,write
use std/matrix
x = num.Linspace(-3.0, 3.0, 61)
across = matrix.Matmul(matrix.Ones(61, 1), matrix.Reshape([1, 61], x))
r = math.Sqrt(across * across + matrix.Transpose(across) * matrix.Transpose(across))
ripple = plot.Of([plot.Surface(math.Sin(2.0 * r) / (1.0 + r), x = x, y = x)], x = "x", y = "y", z = "height")
plot.Save(ripple, "ripple.svg") -->
```

`across` holds `x[j]` in each column $j$, and its transpose `y[i]` in each row $i$: the grid of both, as `meshgrid` gives
it in MATLAB and numpy. [plot.Of] gives a 3D graph three options more: `z`, the name of its third axis, `zlim`, its range,
and `view`, where it is seen from. A 3D graph holds one [plot.Surface], or [plot.Line3] layers, never both and never a
layer of 2D; its axes are linear.

### The view

A *view* is two angles in degrees, `view = [az, el]`, as MATLAB's `view` takes them. The *azimuth* `az` turns around the
vertical axis: 0 looks from the side of $-y$, toward $+y$, and the azimuth grows counterclockwise seen from above. The
*elevation* `el`, from $-90$ to $90$, is the angle of the eye above the plane of x and y: 90 looks from straight above,
$-30$ from below. Without one a graph takes MATLAB's own, `[-37.5, 30]`:

```cesia
result.Unwrap(plot.Scene(ripple, 640, 400)).View -->
result.Unwrap(plot.Scene(ripple, 640, 400, view = [0, 90])).View -->
```

[plot.Scene] takes a `view` too, which turns the graph without changing it: Cemacs turns a graph so, and the code keeps
its own view. The data go into a box of 1 by 1 by 0.75, as matplotlib's: each axis covers the data exactly, or its
`xlim`, `ylim` or `zlim`, and its range takes the whole side of the box. The box is seen from far away, without
perspective, an *orthographic* projection, MATLAB's default: lines that are parallel in space stay parallel on the
screen. With $p$ a point of the box, measured from its center, the eye looks along $v$, and the screen's right and up are
$e_1$ and $e_2$:

$$v = (\cos el \sin az, -\cos el \cos az, \sin el),\quad e_1 = (\cos az, \sin az, 0),\quad e_2 = (-\sin el \sin az, \sin el \cos az, \cos el)$$

The point is drawn at $c + s\,(p \cdot e_1, -p \cdot e_2)$, from the center $c$ of the plot, $s$ pixels a unit, and its
depth, how near it is, is $p \cdot v$. The box turns inside the sphere around it, of radius
$\sqrt{0.5^2 + 0.5^2 + 0.375^2} \approx 0.8004$, and $s$ makes that sphere fit the plot, with room for the labels: so the
box keeps its size at every view, as `axis vis3d` keeps it in MATLAB, and a graph doesn't swell and shrink as it turns.
A test puts the 8 corners of the box where these formulas put them, at 6 views.

The axes are three edges of the box, on its outline, with their ticks and labels, found as in 2D by the search of
Talbot, Lin and Hanrahan for the length each edge shows: x and y on the lowest edges, z on the edge most to the left. An
axis that points at the eye shows no labels, as z seen from straight above. The three far sides of the box are shaded
light, with the grid of the ticks, as matplotlib draws them; a test checks at 72 views and 3 sizes that no two texts
meet and that all stay inside the graph.

### The order of the quads

A surface is drawn as *quads*, the four-sided pieces between four neighbor points of the grid, each filled with one color.
Painted one over the other, the nearest must come last: this is the *painter's algorithm*, by Newell, Newell and Sancha
(1972), which draws polygons from far to near. matplotlib sorts the polygons by their mean depth, and its own FAQ says why
it fails: the "reduction of 3D data down to 2D + z-order scalar", one depth for a whole polygon, so that "from some
viewing angles" an object "would appear in front of another object, even though it is physically behind it".

A surface needs no sort. Its quads stand on a grid whose x and y each increase or each decrease, and seen without
perspective, the trace of a ray of the eye on the plane of x and y is a straight line, along which the depth grows one
way. That line meets the columns of the grid in order, and the rows in order. So the quads drawn row after row from the
far side, and in each row column after column from the far side, put every quad that a ray meets behind another before
it:

1. the rows by increasing y when $v_y (y_{last} - y_{first}) \ge 0$, else by decreasing y;
2. the columns the same, with $v_x$ and x.

It is the case of one sheet of the order of McMillan (1995), who computes visibility without depth; Anderson (1982) walks
a grid the same way for hidden lines. The order costs nothing: the sort it replaces takes 3.3 ms for 100 by 100 quads and
14 ms for 200 by 200. A test draws random surfaces, uneven in x and y, increasing or decreasing, at random views and at
the views on the axes, and checks at points of the screen that two quads or more cover that the quad painted last is the
nearest one: 10 grids in the change loop, 1,500 in the slow tests, and 10,500 once, with no failure. The same check of
matplotlib's sort found 0.6 % to 29 % of such points wrong, from a flat surface to a rough one.

### Colors, holes and large surfaces

A quad takes the color of the mean of its four heights, as matplotlib's `plot_surface` colors them, among the 256 of
viridis, or of `colors = "diverging"` as for [plot.Heatmap], and a color bar beside says which height each color is.
There is no light and no edge: the color alone says the height, as in MATLAB's `surf`, whose colors "vary according to
the heights". A NaN leaves out the four quads around it, a *hole*, and [plot.Scene] counts it in `Dropped`; an infinity is
an error that names its place:

```cesia
plot.Svg(plot.Surface([1, 2; 3, 1.0 / 0.0])) -->
```

A quad with a corner past `xlim`, `ylim` or `zlim` is left out too, as matplotlib's `axlim_clip` hides "patches with a
vertex outside the axes view limits"; a [plot.Line3] is cut at a point past them, as at a NaN.

A surface draws up to 200 by 200 quads exactly. Past 200 in a direction, its points become the means of blocks of $k$ by
$k$ points, $k$ the least that fits, x, y and z each the mean of its block, NaNs left out; a note under the graph says so:

```cesia
big = matrix.Ones(1000, 300)
[item.Text for item in result.Unwrap(plot.Scene(plot.Surface(big), 640, 400)).Items if item.Role == "note"] -->
```

matplotlib keeps 50 points a direction by default, "downsampled (by slicing)": one row in $k$, which can step over a
narrow peak; a mean keeps a trace of it, smoothed. [plot.Surface] checks its matrix and takes these means once, when it
is made, so that a graph turned again and again pays for them once.

### 3D lines

[plot.Line3] takes x, y and z, and the label, color, width and dash of [plot.Line]. Several share a graph, drawn in their
order, the later on top: unlike a surface, two lines that cross in depth are drawn in the order of the layers, a limit
of this version. Here the Lorenz system, solved by [std/ode], as [Numerical methods](numerical.md) shows:

```cesia allow=read,write
use std/ode
lorenz(t, y) = [10.0 * (y[2] - y[1]), y[1] * (28.0 - y[3]) - y[2], y[1] * y[2] - 8.0 / 3.0 * y[3]]
ys = result.Unwrap(ode.Solve(lorenz, [0.0, 50.0], [1.0, 1.0, 1.0])).At(num.Linspace(0.0, 50.0, 5000))
plot.Save(plot.Of([plot.Line3(ys[:, 1], ys[:, 2], ys[:, 3])], x = "x", y = "y", z = "z"), "lorenz.svg") -->
```

### In Cemacs and in a page

Cemacs turns a 3D graph of a cell or of `*repl*` when it is dragged, or with the arrows after `C-c e f`: each view is
drawn by the session, by [cells.Scene] with `view`, and only the places of the points of the surface cross back; the code
keeps its view. The page of [cells.Html] shows each graph at the view of its code, and its SVG has a `<title>` that a
screen reader says, as `Surface, 61 × 61 points, z from −0.301 to 0.584`.

### Compared with matplotlib, plotly and MATLAB

| | Cesia | matplotlib `mplot3d` | plotly `go.Surface` | MATLAB, Octave `surf` |
|---|---|---|---|---|
| drawing | quads from far to near, an order exact for one surface, no sort | polygons sorted by one depth each, wrong at some views by its own FAQ | WebGL in the browser, a depth buffer | the graphics card's depth buffer |
| several surfaces, a line on a surface | no: one surface, or 3D lines | yes, with the faults of its sort | yes | yes |
| colors | the mean height of a quad, viridis; no light, no edge | a single color shaded by a light by default, or a colormap | a colorscale, and a light: ambient 0.8, diffuse 0.8 | the height, `FaceColor` flat, dark edges by default |
| large surfaces | means of blocks past 200 by 200 quads, said under the graph | 50 points a direction by default, by slicing | all the points | all the points |
| turning | Cemacs, by the session; the page shows the view of the code | a window | the page, with plotly.js | a window, `rotate3d` |

Where they win: plotly turns its graph in the page itself, with a script, shows the value under the mouse and draws
contours on the surface; MATLAB, Octave and plotly draw several surfaces that cross, with light and transparency, as a
depth buffer does; all three offer perspective. Where Cesia wins: its picture is exact at every view without a graphics
card, the same in Cemacs and in the SVG, and a large surface is smoothed by means, said under the graph, not sliced.

## From data to pixels

### The range of an axis

An axis covers the data of its layers, and 5 % of that range more on each side, as matplotlib and ggplot2 do, so that no
point sits on the frame; on a log axis, the 5 % are taken of the range of the logarithms. Bars and histograms start at
0, so their axis doesn't pass below 0 when no value does. The cells of a heatmap or a density cover their axis exactly.
`xlim` and `ylim` give the range exactly, and the data past it is cut at the frame. When all the values are one value, the
axis covers 10 % of it on each side, or 1 around 0, or half a power of ten on a log axis. A log axis with a value at 0
or below is an `Err` that names the layer and the first such value.

### Ticks

The *ticks* are the marks along an axis, with their labels. [std/plot] places them by the extended Wilkinson algorithm
of Talbot, Lin and Hanrahan (2010). It tries steps of $q \cdot 10^z$, with $q$ among 1, 5, 2, 2.5, 4 and 3, the first
simpler, labels every $j$-th multiple of the step, from 3 to 12 labels, and scores each set of labels by four measures:

- *simplicity*, $1 - \frac{i - 1}{5} - j + v$, where $i$ is the place of $q$ in the list and $v$ is 1 when 0 is a label;
- *coverage*, $1 - \frac{1}{2} \cdot \frac{(d_{max} - l_{max})^2 + (d_{min} - l_{min})^2}{(0.1 (d_{max} - d_{min}))^2}$:
  how much of the axis's range $[d_{min}, d_{max}]$ the labels $[l_{min}, l_{max}]$ span;
- *density*, $2 - \max(r / r_t, r_t / r)$, where $r$ is the number of labels per unit and $r_t$ the target, one label per
  100 pixels along x and per 60 along y;
- *legibility*: minus infinity when two labels would touch, less than 6 pixels apart along x, or less than a line and
  2 pixels apart along y; 1 otherwise.

The score is $0.25 s + 0.2 c + 0.5 d + 0.05 l$, the weights of the paper, and the search stops a branch as soon as the
best score it could still reach is below the best found. One change from the
paper: the range of the axis is fixed first, as the section above says, and only the sets of labels inside it are tried,
so every tick lies on the axis. When no set fits, the labels are written shorter, with a power of ten, and when none
fits still, on an axis too short for three labels, the best set is taken as it is.

A label is the shortest decimal that reads back to its tick: `0.5`, `2`, `−1.5`, with the true minus sign, U+2212. It is
written from integers, $n \cdot 10^e$ for each tick, never from the binary float, so `0.30000000000000004` can't show.
Past $10^6$, or below $10^{-4}$, the labels count in a power of ten, shown once at the end of the axis: `1`, `2`, `3`
and `×10⁷`. When the ticks share 4 leading digits or more, as times in seconds since 1970, they count from an *offset*,
a round number shown there too: `2`, `4`, `6` and `+1.7314×10⁹`. Both are matplotlib's ways, with thresholds of their
own.

A log axis puts its ticks at the powers of ten, written `10ⁿ`: every one, or every second, third, fifth or more, so that
3 to 12 fit. With fewer than 3 powers of ten in its range, it adds 2 and 5 times each power; with fewer than 3 ticks
still, it places them as a linear axis would.

### Text, and the size of each label

The margins around the plot are measured, not guessed: each label's width is the sum of the *advance widths* of its
characters, how far each moves the pen, in the font Cemacs draws with, JetBrains Mono 2.304, the font of its code. It is
*monospaced*: each of its 1,363 characters moves the pen 0.6 *em*, the size of the font, but the combining marks, which
move it none, so a label of 12 pixels is 7.2 pixels a character. [std/plot] counts a text so, in *columns*, as a
terminal counts them, by the rules of Markus Kuhn's `wcwidth`: a column a character, none for a combining mark, a soft
hyphen or a character of zero width, two for a wide character of East Asia, which the font lacks and another font draws
about an em wide. A test measures the characters of graphs with SDL3_ttf, the text library of Cemacs, and finds every
one within a pixel.

The SVG names JetBrains Mono first, then the browser's own monospace font: a viewer without JetBrains Mono draws the
texts in another monospaced font, as DejaVu Sans Mono, Menlo or Consolas, whose characters are as wide, 0.6 em or a
little less, so the layout holds. A character that JetBrains Mono lacks, as the superscript minus of `10⁻³`, is drawn by
another font, Noto Sans Medium in Cemacs.

With the widths known, the layout reserves the title, the labels of the ticks, the names of the axes, the legend and the
color bar, and gives the plot what is left. A label at the end of an axis may reach past the plot: the margin grows to
hold it. The tests check, on graphs of random data and random sizes, that every text lies inside the image and that no
two labels of an axis overlap.

### Long lines: M4

A line of ten million points drawn on 600 pixels puts thousands of points in each column of pixels. *M4*, by Jugel,
Jerzak, Hackenbroich and Markl (2014), keeps four points of each column: the first, the last, the lowest and the
highest. The pixels lit are the same as with all the points: the first and the last join the columns as all the points
did, and the lowest and the highest span the column as all of them did. The paper proves it for a line one pixel wide,
drawn without anti-aliasing at the size the points were grouped for; a test of [std/plot] draws lines of 60,000 points
both ways with Bresenham's algorithm (1965), the classic way to draw a line on a grid of pixels, and compares every
pixel. An anti-aliased or wider line, as Cemacs and browsers draw, can differ by a shade at the edge of a column.

[std/plot] uses M4 when x never decreases along the line and there are more than 4 points per column of the plot. A line
whose x goes back and forth, as a circle, keeps all its points.

### Colors

A graph is black on white, the grid a light grey, `#d0d0d0`, 1 pixel wide, as are the frame and the lines. The layers
without a color are black, the ink of the axes, and tell themselves apart by what black and white keep:

| Layers without a color | In turn |
|---|---|
| [plot.Line], [plot.Line3], without `dash` | solid, dashed, dotted, dash-dot |
| [plot.Points], without `shape` | circle, square, triangle, cross |
| the series of [plot.Bars], [plot.Histogram] | black, then the ink at 60, 40 and 30 %: the greys of matplotlib's `grayscale` style |
| [plot.Area] | the ink at 30 %, a grey |

The fifth of a kind starts the turn again. A layer with a `color` keeps a solid line or a circle and takes no turn: a
color is given where it says something, to tell curves apart or to bring one forward, as the day of today among the
others. The same graph prints and photocopies in black and white without losing a curve.

Heatmaps and densities use *viridis*, by van der Walt and Smith (2015): its lightness grows evenly from the least value to
the greatest, so equal steps of the data look like equal steps of color, a *perceptually uniform* map, and it stays in
order in grey and for color-blind eyes. A value takes one of its 256 colors, those of matplotlib's table, number
$\lfloor 256 (v - v_{min}) / (v_{max} - v_{min}) \rfloor$, the last for the greatest. `colors = "diverging"` takes
ColorBrewer's RdBu, by Harrower and Brewer (2003), for data around 0: dark blue for the most negative, white at 0, dark
red for the most positive, with its 11 colors joined by straight lines, and the same distance on both sides of 0. The
themes of Cemacs change the axes and the texts, never the colors of the data.

## Scenes, for a back-end

[plot.Scene] gives what a graph is made of, so that a program other than a browser can draw it: `{Width, Height,
Items, Dropped}`, its items in the order they are drawn, each a dictionary with a `Kind` and a `Role`; the scene of a
frame of an animation has `Frames` and `Fps` too, and the scene of a 3D graph `View`, the `[az, el]` it is seen from:

| Kind | Fields |
|---|---|
| `"line"` | `Xs`, `Ys`, `Color`, `Width`, `Dash` (missing, or the lengths on and off) |
| `"area"` | `Xs`, `Ys` around the band, `Color`, `Opacity` |
| `"rect"` | `X`, `Y`, `W`, `H`, `Color`, `Opacity` |
| `"marks"` | `Xs`, `Ys`, the centers, `Shape`, `Size`, `Color` |
| `"cells"` | `Xs` and `Ys`, the edges of the columns and the rows, `Colors` row after row, missing for an empty cell |
| `"mesh"` | the quads of a surface: `Rows` and `Columns`, their counts; `Xs` and `Ys`, the places of the `(Rows + 1) × (Columns + 1)` points, column by column, to a hundredth of a pixel; `Palette`, its colors; `Colors`, for each quad column by column, its place in `Palette` from 0, or -1 for a hole; `Order`, `[rowStep, columnStep]`, each 1 or -1 |
| `"text"` | `X`, `Y` on the baseline, `Text`, `Size`, `Color`, `Anchor` (`"start"`, `"middle"` or `"end"`), `Angle` (0 or -90), `Width` |

Coordinates are in pixels from the top left corner. The items of the data have `Clip`, the rectangle `[x, y, width,
height]` of the plot they are cut to. A `Color` is `"#rrggbb"`, or `"ink"` and `"grid"` for the frame, the ticks and the
texts, which a back-end paints in the colors of its theme, as it does `"ink"` for the layers without a color and
`"paper"` for what hides the grid behind a text; [plot.Svg] paints them `#000000`, `#d0d0d0` and `#ffffff`. The
`Role` says what an item is: `"grid"`, `"data"`, `"frame"`, `"tick"`, `"xlabel"`, `"ylabel"` and `"zlabel"` for the
labels of the ticks, `"factor"` for the power of ten or the offset of an axis, `"title"`, `"xtitle"`, `"ytitle"`,
`"ztitle"`, `"legend"`, `"colorbar"`, `"note"`, a line under the graph, or `"info"`, the box of the option `note`, its
paper and its lines; in 3D, `"pane"` for the far sides of the box and `"axis"` for the edges that hold the labels. A
polar graph has the same roles: its rays and rings are `"grid"`, its rim `"frame"`, the labels of its angles `"xlabel"`
and those of its rings `"ylabel"`. The labels of `legend = "ends"` have the role `"legend"`.

A *mark* points at one point of the data, as the row of a table points at its point: `mark = [i, n]` rings point $i$ of
each layer of $n$ points, [plot.Line], [plot.Points] or [plot.Text], at its exact place, even where M4 left it out of a
long line, and writes its values in a box beside the first, `x = 2  y = 4`, the items of the role `"mark"`. The scene
then has `Points`, for each such layer, `{Layer, Kind, Label, Count, At, Xs, Ys, Values}`: its place among the layers,
`"line"`, `"points"` or `"text"`, its label, the number of its points in the data, the positions from 1 of its points on
the screen, those that M4 keeps of a long line, at most 100,000, their places in pixels, to a hundredth, and their values,
`{X, Y}`. A mark is for a 2D graph; a grid, an animation or a 3D graph has none. [cells.Scene] asks it of a session, as
[Cells](cells.md#a-row-and-its-point) tells.

```cesia
path3 = plot.Of([plot.Line([1, 2, 3], [3, 4, 2]), plot.Points([1, 2, 3], [3, 4, 2])])
marked = result.Unwrap(plot.Scene(path3, 640, 400, mark = [2, 3]))
[x.Text for x in marked.Items if x.Role == "mark" and x.Kind == "text"] -->
[[p.Kind, p.At] for p in marked.Points] -->
```

An editor that shows the values under the mouse asks the scene once with `points = true`: `Points` then holds every layer
of [plot.Line], [plot.Points] and [plot.Text], linked to a mark or not, and the scene has `Axes` too, how the data meet
the pixels, so that the point nearest the mouse and its values are found with no other question, and a zoom is computed
about the mouse. `Axes` has `X` and `Y`, each `{Scale, Low, High, From, To}`: its scale, `"linear"`, `"log"`, or
`"names"` for the axis of the names of bars, the range of its data from `Low` to `High`, and the pixels of `Low` and
`High` along it, `From` and `To`, which run up for y. A value $v$ is at the pixel
$From + (t(v) - t(Low)) / (t(High) - t(Low)) \times (To - From)$, $t$ the logarithm in base 10 on a log axis and the
value itself on a linear one. A polar graph has `Center`, `[x, y]` in pixels, and `Y` alone, its `From` and `To` the
distances from the center of the values at the center and on the rim. `xlim` and `ylim` draw the graph with these ranges
in place of its own, as the options of [plot.Of] do, without changing the graph: the view zoomed or moved, as Cemacs does
with the wheel and the mouse; a polar graph takes `ylim` alone, `[center, rim]`.

```cesia
zoomed = result.Unwrap(plot.Scene(path3, 640, 400, xlim = [1.5, 3], points = true))
[zoomed.Axes.X.Low, zoomed.Axes.X.High, zoomed.Axes.X.Scale] -->
[[p.Layer, p.At, p.Values.Y] for p in zoomed.Points] -->
```

The points and the axes come only when they are asked: a first graph is drawn as fast without them, and an editor asks
them of the graph under the mouse alone. The values come with the places, as the places are rounded to a hundredth of a
pixel, which would not give back the values of the data to their last digit.

A back-end draws a mesh by its `Order`: the rows from the first when `rowStep` is 1, from the last when it is -1, and in
each row the columns the same way; each quad is the path through its points $(i, j)$, $(i + 1, j)$, $(i + 1, j + 1)$ and
$(i, j + 1)$, where point $(i, j)$ is number $(j - 1)(Rows + 1) + i$ of `Xs` and `Ys`. [plot.Svg] writes each quad as one
path of its color in a group with `shape-rendering="crispEdges"`, so that no hairline shows between two quads; Cemacs
splits each in two triangles of its color. At a grazing view a quad folded on itself may differ by a pixel or two
between the two, in its own color.

## Errors

Every mistake in a graph gives an `Err` of kind `"plot"` from [plot.Svg], [plot.Save] and [plot.Scene], which name the
layer and say what to do; making the graph never fails, so a graph is checked once, when it is drawn:

```cesia
plot.Svg(plot.Of([plot.Line([1, 2, 3], [1, 2]), plot.Points([1], [1], shape = "star")])) -->
plot.Svg(plot.Of([plot.Line([1, 10], [0, 5], label = "rate")], yscale = "log")) -->
```

The checks: the lengths of `x` and `y`, a value that is no number, no finite value at all, a log axis with a value at 0
or below, more than 200,000 points, a count of bins below 1 or edges that don't increase, a color, a shape, a dash, a
scale or a range written wrong, and a size too small for the plot; in 3D, a surface of fewer than 2 by 2 points, an
infinity in it, an x or a y that neither increases nor decreases, a view that is not `[az, el]` with `el` from -90 to 90,
a 3D graph that holds more than one surface or a layer of 2D, and `z`, `zlim` or `view` on a graph of 2D:

```cesia
plot.Svg(plot.Of([plot.Surface([1, 2; 3, 4]), plot.Line3([1, 2], [1, 2], [1, 2])])) -->
```

## Speed

A program that doesn't use [std/plot] starts as fast as before: 2.8 ms for `io.Print(1)`. `use std/plot` loads its 3,000
lines in about 11 ms the first time, before the cache of loaded packages holds them; once it does, a first graph, from
the start of the program to its SVG, takes 7 ms. Then [plot.Svg] takes,
the median of 21 runs on a desktop of 8 cores:

| Graph | Time |
|---|---|
| a line of 1,000 points | 2.0 ms |
| a line of 100,000 points | 7.4 ms |
| a line of 1,000,000 points | 37 ms |
| a line of 10,000,000 points | 324 ms |
| a heatmap of 100 by 100 | 17 ms |
| a heatmap of 1,000 by 1,000 | 298 ms |

All of it is Cesia, made fast by the JIT; for a long line, the pass over the points that finds their range and the pass
of M4 take most of the time.

An animation of 300 frames of a wave of 500 points is made in 21 ms, the check of every frame and their shared ranges,
and written as SVG in 0.43 s, 2.1 MB. One frame of the Lorenz curve, 5,000 points, takes 1.2 ms to draw as a scene; its
SVG of 300 frames, thinned to 100, takes 2.8 s. In Cemacs, a frame of it comes back from the session in about 10 ms, and
it plays at 29 to 30 frames a second.

A surface of 100 by 100 quads is checked and its quads colored once, when [plot.Surface] makes it, in 6.2 ms; then a
scene of it at a new view takes 2.9 ms, the places of its 10,201 points and the axes, and its JSON 3.4 ms, 192
KB; its SVG takes 38 ms, 855 KB. A surface of 1,000 by 1,000 points is made in 119 ms, the means of its blocks of
5 by 5 included, and then draws as fast as one of 200 by 200. In Cemacs, a surface of 100 by 100 quads turns in 30 ms
a step, from the key to the frame that shows the new view.

### Beside matplotlib

The same graphs by matplotlib 3.11.2 on Agg, on the machine of [Speed](speed.md#beside-the-giants), on 2026-11-19: each
timed inside its program, after a first graph drawn and not timed, so that the time is the drawing and not the loading;
the median of 101 runs alternated, and the 95 % interval of that median:

| | Cesia | matplotlib 3.11.2 |
|---|---:|---:|
| a line of 1,000,000 points, to SVG | **28.2 ms** (28.1 to 28.2) | 113.1 ms (112.8 to 113.4) |
| a surface of 100 by 100 quads, a new view | **3.17 ms** (3.15 to 3.18), a scene | 75.27 ms (74.98 to 75.46), `view_init` and a draw |
| the same surface, to SVG | **33.9 ms** (33.8 to 34.1) | 804.1 ms (801.2 to 809.5) |

matplotlib draws the line with its path simplification, on by default, and the surface with every point,
`rstride = cstride = 1`, as Cesia draws every quad; at its default of 50 points a direction it would draw a quarter of
them. A view is not the same work in both: Cesia's is a scene, the shapes in pixels that Cemacs then paints, the mean of
20 views; matplotlib's is a draw of the figure on Agg, its pixels painted, which is what an `mplot3d` window does at
each drag, the mean of 20 views too. matplotlib wins none of the three; its view gives pixels ready to show, where Cesia
leaves the painting to Cemacs.

## Limits

- SVG only, for now; PNG will come with a rasterizer chosen by measure.
- One font is measured, JetBrains Mono; another monospaced font draws as wide or a little narrower, a proportional
  font narrower.
- The legend and the color bar sit right of the plot, or the names at the ends of the lines; bars stand upright; a graph
  holds one [plot.Bars].
- A polar graph draws lines, points, texts and rules, on linear axes, a full turn; no bars or bands in a circle yet.
- A line whose x goes back and forth keeps all its points; past 200,000 markers, use [plot.Density].
- No zoom in this version. An animation holds 300 frames at most, all in memory, and is written as SVG, not as a video
  or a GIF.
- In 3D: one surface a graph, or lines, never both; no perspective, no light, no edges, no transparency, no contours on
  the surface, no points or log scales in 3D; 3D lines are drawn in the order of their layers; a grid or an animation
  of 3D graphs shows them at the view of their code, and Cemacs doesn't turn them; a page shows the view of the code.

## Further reading

- Justin Talbot, Sharon Lin, Pat Hanrahan. "An Extension of Wilkinson's Algorithm for Positioning Tick Labels on Axes".
  *IEEE Transactions on Visualization and Computer Graphics* 16(6):1036–1043, 2010. <https://doi.org/10.1109/TVCG.2010.130>.
  The search for the ticks and its four scores.
- Uwe Jugel, Zbigniew Jerzak, Gregor Hackenbroich, Volker Markl. "M4: A Visualization-Oriented Time Series Data
  Aggregation". *Proceedings of the VLDB Endowment* 7(10):797–808, 2014. <https://doi.org/10.14778/2732951.2732953>. The
  four points per column of pixels of a long line.
- David Freedman, Persi Diaconis. "On the histogram as a density estimator: L2 theory". *Zeitschrift für
  Wahrscheinlichkeitstheorie und verwandte Gebiete* 57(4):453–476, 1981. <https://doi.org/10.1007/BF01025868>. The width
  of the bins.
- Herbert A. Sturges. "The Choice of a Class Interval". *Journal of the American Statistical Association*
  21(153):65–66, 1926. <https://doi.org/10.1080/01621459.1926.10502161>. The count of bins when the IQR is 0.
- Rob J. Hyndman, Yanan Fan. "Sample Quantiles in Statistical Packages". *The American Statistician* 50(4):361–365,
  1996. <https://doi.org/10.1080/00031305.1996.10473566>. The quartiles, by its type 7.
- Stéfan van der Walt, Nathaniel Smith. "matplotlib colormaps", the page of the colormaps they designed as matplotlib's
  default, with their talk at SciPy 2015. <https://bids.github.io/colormap/>. Viridis, from the table of matplotlib 3.11.
- Mark Harrower, Cynthia A. Brewer. "ColorBrewer.org: An Online Tool for Selecting Colour Schemes for Maps". *The
  Cartographic Journal* 40(1):27–37, 2003. <https://doi.org/10.1179/000870403235002042>. RdBu.
- J. E. Bresenham. "Algorithm for computer control of a digital plotter". *IBM Systems Journal* 4(1):25–30, 1965.
  <https://doi.org/10.1147/sj.41.0025>. The pixels of a line, in the test of M4.
- W3C. *CSS Animations Level 1*. <https://www.w3.org/TR/css-animations-1/>. The keyframes, the delays and `step-end`
  of the frames of an animation.
- W3C. *Media Queries Level 5*, `prefers-reduced-motion`. <https://www.w3.org/TR/mediaqueries-5/#prefers-reduced-motion>.
  The animation that stays on frame 1.
- W3C. *Web Content Accessibility Guidelines (WCAG) 2.2*, success criterion 2.2.2, Pause, Stop, Hide.
  <https://www.w3.org/TR/WCAG22/#pause-stop-hide>. The page that starts paused.
- Martin E. Newell, Richard G. Newell, Tom L. Sancha. "A solution to the hidden surface problem". *Proceedings of the
  ACM Annual Conference*, 443–450, 1972. <https://doi.org/10.1145/800193.569954>. The painter's algorithm.
- Leonard McMillan. *Computing Visibility Without Depth*. Technical report TR95-047, University of North Carolina at
  Chapel Hill, 1995. The order of a projected grid, a single sheet without perspective.
- Peter R. Anderson. "Hidden Line Elimination in Projected Grid Surfaces". *ACM Transactions on Graphics* 1(4):274–288,
  1982. <https://doi.org/10.1145/357311.357313>. A grid walked in order, for hidden lines.
- MathWorks. *view*, the documentation of MATLAB's camera line of sight.
  <https://www.mathworks.com/help/matlab/ref/view.html>. The azimuth, the elevation and the view `[-37.5, 30]`.
- The Matplotlib development team. *mplot3d FAQ*, "My 3D plot doesn't look right at certain viewing angles", and
  `Axes3D.plot_surface`. <https://matplotlib.org/stable/api/toolkits/mplot3d/faq.html>. The sort of matplotlib, its
  downsampling and `axlim_clip`.
- Markus Kuhn. *wcwidth*, the widths of the characters of Unicode in a terminal, 2007.
  <https://www.cl.cam.ac.uk/~mgk25/ucs/wcwidth.c>. The columns of a text: none, one or two.
- JetBrains. *JetBrains Mono*, version 2.304, SIL Open Font License 1.1. <https://www.jetbrains.com/lp/mono/>. The font
  of the texts, each of its characters 600 thousandths of an em wide.

## Next

You can draw what you compute. The next chapter, [Numerical methods](numerical.md), finds the zeros and minima of
functions, solves differential equations and sparse systems, and computes integrals.
