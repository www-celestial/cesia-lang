# Graphs

In this chapter you draw data with [std/plot]: lines, points, bars, histograms, heatmaps, densities and bands. A graph is a
value, as a number or a list is: you make it, put several on shared axes, and draw it to an SVG file, or Cemacs draws it
on its screen. Each step from the data to the pixels follows a published method, named here with its paper, and the
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
browser opens and that stays sharp at any zoom. The legend shows because the layers have a label.

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
| [plot.Of] `(layers, title, x, y, xscale, yscale, xlim, ylim, legend, size)` | layers on shared axes |
| [plot.Grid] `(graphs, columns)` | graphs side by side |
| [plot.Svg] `(g)`, [plot.Save] `(g, path)`, [plot.Scene] `(g, width, height)` | the drawing |

A color is written `"#rrggbb"`, the red, green and blue of a color in two hexadecimal digits each, as in CSS. A layer
without a color takes the next of the palette of [Colors](#colors).

### Lines and points

[plot.Line] joins the points in the order given. A NaN, *not a number*, or an infinity in `x` or `y` cuts the line: it
leaves a gap there, as matplotlib does, so a missing measure doesn't draw a false segment. `dash` is `"dashed"`,
`"dotted"` or `"dashdot"`, with the patterns of matplotlib's default style scaled by the width: 3.7 on and 1.6 off,
1 and 1.65, and 6.4, 1.6, 1, 1.6 widths.

[plot.Points] draws a marker at each point, `"circle"`, `"square"`, `"triangle"`, `"diamond"`, `"cross"` or `"plus"`, of
`size` pixels across. A point with a NaN or an infinity is left out, and the scene counts it in `Dropped`. At most 200,000
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
of an axis as `[low, high]`; `legend = false` to hide the legend; `size = [width, height]` in pixels, 640 by 400 by
default, 100 by 80 at least. The options of an [plot.Of] given as a layer are left aside: those of the outer one apply.

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
characters, how far each moves the pen, in the font Cemacs draws with, Noto Sans Medium. [std/plot] holds these widths
for the Latin letters, Latin-1 and Latin Extended-A, Greek, and the punctuation, superscripts, subscripts and minus sign of
numbers and units, read from the font file by `tools/plot-font.ce`. A test measures each of them with SDL3_ttf, the text
library of Cemacs, and finds every one within a pixel. A character outside these, as a Chinese one, counts a whole *em*,
the size of the font, as wide as any of these glyphs but `‰`, so that no label overlaps or is cut, at the cost of some
room. The soft hyphen counts nothing, as shaping hides it.

The texts are drawn without *kerning*, the small moves between pairs of letters such as `AV`, so that the widths measured
are the widths drawn. The SVG names Noto Sans first, then the browser's own sans-serif: a viewer without Noto Sans
draws the texts in another font, a little wider or narrower than measured. The ink of a few letters, as an `f` or an
`î` at the end of a label, reaches up to about 0.2 em past its advance, 2 pixels at 12; the space kept between labels,
6 pixels, covers it.

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

The layers take the eight colors of Okabe and Ito (2008) in turn, chosen to stay apart for the common forms of color
blindness: blue `#0072b2`, vermillion `#d55e00`, bluish green `#009e73`, reddish
purple `#cc79a7`, sky blue `#56b4e9`, orange `#e69f00`, yellow `#f0e442` and black `#000000`. Black comes last, as it
vanishes on a dark background.

Heatmaps and densities use *viridis*, by van der Walt and Smith (2015): its lightness grows evenly from the least value to
the greatest, so equal steps of the data look like equal steps of color, a *perceptually uniform* map, and it stays in
order in grey and for color-blind eyes. A value takes one of its 256 colors, those of matplotlib's table, number
$\lfloor 256 (v - v_{min}) / (v_{max} - v_{min}) \rfloor$, the last for the greatest. `colors = "diverging"` takes
ColorBrewer's RdBu, by Harrower and Brewer (2003), for data around 0: dark blue for the most negative, white at 0, dark
red for the most positive, with its 11 colors joined by straight lines, and the same distance on both sides of 0. The
themes of Cemacs change the axes and the texts, never the colors of the data.

## Scenes, for a back-end

[plot.Scene] gives what a graph is made of, so that a program other than a browser can draw it: `{Width, Height,
Items, Dropped}`, its items in the order they are drawn, each a dictionary with a `Kind` and a `Role`:

| Kind | Fields |
|---|---|
| `"line"` | `Xs`, `Ys`, `Color`, `Width`, `Dash` (missing, or the lengths on and off) |
| `"area"` | `Xs`, `Ys` around the band, `Color`, `Opacity` |
| `"rect"` | `X`, `Y`, `W`, `H`, `Color`, `Opacity` |
| `"marks"` | `Xs`, `Ys`, the centers, `Shape`, `Size`, `Color` |
| `"cells"` | `Xs` and `Ys`, the edges of the columns and the rows, `Colors` row after row, missing for an empty cell |
| `"text"` | `X`, `Y` on the baseline, `Text`, `Size`, `Color`, `Anchor` (`"start"`, `"middle"` or `"end"`), `Angle` (0 or -90), `Width` |

Coordinates are in pixels from the top left corner. The items of the data have `Clip`, the rectangle `[x, y, width,
height]` of the plot they are cut to. A `Color` is `"#rrggbb"`, or `"ink"` and `"grid"` for the frame, the ticks and the
texts, which a back-end paints in the colors of its theme; [plot.Svg] paints them `#222222` and `#e6e6e6` on white. The
`Role` says what an item is: `"grid"`, `"data"`, `"frame"`, `"tick"`, `"xlabel"` and `"ylabel"` for the labels of the
ticks, `"factor"` for the power of ten or the offset of an axis, `"title"`, `"xtitle"`, `"ytitle"`, `"legend"` or
`"colorbar"`.

## Errors

Every mistake in a graph gives an `Err` of kind `"plot"` from [plot.Svg], [plot.Save] and [plot.Scene], which name the
layer and say what to do; making the graph never fails, so a graph is checked once, when it is drawn:

```cesia
plot.Svg(plot.Of([plot.Line([1, 2, 3], [1, 2]), plot.Points([1], [1], shape = "star")])) -->
plot.Svg(plot.Of([plot.Line([1, 10], [0, 5], label = "rate")], yscale = "log")) -->
```

The checks: the lengths of `x` and `y`, a value that is no number, no finite value at all, a log axis with a value at 0
or below, more than 200,000 points, a count of bins below 1 or edges that don't increase, a color, a shape, a dash, a
scale or a range written wrong, and a size too small for the plot.

## Speed

A program that doesn't use [std/plot] starts as fast as before: 2.8 ms for `io.Print(1)`. `use std/plot` loads its 2,000
lines in about 6.5 ms, and a first graph, from the start of the program to its SVG, takes 15 ms. Then [plot.Svg] takes,
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

## Limits

- SVG only, for now; PNG will come with a rasterizer chosen by measure.
- One font is measured, Noto Sans Medium; other fonts draw a little wider or narrower.
- The legend and the color bar sit right of the plot; bars stand upright; a graph holds one [plot.Bars].
- A line whose x goes back and forth keeps all its points; past 200,000 markers, use [plot.Density].
- No 3D, animation or zoom in this version.

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
- Masataka Okabe, Kei Ito. "Color Universal Design (CUD): How to make figures and presentations that are friendly to
  Colorblind people". J*Fly, 2002, revised 2008. <https://jfly.uni-koeln.de/color/>. The colors of the layers.
- Stéfan van der Walt, Nathaniel Smith. "matplotlib colormaps", the page of the colormaps they designed as matplotlib's
  default, with their talk at SciPy 2015. <https://bids.github.io/colormap/>. Viridis, from the table of matplotlib 3.11.
- Mark Harrower, Cynthia A. Brewer. "ColorBrewer.org: An Online Tool for Selecting Colour Schemes for Maps". *The
  Cartographic Journal* 40(1):27–37, 2003. <https://doi.org/10.1179/000870403235002042>. RdBu.
- J. E. Bresenham. "Algorithm for computer control of a digital plotter". *IBM Systems Journal* 4(1):25–30, 1965.
  <https://doi.org/10.1147/sj.41.0025>. The pixels of a line, in the test of M4.
- Microsoft and Adobe. *OpenType specification*: the tables cmap, hmtx and head.
  <https://learn.microsoft.com/typography/opentype/spec/>. How `tools/plot-font.ce` reads the widths of the font.

## Next

You can draw what you compute. The next chapter, [Numerical methods](numerical.md), finds the zeros and minima of
functions, solves differential equations and sparse systems, and computes integrals.
