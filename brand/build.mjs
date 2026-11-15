#!/usr/bin/env node
/**
 * Build the NCode logo kit: the {N} mark as SVG masters, and every PNG and ICO export.
 *
 *     node brand/build.mjs            writes each file that is missing or would change
 *     node brand/build.mjs --check    writes nothing; exits 1 when a file is missing or would change
 *
 * Builds every generated file under brand/ and template/NCodeGroup.png, the NuGet package icon a
 * project made from the template gets. brand/README.md says which file is for what. It needs Node.js
 * alone, the release .node-version names: no packages.
 *
 * The mark is drawn on a 64-unit grid from straight lines and circular arcs, so the SVG paths and the
 * PNG pixels come from the same geometry. Sizes from 16 to 48 pixels have their own pixel-fitted
 * geometry (FITTED), because a scaled-down master puts its strokes between pixels.
 *
 * A file that already holds what the run builds is kept: the same bytes, or, for a PNG, the same
 * pixels, and for an ICO the same entries, each stored the same way and holding the same pixels. So an
 * image another encoder wrote doesn't change while its picture stays the same.
 *
 * Options: --output <folder> writes the kit there instead of next to this file, and leaves
 * template/NCodeGroup.png alone; --check writes nothing and lists each file that is missing or would
 * change.
 */
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { deflateSync, inflateSync } from 'node:zlib';

// ---- Palette: one hue (225 degrees) at three lightnesses ---------------------------------------
const BLUE = '#0033CC'; // NCode Blue, hsl(225 100% 40%): the mark on light backgrounds, and the tile
const LIGHT = '#809FFF'; // NCode Blue Light, hsl(225 100% 75%): the mark on dark backgrounds
const NAVY = '#0A1F5C'; // NCode Navy, hsl(225 80% 20%): the dark tile and the dark cards
const WHITE = '#FFFFFF';
const BLACK = '#000000';

const INKS = { blue: BLUE, light: LIGHT, white: WHITE, black: BLACK }; // transparent
const TILES = { blue: [BLUE, WHITE], white: [WHITE, BLUE], dark: [NAVY, LIGHT] }; // fill, mark
const CARDS = { light: [WHITE, BLUE], dark: [NAVY, LIGHT], blue: [BLUE, WHITE] }; // fill, lockup

const GRID = 64.0; // the master's canvas
const RADIUS = 14.0 / 64.0; // corner radius of a rounded tile, as a fraction of its width
const TIGHT = 1.0; // mark across 7/8 of the canvas: icons shown small (favicon, NuGet, badges)
const REGULAR = 0.875; // app tiles and avatars shown in a rounded square
const SAFE = 0.8125; // inside the center circle of 80% diameter: circular crops, maskable icons

// The largest file each platform takes, in bytes.
const NUGET_LIMIT = 1024 * 1024; // 1 MB
const GITHUB_LIMIT = 1024 * 1024; // 1 MB
const GITLAB_LIMIT = 200 * 1024; // 200 KiB
const MYAPPS_LIMIT = 100 * 1000; // 100 KB

// ---- Numbers ---------------------------------------------------------------------------------------
/** Rounds to the nearest integer, and a tie to the even one. */
function roundHalfEven(x) {
  const f = Math.floor(x);
  const d = x - f; // exact for every double
  if (d < 0.5) return f;
  if (d > 0.5) return f + 1;
  return f % 2 === 0 ? f : f + 1;
}

/**
 * The number with `digits` decimals: the exact binary value rounded half to even. toFixed(100) is the exact decimal expansion of every value this file formats
 * (and rounds a tiny one to digits that round to 0 all the same); toFixed(digits) itself takes the
 * larger neighbor on a tie.
 */
function toFixedHalfEven(v, digits) {
  const negative = v < 0 || Object.is(v, -0);
  const [whole, fraction] = Math.abs(v).toFixed(100).split('.');
  const rest = fraction.slice(digits);
  let kept = whole + fraction.slice(0, digits);
  const half = '5'.padEnd(rest.length, '0');
  if (rest > half || (rest === half && Number(kept.at(-1)) % 2 === 1)) {
    kept = (BigInt(kept) + 1n).toString().padStart(kept.length, '0');
  }
  const split = kept.length - digits;
  return (negative ? '-' : '') + (digits ? `${kept.slice(0, split)}.${kept.slice(split)}` : kept);
}

function num(v, digits) {
  const s = toFixedHalfEven(v, digits).replace(/0+$/, '').replace(/\.+$/, '');
  return s === '' || s === '-0' ? '0' : s;
}

const DEG_TO_RAD = Math.PI / 180.0;
const RAD_TO_DEG = 180.0 / Math.PI;

/** a times b as the rounded product and its exact error (Dekker), so p + e is a * b exactly. */
function twoProduct(a, b) {
  const p = a * b;
  const split = (x) => {
    const c = 134217729 * x; // 2^27 + 1
    const hi = c - (c - x);
    return [hi, x - hi];
  };
  const [ah, al] = split(a);
  const [bh, bl] = split(b);
  return [p, ((ah * bh - p) + ah * bl + al * bh) + al * bl];
}

/** a + b as the rounded sum and its exact error, for |a| >= |b|. */
function fastTwoSum(a, b) {
  const x = a + b;
  return [x, b - (x - a)];
}

/** a + b as the rounded sum and its exact error. */
function twoSum(a, b) {
  const s = a + b;
  const bb = s - a;
  return [s, (a - (s - bb)) + (b - bb)];
}

// Double-double numbers, [hi, lo] with hi the double nearest hi + lo: about 106 bits.
function ddAdd([ah, al], [bh, bl]) {
  let [s, e] = twoSum(ah, bh);
  const [t, f] = twoSum(al, bl);
  e += t;
  [s, e] = fastTwoSum(s, e);
  e += f;
  return fastTwoSum(s, e);
}

function ddMul([ah, al], [bh, bl]) {
  const [p, e] = twoProduct(ah, bh);
  return fastTwoSum(p, e + (ah * bl + al * bh));
}

function ddDivide([ah, al], d) {
  const q = ah / d;
  const [p, e] = twoProduct(q, d);
  return fastTwoSum(q, (ah - p - e + al) / d);
}

// pi/2 in four parts, each of the first three 33 bits long, so a small multiple of each is exact.
const PI_2 = [1.57079632673412561417e+00, 6.07710050630396597660e-11, 2.02226624871116645580e-21, 8.47842766036889956997e-32];

/**
 * sin x and cos x as double-doubles: x less a multiple of pi/2, then the Taylor series of both to 106
 * bits. Their high parts are sin x and cos x correctly rounded.
 *
 * Math.sin and Math.cos can be a bit off in the last place, and differently from one V8 release to the
 * next; a last bit of an arc's points can move a pixel whose coverage is exactly one half. Correctly
 * rounded functions draw the same pixels on every platform and with every Node.js release.
 */
function sinCos(x) {
  const k = Math.round(x / (Math.PI / 2));
  let r = twoSum(x, -k * PI_2[0]);
  for (const part of PI_2.slice(1)) r = ddAdd(r, [-k * part, 0]);
  const r2 = ddMul(r, r);
  let term = r;
  let sin = r;
  for (let n = 1; n < 16; n++) {
    term = ddDivide(ddMul(term, r2), -(2 * n) * (2 * n + 1));
    sin = ddAdd(sin, term);
  }
  term = [1, 0];
  let cos = [1, 0];
  for (let n = 1; n < 16; n++) {
    term = ddDivide(ddMul(term, r2), -(2 * n - 1) * (2 * n));
    cos = ddAdd(cos, term);
  }
  const negative = ([hi, lo]) => [-hi, -lo];
  return [[sin, cos], [cos, negative(sin)], [negative(sin), negative(cos)], [negative(cos), sin]][((k % 4) + 4) % 4];
}

const sin = (x) => sinCos(x)[0][0];
const cos = (x) => sinCos(x)[1][0];

