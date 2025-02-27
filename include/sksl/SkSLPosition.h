/*
 * Copyright 2021 Google LLC.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#ifndef SKSL_POSITION
#define SKSL_POSITION

#ifndef __has_builtin
    #define __has_builtin(x) 0
#endif

namespace SkSL {

class Position {
public:
    Position()
        : fFile(nullptr)
        , fStartOffsetOrLine(-1)
        , fEndOffset(-1) {}

    static Position Line(int line, const char* file = nullptr) {
        Position result;
        result.fFile = file;
        result.fStartOffsetOrLine = line;
        result.fEndOffset = -1;
        return result;
    }

    static Position Range(int startOffset, int endOffset) {
        Position result;
        result.fFile = nullptr;
        result.fStartOffsetOrLine = startOffset;
        result.fEndOffset = endOffset;
        return result;
    }

#if __has_builtin(__builtin_FILE) && __has_builtin(__builtin_LINE)
    static Position Capture(const char* file = __builtin_FILE(), int line = __builtin_LINE()) {
        return Position::Line(line, file);
    }
#else
    static Position Capture() { return Position(); }
#endif // __has_builtin(__builtin_FILE) && __has_builtin(__builtin_LINE)

    const char* file_name() const {
        return fFile;
    }

    bool valid() const {
        return fStartOffsetOrLine != -1;
    }

    int line(const char* source = nullptr) const {
        SkASSERT(this->valid());
        if (fEndOffset == -1) {
            return fStartOffsetOrLine;
        }
        SkASSERT(source);
        int line = 1;
        for (int i = 0; i < fStartOffsetOrLine; i++) {
            if (source[i] == '\n') {
                ++line;
            }
        }
        return line;
    }

    int startOffset() const {
        SkASSERT(fEndOffset != -1);
        return fStartOffsetOrLine;
    }

    int endOffset() const {
        SkASSERT(fEndOffset != -1);
        return fEndOffset;
    }

    bool operator==(const Position& other) const {
        return fFile == other.fFile && fStartOffsetOrLine == other.fStartOffsetOrLine &&
                fEndOffset == other.fEndOffset;
    }

    bool operator!=(const Position& other) const {
        return !(*this == other);
    }

    bool operator>(const Position& other) const {
        return fStartOffsetOrLine > other.fStartOffsetOrLine;
    }

    bool operator>=(const Position& other) const {
        return fStartOffsetOrLine >= other.fStartOffsetOrLine;
    }

    bool operator<(const Position& other) const {
        return fStartOffsetOrLine < other.fStartOffsetOrLine;
    }

    bool operator<=(const Position& other) const {
        return fStartOffsetOrLine <= other.fStartOffsetOrLine;
    }

private:
    // TODO(skia:13051): remove fFile
    const char* fFile = nullptr;
    // Contains either a start offset (if fEndOffset != -1) or a line number (if fEndOffset == -1)
    int32_t fStartOffsetOrLine;
    int32_t fEndOffset;
};

} // namespace SkSL

#endif
