#pragma once

#include <QProcessEnvironment>
#include <QString>

//
// Locating and launching the media helpers this module ships.
//
// Basecamp bundles no Qt Multimedia — verified twice: nothing named *Multimedia*
// is loaded by the running app (Core/Gui/Quick/Widgets/RemoteObjects are), and no
// shipped module imports it. The platform's own answer to "play audio" is the
// `receiver_ui` module, which bundles ffplay + SDL2 + libpulse under its
// `plugins/receiver_ui/bin/` and drives it over QProcess. This follows that,
// including the two traps it documents — both of which produce a module that
// fails in ways with no useful error.
//
namespace MediaTools {

// The directory this plugin was loaded from, so bundled helpers under `bin/` can
// be preferred over whatever the user happens to have installed.
//
// Read out of /proc/self/maps, deliberately NOT dladdr: dladdr pulls
// dladdr@GLIBC_2.34, which the AppImage's older bundled glibc cannot resolve, so
// the plugin fails to dlopen at all (receiver_ui #75). Empty when unknown, which
// simply falls back to PATH.
QString moduleDir();

// Resolve a helper binary. Priority: the PEERS_<NAME>_BIN override → the bundled
// binary under <moduleDir>/bin/ → the bare name on PATH.
QString resolveBin(const QString& name);

// Read the first video/image stream's dimensions with ffprobe. Input protocols
// are restricted to local data so even a playlist-shaped selected file cannot
// make the helper contact the network.
bool probeMediaSize(const QString& path, int* width, int* height);

// True when `path` is one of ours under <moduleDir>/bin/.
bool isBundled(const QString& path);

// The environment a spawned helper must get.
//
// A nix-built bundled binary MUST NOT inherit the AppImage's LD_LIBRARY_PATH or
// LD_PRELOAD: it would load the host's mismatched libraries and die (Basecamp
// skill: appimage-child-ld-library-path). Bundled binaries are $ORIGIN-rpath'd,
// so dropping these costs them nothing.
QProcessEnvironment cleanSpawnEnv();

// Where decoded attachments are written so QML can load them.
//
// Prefers <moduleDir>/media-cache. That matters because a shipped module
// (hashweb_ui) documents that "Basecamp's plugin sandbox blocks file:// outside
// the plugin roots" — I could not find a URL interceptor in this build's
// ui-host, so the restriction may be stale or version-specific, but writing
// inside the plugin root satisfies BOTH readings at no cost. Falls back to the
// standard cache location when the module dir is unknown (the standalone test
// host) or not writable.
QString mediaCacheDir();

}   // namespace MediaTools