/** asin y correctly rounded: Math.asin's value with one Newton step taken in double-double. */
function asin(y) {
  const a = Math.asin(y);
  if (y === 0 || Math.abs(y) === 1) return a;
  const [s, c] = sinCos(a);
  return a - ddAdd(s, [-y, 0])[0] / c[0];
}

/** acos y correctly rounded, as asin. */
function acos(y) {
  const a = Math.acos(y);
  if (Math.abs(y) === 1) return a;
  const [s, c] = sinCos(a);
  return a + ddAdd(c, [-y, 0])[0] / s[0];
}

/**
 * The distance between two points, correctly rounded: scaled by a power of two, the squares summed in
 * extended precision, the square root corrected once.
 */
function dist(p, q) {
  const vec = [Math.abs(p[0] - q[0]), Math.abs(p[1] - q[1])];
  const max = Math.max(vec[0], vec[1]);
  if (!Number.isFinite(max) || max === 0) return max;
  let e = Math.floor(Math.log2(max)) + 1; // frexp's exponent: max * 2^-e in [0.5, 1)
  while (max * 2 ** -e >= 1) e++;
  while (max * 2 ** -e < 0.5) e--;
  const scale = 2 ** -e;
  let csum = 1.0;
  let frac1 = 0.0;
  let frac2 = 0.0;
  for (const v of vec) {
    const x = v * scale;
    const [hi, lo] = twoProduct(x, x);
    const [sum, err] = fastTwoSum(csum, hi);
    csum = sum;
    frac1 += lo;
    frac2 += err;
  }
  let h = Math.sqrt(csum - 1.0 + (frac1 + frac2));
  const [hi, lo] = twoProduct(-h, h);
  const [sum, err] = fastTwoSum(csum, hi);
  csum = sum;
  frac1 += lo;
  frac2 += err;
  const x = csum - 1.0 + (frac1 + frac2);
  h += x / (2.0 * h); // differential correction
  return h / scale;
}

// ---- Geometry: closed contours of lines, circular arcs and Bezier curves ------------------------
function onArc(center, r, angle) {
  const t = angle * DEG_TO_RAD;
  return [center[0] + r * cos(t), center[1] + r * sin(t)];
}

/**
 * One closed outline. Angles are in degrees with y pointing down, so a growing angle turns clockwise.
 *
 * Outlines run clockwise on screen, so that shapes which overlap add up to their union under the
 * non-zero fill rule, in an SVG path and in the rasterizer alike.
 *
 * Segments are ['L', [x, y]], ['A', [cx, cy], r, a0, a1] and ['C', p1, p2, p3].
 */
class Contour {
  constructor(start, segments = []) {
    this.start = start;
    this.segments = segments;
  }

  line(x, y) {
    const last = this.segments.length ? this.endOf(this.segments.at(-1)) : this.start;
    if (dist(last, [x, y]) > 1e-9) this.segments.push(['L', [x, y]]); // a hook without a straight end adds no line
    return this;
  }

  arc(cx, cy, r, a0, a1) {
    this.segments.push(['A', [cx, cy], r, a0, a1]);
    return this;
  }

  cubic(p1, p2, p3) {
    this.segments.push(['C', p1, p2, p3]);
    return this;
  }

  endOf(segment) {
    if (segment[0] === 'A') return onArc(segment[1], segment[2], segment[4]);
    return segment.at(-1);
  }

  reversed() {
    const points = [this.start, ...this.segments.map((s) => this.endOf(s))];
    const out = new Contour(points.at(-1));
    for (let i = this.segments.length - 1; i >= 0; i--) {
      const s = this.segments[i];
      if (s[0] === 'L') out.line(...points[i]);
      else if (s[0] === 'A') out.arc(...s[1], s[2], s[4], s[3]);
      else out.cubic(s[2], s[1], points[i]);
    }
    return out;
  }
}

class Shape {
  constructor(contours = []) {
    this.contours = contours;
  }

  add(other) {
    return new Shape([...this.contours, ...other.contours]);
  }

  /** Scaled about the origin, then moved. The scale is uniform, so arcs stay circular. */
  placed(scale = 1.0, dx = 0.0, dy = 0.0) {
    const p = (q) => [q[0] * scale + dx, q[1] * scale + dy];
    const out = new Shape();
    for (const c of this.contours) {
      const n = new Contour(p(c.start));
      for (const s of c.segments) {
        if (s[0] === 'L') n.line(...p(s[1]));
        else if (s[0] === 'A') n.arc(...p(s[1]), s[2] * scale, s[3], s[4]);
        else n.cubic(p(s[1]), p(s[2]), p(s[3]));
      }
      out.contours.push(n);
    }
    return out;
  }

  /** Flipped left to right about x = axisX, keeping each contour's winding direction. */
  mirrored(axisX) {
    const p = (q) => [2 * axisX - q[0], q[1]];
    const out = new Shape();
    for (const c of this.contours) {
      const n = new Contour(p(c.start));
      for (const s of c.segments) {
        if (s[0] === 'L') n.line(...p(s[1]));
        else if (s[0] === 'A') n.arc(...p(s[1]), s[2], 180 - s[3], 180 - s[4]);
        else n.cubic(p(s[1]), p(s[2]), p(s[3]));
      }
      out.contours.push(n.reversed());
    }
    return out;
  }

  /** SVG path data. */
  path(digits = 3) {
    const d = [];
    for (const c of this.contours) {
      let cur = c.start;
      d.push(`M${num(cur[0], digits)} ${num(cur[1], digits)}`);
      for (const s of c.segments) {
        if (s[0] === 'L') {
          const [x, y] = s[1];
          if (Math.abs(y - cur[1]) < 1e-9) d.push(`H${num(x, digits)}`);
          else if (Math.abs(x - cur[0]) < 1e-9) d.push(`V${num(y, digits)}`);
          else d.push(`L${num(x, digits)} ${num(y, digits)}`);
          cur = [x, y];
        } else if (s[0] === 'A') {
          const [, center, r, a0, a1] = s;
          cur = onArc(center, r, a1);
          const rr = num(r, digits);
          const large = Math.abs(a1 - a0) > 180 ? 1 : 0;
          const sweep = a1 > a0 ? 1 : 0;
          d.push(`A${rr} ${rr} 0 ${large} ${sweep} ${num(cur[0], digits)} ${num(cur[1], digits)}`);
        } else {
          d.push(`C${s.slice(1).map((q) => `${num(q[0], digits)} ${num(q[1], digits)}`).join(' ')}`);
          cur = s[3];
        }
      }
      d.push('Z');
    }
    return d.join('');
  }

  /** Each contour as a polygon that stays within the tolerance of its curves. */
  polygons(tolerance = 0.01) {
    const out = [];
    for (const c of this.contours) {
      const pts = [c.start];
      for (const s of c.segments) {
        if (s[0] === 'L') {
          pts.push(s[1]);
        } else if (s[0] === 'A') {
          const [, center, r, a0, a1] = s;
          const step = r > tolerance ? 2 * (acos(Math.max(-1.0, 1 - tolerance / r)) * RAD_TO_DEG) : 360;
          const n = Math.max(1, Math.ceil(Math.abs(a1 - a0) / step));
          for (let i = 1; i <= n; i++) pts.push(onArc(center, r, a0 + ((a1 - a0) * i) / n));
        } else {
          const p0 = pts.at(-1);
          const [, p1, p2, p3] = s;
          const length = dist(p0, p1) + dist(p1, p2) + dist(p2, p3);
          const n = Math.max(4, Math.ceil(Math.sqrt(length / tolerance)));
          for (let i = 1; i <= n; i++) {
            const t = i / n;
            const u = 1 - t;
            const at = (k) => u ** 3 * p0[k] + 3 * u * u * t * p1[k] + 3 * u * t * t * p2[k] + t ** 3 * p3[k];
            pts.push([at(0), at(1)]);
          }
        }
      }
      out.push(pts);
    }
    return out;
  }
}

