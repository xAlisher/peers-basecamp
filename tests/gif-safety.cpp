#include "../plugins/peers_ui/src/GifSafety.h"

#include <array>
#include <cstdlib>
#include <iostream>
#include <string_view>
#include <vector>

namespace {

std::vector<unsigned char> validGif(int width, int height,
                                    std::string_view signature = "GIF89a")
{
    // Complete one-frame GIF: logical screen, global color table, image block,
    // bounded LZW data sub-block, terminator, and trailer. The one-pixel frame
    // remains inside any accepted logical screen dimensions used by the tests.
    std::vector<unsigned char> bytes{
        'G', 'I', 'F', '8', '9', 'a',
        0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
        0x00, 0x00, 0x00, 0xff, 0xff, 0xff,
        0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0x02, 0x01, 0x4c, 0x00, 0x3b,
    };
    for (std::size_t i = 0; i < signature.size() && i < 6; ++i)
        bytes[i] = static_cast<unsigned char>(signature[i]);
    bytes[6] = static_cast<unsigned char>(width & 0xff);
    bytes[7] = static_cast<unsigned char>((width >> 8) & 0xff);
    bytes[8] = static_cast<unsigned char>(height & 0xff);
    bytes[9] = static_cast<unsigned char>((height >> 8) & 0xff);
    return bytes;
}

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
    const auto landscape = validGif(1920, 1080, "GIF87a");
    const auto landscapeResult = GifSafety::classify(landscape.data(), landscape.size());
    require(landscapeResult.isGif, "GIF87a signature was not recognized");
    require(landscapeResult.decodeWidth == 640 && landscapeResult.decodeHeight == 360,
            "complete landscape GIF is not aspect-preserving and bounded");

    const auto portrait = validGif(1080, 1920);
    const auto portraitResult = GifSafety::classify(portrait.data(), portrait.size());
    require(portraitResult.isGif, "GIF89a signature was not recognized");
    require(portraitResult.decodeWidth == 360 && portraitResult.decodeHeight == 640,
            "complete portrait GIF is not aspect-preserving and bounded");

    for (std::size_t size = 6; size < portrait.size(); ++size) {
        const auto result = GifSafety::classify(portrait.data(), size);
        require(result.isGif && !result.isValid(),
                "a truncated signed GIF prefix was accepted");
    }

    const auto headerOnly = validGif(10, 10);
    require(!GifSafety::classify(headerOnly.data(), 13).isValid(),
            "header-only signed GIF was accepted");

    const auto zeroAxis = validGif(0, 10);
    const auto zeroResult = GifSafety::classify(zeroAxis.data(), zeroAxis.size());
    require(zeroResult.isGif && !zeroResult.isValid(), "zero-axis GIF did not fail closed");

    const auto oversizedAxis = validGif(4097, 1);
    const auto oversizedAxisResult = GifSafety::classify(oversizedAxis.data(), oversizedAxis.size());
    require(oversizedAxisResult.isGif && !oversizedAxisResult.isValid(),
            "oversized-axis GIF did not fail closed");

    const auto excessivePixels = validGif(4096, 4096);
    const auto excessivePixelsResult = GifSafety::classify(excessivePixels.data(), excessivePixels.size());
    require(excessivePixelsResult.isGif && !excessivePixelsResult.isValid(),
            "excessive-pixel GIF did not fail closed");

    auto outOfBoundsFrame = validGif(10, 10);
    outOfBoundsFrame[24] = 11;
    require(!GifSafety::classify(outOfBoundsFrame.data(), outOfBoundsFrame.size()).isValid(),
            "out-of-bounds image descriptor was accepted");

    constexpr std::array<unsigned char, 8> pngHeader{0x89, 'P', 'N', 'G'};
    constexpr std::array<unsigned char, 8> jpegHeader{0xff, 0xd8, 0xff, 0xe0};
    require(!GifSafety::classify(pngHeader.data(), pngHeader.size()).isGif,
            "PNG bytes were classified as GIF");
    require(!GifSafety::classify(jpegHeader.data(), jpegHeader.size()).isGif,
            "JPEG bytes were classified as GIF");

    std::cout << "ok: complete and hostile GIF streams are byte-classified and decode-bounded\n";
}
