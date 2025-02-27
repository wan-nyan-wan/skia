/*
 * Copyright 2012 Google Inc.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#ifndef SkRadialGradient_DEFINED
#define SkRadialGradient_DEFINED

#include "src/shaders/gradients/SkGradientShaderPriv.h"

class SkShaderCodeDictionary;

class SkRadialGradient final : public SkGradientShaderBase {
public:
    SkRadialGradient(const SkPoint& center, SkScalar radius, const Descriptor&);

    GradientType asAGradient(GradientInfo* info) const override;
#if SK_SUPPORT_GPU
    std::unique_ptr<GrFragmentProcessor> asFragmentProcessor(const GrFPArgs&) const override;
#endif
#ifdef SK_ENABLE_SKSL
    void addToKey(const SkKeyContext&,
                  SkPaintParamsKeyBuilder*,
                  SkPipelineData*) const override;
#endif
protected:
    SkRadialGradient(SkReadBuffer& buffer);
    void flatten(SkWriteBuffer& buffer) const override;

    void appendGradientStages(SkArenaAlloc* alloc, SkRasterPipeline* tPipeline,
                              SkRasterPipeline* postPipeline) const override;

    skvm::F32 transformT(skvm::Builder*, skvm::Uniforms*,
                         skvm::Coord coord, skvm::I32* mask) const final;

private:
    SK_FLATTENABLE_HOOKS(SkRadialGradient)

    const SkPoint fCenter;
    const SkScalar fRadius;

    friend class SkGradientShader;
    using INHERITED = SkGradientShaderBase;
};

#endif