/** The subset of SVG path data that Shape.path writes without arcs: M, L, H, V, C and Z. */
function parsePath(d) {
  const shape = new Shape();
  let contour = null;
  let cur = [0.0, 0.0];
  for (const [, cmd, args] of d.matchAll(/([MLHVCZ])([^MLHVCZ]*)/g)) {
    const v = [...args.matchAll(/-?\d*\.?\d+/g)].map((m) => Number(m[0]));
    if (cmd === 'M') {
      cur = [v[0], v[1]];
      contour = new Contour(cur);
      shape.contours.push(contour);
    } else if (cmd === 'L') {
      cur = [v[0], v[1]];
      contour.line(...cur);
    } else if (cmd === 'H') {
      cur = [v[0], cur[1]];
      contour.line(...cur);
    } else if (cmd === 'V') {
      cur = [cur[0], v[0]];
      contour.line(...cur);
    } else if (cmd === 'C') {
      contour.cubic([v[0], v[1]], [v[2], v[3]], [v[4], v[5]]);
      cur = [v[4], v[5]];
    }
  }
  return shape;
}

function rectangle(x, y, w, h) {
  return new Shape([new Contour([x, y]).line(x + w, y).line(x + w, y + h).line(x, y + h)]);
}

function roundedRectangle(x, y, w, h, r) {
  const c = new Contour([x + r, y]);
  c.line(x + w - r, y).arc(x + w - r, y + r, r, 270, 360);
  c.line(x + w, y + h - r).arc(x + w - r, y + h - r, r, 0, 90);
  c.line(x + r, y + h).arc(x + r, y + h - r, r, 90, 180);
  c.line(x, y + r).arc(x + r, y + r, r, 180, 270);
  return new Shape([c]);
}

// ---- Rasterizer: exact area coverage, by signed-area accumulation ---------------------------------
/** Sutherland-Hodgman clip of a polygon to the canvas. */
function clip(points, w, h) {
  const cut = (pts, inside, cross) => {
    const out = [];
    let prev = pts.length ? pts.at(-1) : null;
    for (const cur of pts) {
      if (inside(cur)) {
        if (!inside(prev)) out.push(cross(prev, cur));
        out.push(cur);
      } else if (inside(prev)) {
        out.push(cross(prev, cur));
      }
      prev = cur;
    }
    return out;
  };
  const atX = (x) => (a, b) => [x, a[1] + ((b[1] - a[1]) * (x - a[0])) / (b[0] - a[0])];
  const atY = (y) => (a, b) => [a[0] + ((b[0] - a[0]) * (y - a[1])) / (b[1] - a[1]), y];
  points = cut(points, (q) => q[0] >= 0, atX(0.0));
  points = cut(points, (q) => q[0] <= w, atX(w));
  points = cut(points, (q) => q[1] >= 0, atY(0.0));
  return cut(points, (q) => q[1] <= h, atY(h));
}

/**
 * The fraction of each pixel the shape covers, 0 to 1 (non-zero winding), row by row.
 *
 * Every edge adds its signed area to the pixels it crosses and its full height to the pixel after
 * them; a running sum along each row then gives the coverage. An edge on a pixel boundary therefore
 * gives exactly 0 or 1, which is what keeps the pixel-fitted sizes sharp.
 *
 * Each row of the accumulator is two pixels wider than the image, and an index below 0 counts from the
 * row's end.
 */
function coverage(shape, w, h) {
  const W = w + 2;
  const acc = new Float64Array(h * W);
  const at = (i) => (i < 0 ? i + W : i);
  for (const raw of shape.polygons()) {
    const polygon = clip(raw, w, h);
    for (let i = 0; i < polygon.length; i++) {
      let [x0, y0] = polygon[i];
      let [x1, y1] = polygon[(i + 1) % polygon.length];
      if (y0 === y1) continue;
      let sign = 1.0;
      if (y0 > y1) [x0, y0, x1, y1, sign] = [x1, y1, x0, y0, -1.0];
      const slope = (x1 - x0) / (y1 - y0);
      let x = x0;
      const yEnd = Math.min(h, Math.ceil(y1));
      for (let y = Math.max(0, Math.floor(y0)); y < yEnd; y++) {
        const dy = Math.min(y + 1, y1) - Math.max(y, y0);
        if (dy <= 0) continue;
        const xNext = x + slope * dy;
        const d = dy * sign;
        const [xa, xb] = x < xNext ? [x, xNext] : [xNext, x];
        const ia = Math.floor(xa);
        const ib = Math.ceil(xb);
        const row = y * W;
        if (ib <= ia + 1) {
          // the edge stays inside one pixel column
          const mid = 0.5 * (x + xNext) - ia;
          acc[row + at(ia)] += d * (1 - mid);
          acc[row + at(ia + 1)] += d * mid;
        } else {
          // it crosses several: a trapezoid per column
          const s = 1.0 / (xb - xa);
          const fa = xa - ia;
          const first = 0.5 * s * ((1 - fa) * (1 - fa));
          const fb = xb - ib + 1.0;
          const last = 0.5 * s * fb * fb;
          acc[row + at(ia)] += d * first;
          if (ib === ia + 2) {
            acc[row + at(ia + 1)] += d * (1.0 - first - last);
          } else {
            const second = s * (1.5 - fa);
            acc[row + at(ia + 1)] += d * (second - first);
            const ds = d * s;
            const from = Math.max(0, at(ia + 2));
            const to = Math.min(W, at(ib - 1));
            for (let k = from; k < to; k++) acc[row + k] += ds;
            acc[row + at(ib - 1)] += d * (1.0 - second - (ib - ia - 3) * s - last);
          }
          acc[row + at(ib)] += d * last;
        }
        x = xNext;
      }
    }
  }
  const cover = new Float64Array(h * w);
  for (let y = 0; y < h; y++) {
    let sum = 0.0;
    for (let k = 0; k < w; k++) {
      sum += acc[y * W + k];
      cover[y * w + k] = Math.min(Math.max(Math.abs(sum), 0.0), 1.0);
    }
  }
  return cover;
}

function rgb(color) {
  return [1, 3, 5].map((i) => parseInt(color.slice(i, i + 2), 16));
}

/** An RGBA image in floats. Shapes are composited source-over in sRGB, as browsers composite SVG. */
class Canvas {
  constructor(w, h, background = null) {
    this.w = w;
    this.h = h;
    this.color = new Float64Array(w * h * 3);
    this.alpha = new Float64Array(w * h);
    if (background) {
      const c = rgb(background);
      for (let i = 0; i < w * h; i++) {
        this.color.set(c, i * 3);
        this.alpha[i] = 1.0;
      }
    }
  }

  fill(shape, color) {
    const cover = coverage(shape, this.w, this.h);
    const c = rgb(color);
    for (let i = 0; i < cover.length; i++) {
      const under = this.alpha[i] * (1 - cover[i]);
      const alpha = cover[i] + under;
      for (let k = 0; k < 3; k++) {
        const mixed = c[k] * cover[i] + this.color[i * 3 + k] * under;
        this.color[i * 3 + k] = alpha > 0 ? mixed / alpha : 0;
      }
      this.alpha[i] = alpha;
    }
    return this;
  }

  /** The image in 8-bit RGBA, { width, height, data }; a fully transparent pixel's color is 0. */
  image() {
    const data = new Uint8Array(this.w * this.h * 4);
    for (let i = 0; i < this.w * this.h; i++) {
      const alpha = roundHalfEven(this.alpha[i] * 255);
      data[i * 4 + 3] = alpha;
      if (alpha === 0) continue;
      for (let k = 0; k < 3; k++) data[i * 4 + k] = Math.min(Math.max(roundHalfEven(this.color[i * 3 + k]), 0), 255);
    }
    return { width: this.w, height: this.h, data };
  }
}

