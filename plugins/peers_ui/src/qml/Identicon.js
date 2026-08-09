.pragma library

//
// The Peers HexAvatar identicon — a straight port of
// logos-chat-android `src/components/HexAvatar.tsx` (`identiconCells`).
//
// Kept as a QML JS library, not a C++ backend call, for two reasons: every
// avatar in a list would otherwise cost a QtRO round trip, and the original is
// JavaScript, so porting it as JavaScript is the only version that is exact by
// construction rather than by careful re-derivation.
//
// Equivalence with the Android implementation is proven, not assumed:
// `tests/identicon-equivalence.mjs` runs this file and the real
// `HexAvatar.tsx` implementation over the same seeds and diffs the output.
//
// Out of scope for desktop: the `mesh` (green) and `ble` (azure) ramps. Peers
// colours the identicon by TRANSPORT, and this client has only the Logos
// transport, so `contact` and `group` both resolve to the orange LOGOS ramp —
// exactly as they do on Android.
//

// Dark → near-white. The top of each ramp is close to white so bright cells pop.
var LOGOS_RAMP = ['#B8420E', '#FF5000', '#FF7A33', '#FFB27A', '#FFE4D0'];

var RAMPS = {
    contact: LOGOS_RAMP,
    group: LOGOS_RAMP
};

var PREFIX = {
    contact: 'c:',
    group: 'g:'
};

var AVATAR_N = 5;

// The avatar ground, shown through empty cells. `colors.canvas` on Android.
var GROUND = '#0A0A0A';

// Container corner radius as a fraction of the side.
var RADIUS_RATIO = 0.22;

// mulberry32 seeded via an xmur3 hash of the seed — deterministic per identity.
//
// Every operation here is 32-bit. `Math.imul` is a wrapping 32-bit multiply,
// `>>>` is a logical shift on the 32-bit pattern, and `charCodeAt` yields UTF-16
// code units. QML's JS engine provides all three with the same semantics, so
// this is a verbatim copy rather than a reimplementation.
function rng(seed) {
    var h = 1779033703 ^ seed.length;
    for (var i = 0; i < seed.length; i++) {
        h = Math.imul(h ^ seed.charCodeAt(i), 3432918353);
        h = (h << 13) | (h >>> 19);
    }
    var a = Math.imul(h ^ (h >>> 13), 3266489909);
    a = (a ^ (a >>> 16)) >>> 0;
    return function () {
        a |= 0;
        a = (a + 0x6d2b79f5) | 0;
        var t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

//
// The filled cells of the identicon, in grid units (0..4), for a given
// (seed, kind). Returns [{x, y, fill}, …].
//
// Three details are load-bearing and easy to get wrong:
//
//  1. Iteration is COLUMN-MAJOR — x outer (0,1,2), y inner (0..4). Fifteen
//     decisions, not twenty-five.
//  2. There are two rolls per cell, but the SECOND IS ONLY CONSUMED WHEN THE
//     CELL IS FILLED. A port that draws both rolls unconditionally advances the
//     PRNG differently and diverges from the second skipped cell onward.
//  3. Column x also paints column 4-x with the SAME colour; column 2 is the
//     centre and is painted once. That is what makes it left-right symmetric.
//
function identiconCells(seed, kind) {
    var k = RAMPS[kind] ? kind : 'contact';
    var ramp = RAMPS[k];
    var r = rng(PREFIX[k] + seed);
    var cells = [];
    // Only the left three columns are decided; columns 0,1 mirror to 4,3.
    for (var x = 0; x < 3; x++) {
        for (var y = 0; y < AVATAR_N; y++) {
            if (r() > 0.5) {
                continue; // empty cell → shows the avatar ground
            }
            var fill = ramp[Math.floor(r() * ramp.length)];
            var xs = x === 2 ? [2] : [x, AVATAR_N - 1 - x];
            for (var j = 0; j < xs.length; j++) {
                cells.push({ x: xs[j], y: y, fill: fill });
            }
        }
    }
    return cells;
}
