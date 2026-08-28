#pragma once

#include <cstddef>
#include <cstdint>

namespace GifSafety {

constexpr int maxSourceAxis = 4096;
constexpr std::int64_t maxSourcePixels = 8 * 1024 * 1024;
constexpr int maxDecodeAxis = 640;
constexpr std::size_t maxFileBytes = 100 * 1024 * 1024;

struct Classification {
    bool isGif = false;
    int decodeWidth = 0;
    int decodeHeight = 0;

    constexpr bool isValid() const
    {
        return decodeWidth > 0 && decodeHeight > 0;
    }
};

namespace Detail {

inline bool hasBytes(std::size_t offset, std::size_t count, std::size_t size)
{
    return offset <= size && count <= size - offset;
}

inline int littleEndian16(const unsigned char* bytes)
{
    return static_cast<int>(bytes[0]) | (static_cast<int>(bytes[1]) << 8);
}

inline bool skipColorTable(unsigned char packed, std::size_t size, std::size_t& offset)
{
    if ((packed & 0x80U) == 0)
        return true;
    const std::size_t entries = std::size_t{1} << ((packed & 0x07U) + 1U);
    const std::size_t tableBytes = entries * 3U;
    if (!hasBytes(offset, tableBytes, size))
        return false;
    offset += tableBytes;
    return true;
}

inline bool skipSubBlocks(const unsigned char* bytes, std::size_t size,
                          std::size_t& offset, bool requireData)
{
    bool sawData = false;
    while (offset < size) {
        const std::size_t blockSize = bytes[offset++];
        if (blockSize == 0)
            return !requireData || sawData;
        if (!hasBytes(offset, blockSize, size))
            return false;
        sawData = true;
        offset += blockSize;
    }
    return false;
}

inline bool hasCompleteStructure(const unsigned char* bytes, std::size_t size,
                                 int logicalWidth, int logicalHeight)
{
    if (size < 13 || size > maxFileBytes)
        return false;

    std::size_t offset = 13;
    if (!skipColorTable(bytes[10], size, offset))
        return false;

    bool sawImage = false;
    while (offset < size) {
        const unsigned char marker = bytes[offset++];
        if (marker == 0x3b)
            return sawImage && offset == size;

        if (marker == 0x21) {
            if (!hasBytes(offset, 1, size))
                return false;
            ++offset; // extension label
            if (!skipSubBlocks(bytes, size, offset, false))
                return false;
            continue;
        }

        if (marker != 0x2c || !hasBytes(offset, 9, size))
            return false;

        const int left = littleEndian16(bytes + offset);
        const int top = littleEndian16(bytes + offset + 2);
        const int width = littleEndian16(bytes + offset + 4);
        const int height = littleEndian16(bytes + offset + 6);
        const unsigned char packed = bytes[offset + 8];
        if (width < 1 || height < 1
            || static_cast<std::int64_t>(left) + width > logicalWidth
            || static_cast<std::int64_t>(top) + height > logicalHeight) {
            return false;
        }
        offset += 9;
        if (!skipColorTable(packed, size, offset) || !hasBytes(offset, 1, size))
            return false;

        const unsigned char minimumCodeSize = bytes[offset++];
        if (minimumCodeSize < 2 || minimumCodeSize > 8
            || !skipSubBlocks(bytes, size, offset, true)) {
            return false;
        }
        sawImage = true;
    }
    return false;
}

} // namespace Detail

inline Classification classify(const unsigned char* bytes, std::size_t size)
{
    Classification result;
    if (!bytes || size < 6)
        return result;

    const bool gif87a = bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F'
        && bytes[3] == '8' && bytes[4] == '7' && bytes[5] == 'a';
    const bool gif89a = bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F'
        && bytes[3] == '8' && bytes[4] == '9' && bytes[5] == 'a';
    if (!gif87a && !gif89a)
        return result;

    result.isGif = true;
    if (size < 13)
        return result;

    const int width = Detail::littleEndian16(bytes + 6);
    const int height = Detail::littleEndian16(bytes + 8);
    if (width < 1 || height < 1 || width > maxSourceAxis || height > maxSourceAxis
        || static_cast<std::int64_t>(width) * height > maxSourcePixels
        || !Detail::hasCompleteStructure(bytes, size, width, height)) {
        return result;
    }

    if (width <= maxDecodeAxis && height <= maxDecodeAxis) {
        result.decodeWidth = width;
        result.decodeHeight = height;
    } else if (width >= height) {
        result.decodeWidth = maxDecodeAxis;
        result.decodeHeight = static_cast<int>(
            (static_cast<std::int64_t>(height) * maxDecodeAxis + width / 2) / width);
        if (result.decodeHeight < 1)
            result.decodeHeight = 1;
    } else {
        result.decodeHeight = maxDecodeAxis;
        result.decodeWidth = static_cast<int>(
            (static_cast<std::int64_t>(width) * maxDecodeAxis + height / 2) / height);
        if (result.decodeWidth < 1)
            result.decodeWidth = 1;
    }
    return result;
}

} // namespace GifSafety