// ---- The mark ------------------------------------------------------------------------------------
/**
 * One drawing of the mark, in the units of a square canvas `size` wide.
 *
 * stroke: the braces' stroke. stem: the N's two stems. diagonal: the N's diagonal, measured along the
 * horizontal. brace: x of the left brace's beak tip and of its hook ends. beakRadius: center-line radius
 * of the two arcs into the beak. hookRadius: center-line radius of the two hooks. braceY: top and bottom
 * of the braces. nX, nY: left and right, top and bottom of the N. taper: how much thinner than the stroke
 * the beak's tip is. beakY: the beak's center, when it isn't the middle of the brace. staircase: the
 * diagonal as steps (columns, rows per step).
 */
function spec(fields) {
  return Object.freeze({ taper: 0.0, beakY: null, staircase: null, ...fields });
}

// The master. Braces: a stroke of 4. N: stems of 5, 24 wide and 32 tall. 4 units clear left and
// right, 8 above and below.
const MASTER = spec({ size: 64, stroke: 4, stem: 5, diagonal: 5.5, brace: [4, 16], beakRadius: 6, hookRadius: 5,
  braceY: [8, 56], nX: [20, 44], nY: [16, 48], taper: 2 });

// The same drawing with every stem on whole pixels, for the sizes where half a pixel shows.
const FITTED = {
  // 16: one-pixel strokes, the beak moved up half a pixel onto a row, the diagonal as a staircase.
  16: spec({ size: 16, stroke: 1, stem: 1, diagonal: 1, brace: [1, 4], beakRadius: 1.5, hookRadius: 1,
    braceY: [2, 14], nX: [5, 11], nY: [4, 12], beakY: 7.5, staircase: [4, 2] }),
  20: spec({ size: 20, stroke: 2, stem: 2, diagonal: 2, brace: [1, 5], beakRadius: 2, hookRadius: 2,
    braceY: [2, 18], nX: [6, 14], nY: [5, 15] }),
  24: spec({ size: 24, stroke: 2, stem: 2, diagonal: 2, brace: [1, 5], beakRadius: 2, hookRadius: 2,
    braceY: [3, 21], nX: [7, 17], nY: [6, 18] }),
  32: spec({ size: 32, stroke: 2, stem: 3, diagonal: 3, brace: [2, 8], beakRadius: 3, hookRadius: 2.5,
    braceY: [4, 28], nX: [10, 22], nY: [8, 24] }),
  40: spec({ size: 40, stroke: 3, stem: 4, diagonal: 4, brace: [2, 9], beakRadius: 3.5, hookRadius: 3.5,
    braceY: [5, 35], nX: [12, 28], nY: [10, 30], taper: 1 }),
  48: spec({ size: 48, stroke: 3, stem: 4, diagonal: 4.25, brace: [3, 12], beakRadius: 4.5, hookRadius: 3.5,
    braceY: [6, 42], nX: [15, 33], nY: [12, 36], taper: 1 }),
};

/**
 * The outline of a constant-width stroke: hook, stem, beak, stem, hook.
 *
 * The hooks and the arcs into the beak are quarter circles. The two arcs into the beak cross on the
 * inner side, which leaves the notch a curly brace has there; `taper` moves their centers together,
 * so the beak narrows to a tip `stroke - taper` high.
 */
function leftBrace(s) {
  const half = s.stroke / 2;
  const [top, bottom] = s.braceY;
  const [tipX, hookX] = s.brace;
  const stemX = tipX + s.beakRadius; // the stem's center line
  const beakY = s.beakY === null ? (top + bottom) / 2 : s.beakY;
  const reach = s.beakRadius - s.taper / 2; // from an arc's center to the beak's center line
  const hookTop = [stemX + s.hookRadius, top + half + s.hookRadius];
  const hookBottom = [stemX + s.hookRadius, bottom - half - s.hookRadius];
  const beakUpper = [tipX, beakY - reach];
  const beakLower = [tipX, beakY + reach];
  const [hookOut, hookIn] = [s.hookRadius + half, s.hookRadius - half];
  const [beakOut, beakIn] = [s.beakRadius + half, s.beakRadius - half];
  const notch = asin(reach / beakOut) * RAD_TO_DEG; // where the outer beak arcs cross, seen from a center
  const tipHalf = (s.stroke - s.taper) / 2;

  const c = new Contour([hookX, top]);
  c.line(hookTop[0], top).arc(...hookTop, hookOut, 270, 180); // over the top hook
  c.line(stemX - half, beakUpper[1]).arc(...beakUpper, beakIn, 0, 90); // down the stem, into the beak
  c.line(tipX, beakY + tipHalf).arc(...beakLower, beakIn, 270, 360); // the tip, and out of the beak
  c.line(stemX - half, hookBottom[1]).arc(...hookBottom, hookOut, 180, 90);
  c.line(hookX, bottom).line(hookX, bottom - s.stroke); // the bottom hook's end
  c.line(hookBottom[0], bottom - s.stroke).arc(...hookBottom, hookIn, 90, 180);
  c.line(stemX + half, beakLower[1]).arc(...beakLower, beakOut, 0, -notch); // up into the notch
  c.arc(...beakUpper, beakOut, notch, 0); // and out of it
  c.line(stemX + half, hookTop[1]).arc(...hookTop, hookIn, 180, 270);
  c.line(hookX, top + s.stroke);
  return new Shape([c.reversed()]); // clockwise, as every outline here is
}

function letterN(s) {
  const [[x0, x1], [top, bottom]] = [s.nX, s.nY];
  if (s.staircase) {
    // stems, with the diagonal as whole-pixel steps
    const [columns, rows] = s.staircase;
    let shape = rectangle(x0, top, s.stem, bottom - top).add(rectangle(x1 - s.stem, top, s.stem, bottom - top));
    for (let i = 0; i < columns; i++) shape = shape.add(rectangle(x0 + s.stem + i, top + i * rows, 1, rows));
    return shape;
  }
  const run = x1 - s.diagonal - x0; // the diagonal's edges run from corner to corner
  const rise = bottom - top;
  const joinsRight = top + (rise * (x1 - s.stem - x0 - s.diagonal)) / run;
  const joinsLeft = top + (rise * s.stem) / run;
  const c = new Contour([x0, top]);
  c.line(x0 + s.diagonal, top).line(x1 - s.stem, joinsRight).line(x1 - s.stem, top).line(x1, top);
  c.line(x1, bottom).line(x1 - s.diagonal, bottom).line(x0 + s.stem, joinsLeft);
  c.line(x0 + s.stem, bottom).line(x0, bottom);
  return new Shape([c]);
}

function mark(s = MASTER) {
  const brace = leftBrace(s);
  return brace.add(letterN(s)).add(brace.mirrored(s.size / 2));
}

/** The mark in the pixels of a size-by-size image: fitted where there is a fitted drawing. */
function markFor(size, fit = TIGHT) {
  if (fit === TIGHT && size in FITTED) return mark(FITTED[size]);
  return mark().placed((size / GRID) * fit, (size * (1 - fit)) / 2, (size * (1 - fit)) / 2);
}

