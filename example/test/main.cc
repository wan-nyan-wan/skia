/*
 * Copyright 2015 Google Inc.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */
#include <iostream>

#include "include/c/sk_data.h"
#include "include/c/sk_image.h"
#include "include/c/sk_imageinfo.h"
#include "include/c/sk_paint.h"
#include "include/c/sk_path.h"
#include "include/c/sk_surface.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkData.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPath.h"
#include "include/core/SkPathBuilder.h"
#include "include/core/SkRect.h"
#include "include/core/SkSurface.h"

static void emit_png(const char* path, sk_sp<SkSurface> surface) {
    sk_sp<SkImage> image = surface->makeImageSnapshot();
    sk_sp<SkData> data = image->encodeToData();
    FILE* f = fopen(path, "wb");
    fwrite(data->data(), data->size(), 1, f);
    fclose(f);
}

void draw(SkCanvas* canvas) {
    SkPaint fill = SkPaint();
    fill.setColor(sk_color_set_argb(0xFF, 0x00, 0x00, 0xFF));
    canvas->drawPaint(fill);

    fill.setColor(sk_color_set_argb(0xFF, 0x00, 0xFF, 0xFF));
    SkRect rect = SkRect::MakeLTRB(100.0f, 100.0f, 540.0f, 380.0f);

    canvas->drawRect(rect, fill);

    SkPaint stroke = SkPaint();

    stroke.setColor(sk_color_set_argb(0xFF, 0xFF, 0x00, 0x00));
    stroke.setAntiAlias(true);
    stroke.setStroke(true);

    stroke.setStrokeWidth(5.0f);

    SkPathBuilder pathBuilder = SkPathBuilder();
    pathBuilder.moveTo(50.0f, 50.0f);
    pathBuilder.lineTo(590.0f, 50.0f);
    pathBuilder.cubicTo(-490.0f, 50.0f, 1130.0f, 430.0f, 50.0f, 430.0f);
    pathBuilder.lineTo(590.0f, 430.0f);

    SkPath path = pathBuilder.detach();
    canvas->drawPath(path, stroke);

    fill.setColor(sk_color_set_argb(0x80, 0x00, 0xFF, 0x00));
    SkRect rect2 = SkRect::MakeLTRB(120.0f, 120.0f, 520.0f, 360.0f);
    canvas->drawOval(rect2, fill);
}

int main() {
    int w = 640;
    int h = 480;
    SkImageInfo info = SkImageInfo::Make(
            w, h, SkColorType::kBGRA_8888_SkColorType, SkAlphaType::kPremul_SkAlphaType);
    sk_sp<SkSurface> surface = SkSurface::MakeRaster(info);
    SkCanvas* canvas = surface->getCanvas();
    draw(canvas);
    emit_png("skia-test.png", surface);
    return 0;
}
