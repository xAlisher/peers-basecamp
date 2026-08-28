#include "StorageBounds.h"

#include <cstdlib>
#include <iostream>

namespace {

void require(bool condition, const char* message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

} // namespace

int main()
{
    using namespace StorageBounds;

    require(maxCiphertextBytesForMime(QStringView(u"audio/mp4")) == 2LL * 1024 * 1024,
            "audio is capped at 2 MiB");
    require(maxCiphertextBytesForMime(QStringView(u"AUDIO/OGG")) == 2LL * 1024 * 1024,
            "audio MIME casing cannot bypass the cap");
    require(maxCiphertextBytesForMime(QStringView(u"image/png")) == 100LL * 1024 * 1024,
            "visual media retains the general cap");
    require(validCacheFileSize(2LL * 1024 * 1024, QStringView(u"audio/mp4")),
            "audio cache accepts exact limit");
    require(!validCacheFileSize(2LL * 1024 * 1024 + 1, QStringView(u"audio/mp4")),
            "audio cache rejects limit plus one");
    require(!validCacheFileSize(0, QStringView(u"audio/mp4")),
            "empty cache entries are invalid");

    std::cout << "ok: hosted audio materialization is capped at 2 MiB\n";
    return 0;
}