// ---- The wordmark --------------------------------------------------------------------------------
// "NCode" set in Inter Display Medium and converted to outlines, so no file needs the font. The font:
// InterDisplay-Medium.otf, "Version 4.000;git-a52131595", copyright 2016 The Inter Project Authors, under
// the SIL Open Font License 1.1; the file's SHA-256, as Debian's fonts-inter 4.0+ds-1 ships it, is
// cf438d4cd4979fda59150c773af3381d5b18627826672234846722bb6d06b86c. The outlines are its glyphs for N, C,
// o, d and e at the font's own advances (it kerns none of these pairs), scaled so the capitals are as tall
// as the mark's N, 32 units, which makes the stems about as heavy too. They stand on the N's line
// (y = 48) and start 72 units from the lockup's left edge.
const WORDMARK = parsePath(
  'M74.92 48H79.69V30.69C79.69 29.27 79.67 26.5 79.52 22.74C81.64 26.39 83.38 29.29 84.28 30.71L95.22 48' +
  'H100.54V16H95.75V35.05C95.75 36.21 95.8 38.94 95.88 41.26C94.59 38.98 93.18 36.55 92.42 35.35L80.2 16' +
  'H74.92ZM120.11 48.52C127.09 48.52 132.5 44.2 133.59 37.39H128.76C127.75 41.73 124.49 44.16 120.15 44.16' +
  'C113.84 44.16 109.97 39.26 109.97 32.02C109.97 24.74 113.84 19.84 120.15 19.84' +
  'C124.51 19.84 127.8 22.29 128.74 26.65H133.59C132.48 19.82 127.09 15.48 120.11 15.48' +
  'C111.26 15.48 105.18 22.16 105.18 32.02C105.18 41.81 111.28 48.52 120.11 48.52ZM147.58 48.52' +
  'C154.06 48.52 158.42 43.68 158.42 36.7C158.42 29.68 154.06 24.81 147.58 24.81' +
  'C141.09 24.81 136.71 29.68 136.71 36.7C136.71 43.68 141.09 48.52 147.58 48.52ZM147.58 44.61' +
  'C143.69 44.61 141.3 41.54 141.3 36.7C141.3 31.83 143.71 28.71 147.58 28.71' +
  'C151.44 28.71 153.85 31.83 153.85 36.7C153.85 41.51 151.46 44.61 147.58 44.61ZM171.16 48.45' +
  'C174.12 48.45 176.66 47.18 178.18 44.54H178.22V48H182.67V16H178.14V28.61H178.09' +
  'C176.63 26.09 174.08 24.87 171.14 24.87C165.27 24.87 161.32 29.66 161.32 36.66' +
  'C161.32 43.68 165.25 48.45 171.16 48.45ZM172.08 44.54C168.43 44.54 165.92 41.77 165.92 36.66' +
  'C165.92 31.53 168.43 28.76 172.08 28.76C175.95 28.76 178.44 31.89 178.44 36.66' +
  'C178.44 41.43 175.95 44.54 172.08 44.54ZM197.47 48.52C202.6 48.52 206.64 45.49 207.47 41.11H203.11' +
  'C202.47 43.25 200.49 44.74 197.53 44.74C193.56 44.74 191.28 41.97 191.13 37.88H207.82V36.66' +
  'C207.82 29.66 203.65 24.81 197.23 24.81C191.04 24.81 186.66 29.79 186.66 36.7' +
  'C186.66 43.55 190.74 48.52 197.47 48.52ZM191.17 34.45C191.56 30.84 193.86 28.59 197.27 28.59' +
  'C200.71 28.59 203.03 30.84 203.39 34.45Z',
);
const LOCKUP_WIDTH = 212.0; // the mark's 64, 8 clear, the wordmark, and 4 clear as on the left

function lockup(scale = 1.0, dx = 0.0, dy = 0.0) {
  return [mark().placed(scale, dx, dy), WORDMARK.placed(scale, dx, dy)];
}

// ---- Drawings ------------------------------------------------------------------------------------
function drawMark(size, ink, fit = TIGHT) {
  return new Canvas(size, size).fill(markFor(size, fit), ink).image();
}

/** corners: 'rounded' leaves the corners transparent; 'square' fills the whole image. */
function drawTile(size, tile, corners, fit) {
  const [fill, ink] = TILES[tile];
  const canvas = corners === 'square'
    ? new Canvas(size, size, fill)
    : new Canvas(size, size).fill(roundedRectangle(0, 0, size, size, RADIUS * size), fill);
  return canvas.fill(markFor(size, fit), ink).image();
}

function drawLockup(height, ink) {
  const scale = height / GRID;
  const [symbol, word] = lockup(scale);
  return new Canvas(roundHalfEven(LOCKUP_WIDTH * scale), height).fill(symbol, ink).fill(word, ink).image();
}

/** The lockup centered on a solid card, half the card wide at most. */
function drawCard(w, h, card) {
  const [fill, ink] = CARDS[card];
  const scale = Math.floor(Math.min((0.5 * w) / LOCKUP_WIDTH, (0.4 * h) / GRID) * 4) / 4;
  const dx = roundHalfEven((w - LOCKUP_WIDTH * scale) / 2);
  const dy = roundHalfEven((h - GRID * scale) / 2);
  const [symbol, word] = lockup(scale, dx, dy);
  return new Canvas(w, h, fill).fill(symbol, ink).fill(word, ink).image();
}

// ---- Writers -------------------------------------------------------------------------------------
function svg(w, h, body, title = 'NCode') {
  const size = `width="${num(w, 3)}" height="${num(h, 3)}" viewBox="0 0 ${num(w, 3)} ${num(h, 3)}"`;
  return `<svg xmlns="http://www.w3.org/2000/svg" ${size} role="img" aria-label="${title}">` +
    `<title>${title}</title>${body}</svg>\n`;
}

/** Blue, or light blue when the viewer's system or browser asks for a dark scheme. */
function autoStyle(selector = 'path') {
  return `<style>${selector}{fill:${BLUE}}@media (prefers-color-scheme:dark){${selector}{fill:${LIGHT}}}</style>`;
}

/** Percent-encodes every character but letters, digits and _ . - ~. */
function quote(s) {
  return encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
}

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(bytes) {
  let c = 0xffffffff;
  for (const b of bytes) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, 'latin1');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, crc]);
}

/** One PNG filter applied to a row: the filtered bytes, given the row above (zeros for the first). */
function filterRow(type, raw, prior, bpp) {
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) {
    const a = i >= bpp ? raw[i - bpp] : 0;
    const b = prior[i];
    const c = i >= bpp ? prior[i - bpp] : 0;
    let predictor = 0;
    if (type === 1) predictor = a;
    else if (type === 2) predictor = b;
    else if (type === 3) predictor = (a + b) >> 1;
    else if (type === 4) predictor = paeth(a, b, c);
    out[i] = (raw[i] - predictor) & 0xff;
  }
  return out;
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

/**
 * The image data of a PNG: each row behind its filter byte. With `bpp` set, each row takes the filter
 * whose bytes, read as signed, sum to the least in absolute value; without, filter 0.
 */
function filtered(rows, stride, bpp) {
  const out = Buffer.alloc(rows.length * (stride + 1));
  let prior = new Uint8Array(stride);
  rows.forEach((raw, y) => {
    let best = raw;
    let bestType = 0;
    if (bpp) {
      let bestSum = Infinity;
      for (let type = 0; type < 5; type++) {
        const candidate = type ? filterRow(type, raw, prior, bpp) : raw;
        let sum = 0;
        for (const v of candidate) sum += v < 128 ? v : 256 - v;
        if (sum < bestSum) [best, bestType, bestSum] = [candidate, type, sum];
      }
    }
    out[y * (stride + 1)] = bestType;
    out.set(best, y * (stride + 1) + 1);
    prior = raw;
  });
  return out;
}

function ihdr(w, h, depth, colorType) {
  const data = Buffer.alloc(13);
  data.writeUInt32BE(w, 0);
  data.writeUInt32BE(h, 4);
  data.set([depth, colorType, 0, 0, 0], 8);
  return chunk('IHDR', data);
}

