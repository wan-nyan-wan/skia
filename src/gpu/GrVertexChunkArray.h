/*
 * Copyright 2021 Google LLC.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#ifndef GrVertexChunkArray_DEFINED
#define GrVertexChunkArray_DEFINED

#include "include/core/SkRefCnt.h"
#include "include/private/SkNoncopyable.h"
#include "include/private/SkTArray.h"
#include "src/gpu/BufferWriter.h"
#include "src/gpu/GrBuffer.h"

class GrMeshDrawTarget;

// Represents a chunk of vertex data. Use with GrVertexChunkArray and GrVertexChunkBuilder. We write
// the data out in chunks when we don't start out knowing exactly how many vertices (or instances)
// we will end up writing.
struct GrVertexChunk {
    sk_sp<const GrBuffer> fBuffer;
    int fCount = 0;
    int fBase;  // baseVertex or baseInstance, depending on the use case.
};

// Represents an array of GrVertexChunks.
//
// We only preallocate 1 chunk because if the array needs to grow, then we're also allocating a
// brand new GPU buffer anyway.
using GrVertexChunkArray = SkSTArray<1, GrVertexChunk>;

// Builds a GrVertexChunkArray. The provided Target must not be used externally throughout the
// entire lifetime of this object. GrVertexChunkBuilder is drop-in compatible for the PatchAllocator
// parameter to PatchWriter.
class GrVertexChunkBuilder : SkNoncopyable {
public:
    // Stride must come first to be compatible with PatchWriter's templating.
    GrVertexChunkBuilder(size_t stride, GrMeshDrawTarget* target, GrVertexChunkArray* chunks,
                         int minVerticesPerChunk)
            : fTarget(target)
            , fChunks(chunks)
            , fStride(stride)
            , fMinVerticesPerChunk(minVerticesPerChunk) {
        SkASSERT(fMinVerticesPerChunk > 0);
    }

    ~GrVertexChunkBuilder();

    size_t stride() const { return fStride; }

    // Appends 'count' contiguous vertices. These vertices are not guaranteed to be contiguous with
    // previous or future calls to appendVertices.
    SK_ALWAYS_INLINE skgpu::VertexWriter appendVertices(int count) {
        SkASSERT(count > 0);
        if (fCurrChunkVertexCount + count > fCurrChunkVertexCapacity && !this->allocChunk(count)) {
            SkDEBUGCODE(fLastAppendAmount = 0;)
            return {};
        }
        SkASSERT(fCurrChunkVertexCount + count <= fCurrChunkVertexCapacity);
        fCurrChunkVertexCount += count;
        SkDEBUGCODE(fLastAppendAmount = count;)
        return std::exchange(fCurrChunkVertexWriter,
                             fCurrChunkVertexWriter.makeOffset(fStride * count));
    }

    // PatchWriter's allocator template requires an append() function
    SK_ALWAYS_INLINE skgpu::VertexWriter append() { return this->appendVertices(1); }

    // Pops the most recent 'count' contiguous vertices. Since there is no guarantee of contiguity
    // between appends, 'count' may be no larger than the most recent call to appendVertices().
    void popVertices(int count) {
        SkASSERT(count <= fLastAppendAmount);
        SkASSERT(fLastAppendAmount <= fCurrChunkVertexCount);
        SkASSERT(count >= 0);
        fCurrChunkVertexCount -= count;
        fCurrChunkVertexWriter = fCurrChunkVertexWriter.makeOffset(fStride * -count);
        SkDEBUGCODE(fLastAppendAmount -= count;)
    }

private:
    bool allocChunk(int minCount);

    GrMeshDrawTarget* const fTarget;
    GrVertexChunkArray* const fChunks;
    const size_t fStride;
    int fMinVerticesPerChunk;

    skgpu::VertexWriter fCurrChunkVertexWriter;
    int fCurrChunkVertexCount = 0;
    int fCurrChunkVertexCapacity = 0;

    SkDEBUGCODE(int fLastAppendAmount = 0;)
};

#endif
