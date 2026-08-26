.pragma library

// Peers Android's message-layout constants. Keep this file pure JS so the parity
// gate can execute the same sizing logic without constructing a QML scene.
var imageMaxWidth = 230;
var imageMaxHeight = 300;
var bubbleMaxRatio = 0.78;
var voiceBubbleRatio = 0.72;
var voiceReserved = 96;
var voiceMinWave = 96;
var voiceBarWidth = 2;
var voiceBarGap = 2;

function fitMedia(width, height) {
    var safeWidth = Number(width) > 0 ? Number(width) : 1;
    var safeHeight = Number(height) > 0 ? Number(height) : 1;
    var scale = Math.min(imageMaxWidth / safeWidth,
                         imageMaxHeight / safeHeight,
                         1);
    return {
        width: Math.round(safeWidth * scale),
        height: Math.round(safeHeight * scale)
    };
}

function voiceWaveWidth(availableWidth) {
    // A normal pane retains Android's 96px minimum. Extremely narrow desktop
    // panes may not have room for that minimum plus controls; shrink gracefully.
    return Math.max(8,
                    Math.round(Number(availableWidth) * voiceBubbleRatio) - voiceReserved);
}

function downsampleWaveform(samples, maxWidth) {
    var source = samples && samples.length > 0 ? samples : [8, 16, 24, 12, 20, 10];
    var maxBars = Math.max(1, Math.floor(Number(maxWidth)
                                        / (voiceBarWidth + voiceBarGap)));
    if (source.length <= maxBars)
        return Array.prototype.slice.call(source);

    var out = [];
    var bucket = source.length / maxBars;
    for (var i = 0; i < maxBars; ++i) {
        var start = Math.floor(i * bucket);
        var end = Math.max(start + 1, Math.floor((i + 1) * bucket));
        var sum = 0;
        var count = 0;
        for (var j = start; j < end && j < source.length; ++j) {
            sum += Number(source[j]);
            ++count;
        }
        out.push(count > 0 ? sum / count : 0);
    }
    return out;
}