function png(w, h, depth, colorType, extra, idat) {
  return Buffer.concat([PNG_SIGNATURE, ihdr(w, h, depth, colorType), ...extra,
    chunk('IDAT', deflateSync(idat, { level: 9, memLevel: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

/** A truecolor PNG: RGB (color type 2) or, with alpha, RGBA (6). */
function truecolorPng(image, withAlpha) {
  const { width: w, height: h, data } = image;
  const channels = withAlpha ? 4 : 3;
  const rows = [];
  for (let y = 0; y < h; y++) {
    const row = new Uint8Array(w * channels);
    for (let x = 0; x < w; x++) {
      for (let k = 0; k < channels; k++) row[x * channels + k] = data[(y * w + x) * 4 + k];
    }
    rows.push(row);
  }
  return png(w, h, 8, withAlpha ? 6 : 2, [], filtered(rows, w * channels, channels));
}

/**
 * The smallest PNG this file writes without changing a pixel: a palette when 256 colors are enough,
 * least opaque first so the transparency chunk holds only the translucent entries, at the fewest bits
 * per pixel that hold it; else RGB when every pixel is opaque, else RGBA.
 */
function pngBytes(image) {
  const { width: w, height: h, data } = image;
  const keys = new Uint32Array(w * h); // alpha, red, green, blue: sorting the keys sorts least opaque first
  const colors = new Map();
  let opaque = true;
  for (let i = 0; i < w * h; i++) {
    const a = data[i * 4 + 3];
    keys[i] = ((a << 24) | (data[i * 4] << 16) | (data[i * 4 + 1] << 8) | data[i * 4 + 2]) >>> 0;
    if (colors.size <= 256) colors.set(keys[i], 0);
    if (a !== 255) opaque = false;
  }
  let out;
  if (colors.size <= 256) {
    const palette = [...colors.keys()].sort((x, y) => x - y);
    palette.forEach((key, rank) => colors.set(key, rank));
    const depth = palette.length <= 2 ? 1 : palette.length <= 4 ? 2 : palette.length <= 16 ? 4 : 8;
    const stride = Math.ceil((w * depth) / 8);
    const rows = [];
    for (let y = 0; y < h; y++) {
      const row = new Uint8Array(stride);
      for (let x = 0; x < w; x++) {
        const bit = x * depth;
        row[bit >> 3] |= colors.get(keys[y * w + x]) << (8 - depth - (bit & 7));
      }
      rows.push(row);
    }
    const plte = Buffer.alloc(palette.length * 3);
    palette.forEach((key, i) => plte.set([(key >>> 16) & 0xff, (key >>> 8) & 0xff, key & 0xff], i * 3));
    const alphas = palette.map((key) => key >>> 24).filter((a) => a < 255);
    const extra = [chunk('PLTE', plte)];
    if (alphas.length) extra.push(chunk('tRNS', Buffer.from(alphas)));
    out = png(w, h, depth, 3, extra, filtered(rows, stride, 0));
  } else {
    out = truecolorPng(image, !opaque);
  }
  if (!sameImage(decodePng(out), image)) throw new Error("the PNG that was written doesn't decode to the image that was drawn");
  return out;
}

/** The RGBA pixels of a non-interlaced PNG of 1 to 8 bits per sample, { width, height, data }. */
function decodePng(buf) {
  if (buf.length < 8 || !PNG_SIGNATURE.equals(buf.subarray(0, 8))) throw new Error('not a PNG');
  let header = null;
  let palette = null;
  let transparency = null;
  const idat = [];
  for (let at = 8; at + 8 <= buf.length;) {
    const length = buf.readUInt32BE(at);
    const type = buf.toString('latin1', at + 4, at + 8);
    const data = buf.subarray(at + 8, at + 8 + length);
    if (data.length !== length || buf.length < at + 12 + length) throw new Error(`the PNG's ${type} chunk is cut off`);
    if (crc32(buf.subarray(at + 4, at + 8 + length)) !== buf.readUInt32BE(at + 8 + length)) {
      throw new Error(`the PNG's ${type} chunk fails its CRC`);
    }
    at += 12 + length;
    if (type === 'IHDR') {
      header = { w: data.readUInt32BE(0), h: data.readUInt32BE(4), depth: data[8], colorType: data[9], interlace: data[12] };
    } else if (type === 'PLTE') palette = data;
    else if (type === 'tRNS') transparency = data;
    else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
  }
  if (!header) throw new Error('the PNG has no IHDR chunk');
  const { w, h, depth, colorType, interlace } = header;
  if (interlace) throw new Error('interlaced PNGs are not supported');
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[colorType];
  if (!channels) throw new Error(`PNG color type ${colorType} is not supported`);
  if (![1, 2, 4, 8].includes(depth) || (channels > 1 && depth !== 8) || (colorType === 3 && !palette)) {
    throw new Error(`PNG color type ${colorType} at ${depth} bits is not supported`);
  }
  const bpp = Math.max(1, (channels * depth) >> 3);
  const stride = Math.ceil((w * channels * depth) / 8);
  const raw = inflateSync(Buffer.concat(idat));
  if (raw.length < h * (stride + 1)) throw new Error("the PNG's image data is cut off");
  const pixels = new Uint8Array(h * stride);
  let prior = new Uint8Array(stride);
  for (let y = 0; y < h; y++) {
    const type = raw[y * (stride + 1)];
    if (type > 4) throw new Error(`PNG filter type ${type} is not one of the five`);
    const row = pixels.subarray(y * stride, (y + 1) * stride);
    row.set(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? row[i - bpp] : 0;
      const b = prior[i];
      const c = i >= bpp ? prior[i - bpp] : 0;
      if (type === 1) row[i] += a;
      else if (type === 2) row[i] += b;
      else if (type === 3) row[i] += (a + b) >> 1;
      else if (type === 4) row[i] += paeth(a, b, c);
    }
    prior = row;
  }
  const data = new Uint8Array(w * h * 4);
  const sample = (y, x) => {
    // a sample below 8 bits, of a grayscale or palette image
    const bit = x * depth;
    return (pixels[y * stride + (bit >> 3)] >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
  };
  const key = (i) => (transparency && transparency.length >= 2 * (i + 1) ? transparency.readUInt16BE(2 * i) : -1);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const o = (y * w + x) * 4;
      const p = y * stride + x * bpp;
      if (colorType === 0) {
        const v = depth === 8 ? pixels[p] : sample(y, x);
        const gray = Math.round((v * 255) / ((1 << depth) - 1));
        data.set([gray, gray, gray, v === key(0) ? 0 : 255], o);
      } else if (colorType === 3) {
        const index = depth === 8 ? pixels[p] : sample(y, x);
        if (3 * index + 3 > palette.length) throw new Error("a PNG pixel names a color past the palette's end");
        const alpha = transparency && index < transparency.length ? transparency[index] : 255;
        data.set([palette[3 * index], palette[3 * index + 1], palette[3 * index + 2], alpha], o);
      } else if (colorType === 2) {
        const [r, g, b] = pixels.subarray(p, p + 3);
        data.set([r, g, b, r === key(0) && g === key(1) && b === key(2) ? 0 : 255], o);
      } else if (colorType === 4) {
        data.set([pixels[p], pixels[p], pixels[p], pixels[p + 1]], o);
      } else {
        data.set(pixels.subarray(p, p + 4), o);
      }
    }
  }
  return { width: w, height: h, data };
}

function sameImage(a, b) {
  return a.width === b.width && a.height === b.height && Buffer.from(a.data).equals(Buffer.from(b.data));
}

/** A 32-bit bitmap entry of an ICO: the header, BGRA rows bottom row first, then the 1-bit mask. */
function bitmapEntry(image) {
  const { width: w, height: h, data } = image;
  const rowBytes = Math.floor((w + 31) / 32) * 4; // the 1-bit mask, padded to 32 bits
  const color = Buffer.alloc(w * h * 4);
  const mask = Buffer.alloc(rowBytes * h);
  for (let row = 0; row < h; row++) {
    const y = h - 1 - row; // bottom row first
    for (let x = 0; x < w; x++) {
      const [r, g, b, a] = data.subarray((y * w + x) * 4, (y * w + x) * 4 + 4);
      color.set([b, g, r, a], (row * w + x) * 4);
      if (a === 0) mask[row * rowBytes + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  const header = Buffer.alloc(40);
  header.writeUInt32LE(40, 0);
  header.writeInt32LE(w, 4);
  header.writeInt32LE(h * 2, 8);
  header.writeUInt16LE(1, 12);
  header.writeUInt16LE(32, 14);
  header.writeUInt32LE(0, 16);
  header.writeUInt32LE(color.length + mask.length, 20);
  return Buffer.concat([header, color, mask]);
}

/**
 * An ICO holding the images. Entries narrower than `bitmapsBelow` are stored as 32-bit bitmaps, which
 * every Windows API reads; the others as PNG, which browsers and Windows Vista and later read.
 */
function icoBytes(images, bitmapsBelow = 0) {
  const entries = images.map((image) => ({
    w: image.width,
    h: image.height,
    data: image.width < bitmapsBelow ? bitmapEntry(image) : truecolorPng(image, true), // RGBA: Windows wants 32 bits here
  }));
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(entries.length, 4);
  let offset = header.length + 16 * entries.length;
  const directory = entries.map(({ w, h, data }) => {
    const d = Buffer.alloc(16);
    d.set([w % 256, h % 256, 0, 0], 0);
    d.writeUInt16LE(1, 4);
    d.writeUInt16LE(32, 6);
    d.writeUInt32LE(data.length, 8);
    d.writeUInt32LE(offset, 12);
    offset += data.length;
    return d;
  });
  const icon = Buffer.concat([header, ...directory, ...entries.map((e) => e.data)]);
  const decoded = decodeIco(icon); // read each entry back, as pngBytes does
  images.forEach((image, i) => {
    if (!sameImage(decoded[i].image, image)) {
      throw new Error(`the icon's ${image.width}-pixel entry doesn't decode to the image that was drawn`);
    }
  });
  return icon;
}

/**
 * The entries of an ICO, in order: { png, image } for each, with `png` saying how it is stored. A
 * bitmap entry takes its alpha from its 32-bit pixels and must have its mask set exactly where the
 * alpha is 0.
 */
function decodeIco(buf) {
  if (buf.length < 6 || buf.readUInt16LE(0) !== 0 || buf.readUInt16LE(2) !== 1) throw new Error('not an ICO');
  const count = buf.readUInt16LE(4);
  const entries = [];
  for (let i = 0; i < count; i++) {
    const d = 6 + 16 * i;
    const size = buf.readUInt32LE(d + 8);
    const offset = buf.readUInt32LE(d + 12);
    const data = buf.subarray(offset, offset + size);
    if (data.length !== size) throw new Error(`the ICO's entry ${i + 1} is cut off`);
    if (data.length >= 8 && PNG_SIGNATURE.equals(data.subarray(0, 8))) {
      entries.push({ png: true, image: decodePng(Buffer.from(data)) });
      continue;
    }
    const w = data.readInt32LE(4);
    const h = data.readInt32LE(8) / 2;
    if (data.readUInt32LE(0) !== 40 || data.readUInt16LE(14) !== 32 || data.readUInt32LE(16) !== 0) {
      throw new Error(`the ICO's entry ${i + 1} is not an uncompressed 32-bit bitmap`);
    }
    const rowBytes = Math.floor((w + 31) / 32) * 4;
    if (data.length < 40 + w * h * 4 + rowBytes * h) throw new Error(`the ICO's entry ${i + 1} is cut off`);
    const pixels = new Uint8Array(w * h * 4);
    for (let row = 0; row < h; row++) {
      const y = h - 1 - row;
      for (let x = 0; x < w; x++) {
        const at = 40 + (row * w + x) * 4;
        const alpha = data[at + 3];
        const masked = (data[40 + w * h * 4 + row * rowBytes + (x >> 3)] & (0x80 >> (x & 7))) !== 0;
        if (masked !== (alpha === 0)) throw new Error(`the ICO's entry ${i + 1} has a mask that doesn't match its alpha`);
        pixels.set([data[at + 2], data[at + 1], data[at], alpha], (y * w + x) * 4);
      }
    }
    entries.push({ png: false, image: { width: w, height: h, data: pixels } });
  }
  return entries;
}

// ---- The kit -------------------------------------------------------------------------------------
class Kit {
  constructor() {
    /** Each file's bytes, and what an existing file must decode to for the run to keep it. */
    this.files = new Map();
  }

  text(name, content) {
    this.files.set(name, { data: Buffer.from(content, 'utf8') });
  }

  png(name, image, { limit = null, opaque = false } = {}) {
    const data = pngBytes(image);
    if (limit !== null && data.length > limit) throw new Error(`${name} is ${data.length} bytes, over the ${limit} its platform allows`);
    if (opaque && image.data.some((v, i) => i % 4 === 3 && v < 255)) throw new Error(`${name} must have no transparency`);
    this.files.set(name, { data, image });
  }

  ico(name, images, bitmapsBelow = 0) {
    const data = icoBytes(images, bitmapsBelow);
    this.files.set(name, { data, entries: images.map((image) => ({ png: image.width >= bitmapsBelow, image })) });
  }
}

/** Whether the existing bytes hold the file: the same bytes, or the same pixels stored the same way. */
function holds(existing, file) {
  if (existing.equals(file.data)) return true;
  try {
    if (file.image) return sameImage(decodePng(existing), file.image);
    if (file.entries) {
      const entries = decodeIco(existing);
      return entries.length === file.entries.length &&
        entries.every((e, i) => e.png === file.entries[i].png && sameImage(e.image, file.entries[i].image));
    }
  } catch {
    return false; // a file that doesn't decode is rewritten
  }
  return false;
}

function build(kit) {
  const master = mark().path();
  const word = WORDMARK.path(2);
  const regular = mark().placed(REGULAR, (GRID * (1 - REGULAR)) / 2, (GRID * (1 - REGULAR)) / 2).path();

  // mark/: the mark alone on a transparent background.
  for (const [name, ink] of Object.entries(INKS)) {
    kit.text(`mark/ncode-mark-${name}.svg`, svg(64, 64, `<path fill="${ink}" d="${master}"/>`));
    for (const size of [256, 1024]) kit.png(`mark/ncode-mark-${name}-${size}.png`, drawMark(size, ink));
  }
  kit.text('mark/ncode-mark-auto.svg', svg(64, 64, `${autoStyle()}<path d="${master}"/>`));

  // tile/: the mark on a solid tile, the app-icon form. "square" has no rounded corners, for a
  // platform that cuts its own.
  for (const [name, [fill, ink]] of Object.entries(TILES)) {
    const glyph = `<path fill="${ink}" d="${regular}"/>`;
    const rounded = `<rect width="64" height="64" rx="14" fill="${fill}"/>`;
    const square = `<path fill="${fill}" d="M0 0H64V64H0Z"/>`;
    kit.text(`tile/ncode-tile-${name}.svg`, svg(64, 64, rounded + glyph));
    kit.text(`tile/ncode-tile-${name}-square.svg`, svg(64, 64, square + glyph));
    for (const size of [256, 1024]) kit.png(`tile/ncode-tile-${name}-${size}.png`, drawTile(size, name, 'rounded', REGULAR));
    kit.png(`tile/ncode-tile-${name}-square-1024.png`, drawTile(1024, name, 'square', REGULAR), { opaque: true });
  }

  // lockup/: the mark and the wordmark.
  for (const [name, ink] of Object.entries(INKS)) {
    kit.text(`lockup/ncode-lockup-${name}.svg`, svg(LOCKUP_WIDTH, 64, `<path fill="${ink}" d="${master}${word}"/>`));
    for (const height of [128, 512]) kit.png(`lockup/ncode-lockup-${name}-h${height}.png`, drawLockup(height, ink));
  }
  kit.text('lockup/ncode-lockup-auto.svg', svg(LOCKUP_WIDTH, 64, `${autoStyle()}<path d="${master}${word}"/>`));

  // favicon/: the blue tile. The ICO holds a pixel-fitted drawing per size; the SVG is the 32-pixel
  // drawing, which is sharp at 32 and at its multiples.
  const small = mark(FITTED[32]).path();
  const iconSizes = [16, 20, 24, 32, 40, 48, 64];
  kit.ico('favicon/favicon.ico', iconSizes.map((s) => drawTile(s, 'blue', 'rounded', TIGHT)));
  kit.text('favicon/favicon.svg', svg(32, 32, `<rect width="32" height="32" rx="7" fill="${BLUE}"/>` +
    `<path fill="${WHITE}" d="${small}"/>`));
  kit.png('favicon/apple-touch-icon.png', drawTile(180, 'blue', 'square', REGULAR), { opaque: true });
  kit.png('favicon/icon-192.png', drawTile(192, 'blue', 'rounded', REGULAR));
  kit.png('favicon/icon-512.png', drawTile(512, 'blue', 'rounded', REGULAR));
  kit.png('favicon/icon-maskable-512.png', drawTile(512, 'blue', 'square', SAFE), { opaque: true });
  kit.text('favicon/site.webmanifest', `${JSON.stringify({
    name: 'NCode',
    short_name: 'NCode',
    icons: [
      { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
      { src: 'icon-512.png', sizes: '512x512', type: 'image/png' },
      { src: 'icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
    ],
    theme_color: BLUE,
    background_color: WHITE,
    display: 'standalone',
  }, null, 2)}\n`);
  // The same without a tile: blue for a light tab strip, light blue for a dark one.
  kit.ico('favicon/transparent/favicon.ico', iconSizes.map((s) => drawMark(s, BLUE)));
  kit.ico('favicon/transparent/favicon-dark.ico', iconSizes.map((s) => drawMark(s, LIGHT)));
  kit.text('favicon/transparent/favicon.svg', svg(32, 32, `${autoStyle()}<path d="${small}"/>`));

  // windows/: an application icon. Bitmaps up to 64 pixels, so System.Drawing and the resource
  // compiler read it, and a PNG at 256.
  kit.ico('windows/ncode.ico', [...iconSizes, 256].map((s) => drawTile(s, 'blue', 'rounded', TIGHT)), 256);

  // nuget/: 128 by 128, as NuGet recommends: twice the master, so every stem is on whole pixels, and
  // still is when a client shows the icon at half or a quarter of that.
  for (const name of Object.keys(TILES)) {
    kit.png(`nuget/ncode-nuget-tile-${name}.png`, drawTile(128, name, 'rounded', TIGHT), { limit: NUGET_LIMIT });
  }
  for (const name of ['blue', 'light']) kit.png(`nuget/ncode-nuget-mark-${name}.png`, drawMark(128, INKS[name]), { limit: NUGET_LIMIT });

  // profile/: a square that a circle can be cut from (GitHub and GitLab users, Gravatar, X, LinkedIn).
  for (const name of Object.keys(TILES)) {
    kit.png(`profile/ncode-profile-tile-${name}.png`, drawTile(1024, name, 'square', SAFE), { opaque: true });
  }
  for (const name of ['blue', 'light']) kit.png(`profile/ncode-profile-mark-${name}.png`, drawMark(1024, INKS[name], SAFE));

  // github/: an organization's picture (about 500 pixels, under 1 MB) and a repository's social
  // preview (1280 by 640, under 1 MB).
  for (const name of Object.keys(TILES)) {
    kit.png(`github/ncode-github-avatar-tile-${name}.png`, drawTile(500, name, 'square', REGULAR),
      { limit: GITHUB_LIMIT, opaque: true });
  }
  for (const name of ['blue', 'light']) {
    kit.png(`github/ncode-github-avatar-mark-${name}.png`, drawMark(500, INKS[name], REGULAR), { limit: GITHUB_LIMIT });
  }
  for (const name of Object.keys(CARDS)) {
    kit.png(`github/ncode-github-social-${name}.png`, drawCard(1280, 640, name), { limit: GITHUB_LIMIT, opaque: true });
  }

  // gitlab/: a group's or project's avatar (192 pixels, 200 KiB at most). A logo.png at a
  // repository's root is the project's avatar until one is uploaded.
  for (const name of Object.keys(TILES)) {
    kit.png(`gitlab/ncode-gitlab-avatar-tile-${name}.png`, drawTile(192, name, 'square', REGULAR),
      { limit: GITLAB_LIMIT, opaque: true });
  }
  for (const name of ['blue', 'light']) {
    kit.png(`gitlab/ncode-gitlab-avatar-mark-${name}.png`, drawMark(192, INKS[name], REGULAR), { limit: GITLAB_LIMIT });
  }
  kit.png('gitlab/logo.png', drawTile(192, 'blue', 'square', REGULAR), { limit: GITLAB_LIMIT, opaque: true });

  // myapps/: Microsoft Entra's My Apps takes exactly 215 by 215 pixels, PNG, 100 KB at most, and
  // asks for a solid background.
  for (const name of Object.keys(TILES)) {
    kit.png(`myapps/ncode-myapps-tile-${name}.png`, drawTile(215, name, 'square', REGULAR),
      { limit: MYAPPS_LIMIT, opaque: true });
  }

  // badge/: the mark cropped to its edges, as small a file as it gets, for a badge's logo. The .txt
  // files hold it as the value of Shields.io's logo parameter.
  const cropped = mark().placed(1, -4, -8).path(2);
  for (const name of ['white', 'blue', 'light']) {
    const badge = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 56 48">' +
      `<path fill="${INKS[name]}" d="${cropped}"/></svg>`;
    kit.text(`badge/ncode-badge-${name}.svg`, `${badge}\n`);
    const uri = `data:image/svg+xml;base64,${Buffer.from(badge, 'utf8').toString('base64')}`;
    kit.text(`badge/shields-logo-${name}.txt`, `${quote(uri)}\n`);
  }

  // social/: link previews (1200 by 630) and profile banners (1500 by 500).
  for (const name of Object.keys(CARDS)) {
    kit.png(`social/ncode-og-${name}.png`, drawCard(1200, 630, name), { opaque: true });
    kit.png(`social/ncode-banner-${name}.png`, drawCard(1500, 500, name), { opaque: true });
  }
}

const USAGE = 'Usage: node brand/build.mjs [--output <folder>] [--check]';

function main() {
  const here = dirname(fileURLToPath(import.meta.url));
  let values;
  try {
    ({ values } = parseArgs({
      options: { output: { type: 'string' }, check: { type: 'boolean', default: false }, help: { type: 'boolean', short: 'h' } },
    }));
  } catch (error) {
    console.error(`${error.message}\n${USAGE}`);
    return 2;
  }
  if (values.help) {
    console.log(`${USAGE}\n\nBuilds the NCode logo kit.\n` +
      '  --output <folder>  the folder to write the kit into (default: the one holding build.mjs)\n' +
      '  --check            write nothing; list each file that is missing or would change, and exit 1 if any is');
    return 0;
  }
  const root = resolve(values.output ?? here);
  const kit = new Kit();
  build(kit);

  // Each file in report order: the template's own copy of the NuGet package icon first, when the kit
  // goes to this folder and the template has one.
  const targets = [];
  const packageIcon = join(here, '..', 'template', 'NCodeGroup.png');
  if (root === here && existsSync(packageIcon) && statSync(packageIcon).isFile()) {
    targets.push({ name: 'template/NCodeGroup.png', path: packageIcon, file: kit.files.get('nuget/ncode-nuget-tile-blue.png'), counted: false });
  }
  for (const [name, file] of kit.files) targets.push({ name, path: join(root, name), file, counted: true });

  let changed = 0;
  let total = 0;
  for (const { name, path, file, counted } of targets) {
    const exists = existsSync(path);
    const kept = exists && holds(readFileSync(path), file);
    if (!kept) {
      changed++;
      if (!values.check) {
        mkdirSync(dirname(path), { recursive: true });
        writeFileSync(path, file.data);
      }
    }
    const onDisk = existsSync(path) ? statSync(path).size : null;
    if (counted) total += onDisk ?? 0;
    let note = '';
    if (!kept) note = values.check ? (exists ? '  would change' : '  missing') : '  written';
    console.log(`${name.padEnd(52)}${String(onDisk ?? '-').padStart(8)}${note}`);
  }
  console.log(`${kit.files.size} files, ${total} bytes`);
  const files = changed === 1 ? '1 file' : `${changed} files`;
  if (values.check) {
    console.log(changed ? `Missing or would change: ${files}. Run node brand/build.mjs to write them.` : 'No file would change.');
    return changed ? 1 : 0;
  }
  console.log(changed ? `Wrote ${files}.` : 'No file changed.');
  return 0;
}

try {
  process.exitCode = main();
} catch (error) {
  console.error(`build.mjs: ${error.message}`);
  process.exitCode = 1;
}
