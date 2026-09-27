import QtQuick
import QtTest

SwiftRollTrackHeadersSupport {
    function meterPixels(row) {
        waitForRendering(row)
        var image = grabImage(testCase)
        var origin = row.mapToItem(testCase, 0, 0)
        var h = surface().headersModel
        var dpr = image.width / testCase.width
        var x0 = Math.round(origin.x * dpr)
        var y0 = Math.round(origin.y * dpr)
        var width = Math.round((origin.x + h.activityWidth) * dpr) - x0
        var height = Math.round((origin.y + h.rowHeight - h.separatorWidth) * dpr) - y0
        verify(width > 0 && height > 0 && x0 >= 0 && y0 >= 0
               && x0 + width <= image.width && y0 + height <= image.height)
        var pixels = []
        for (var y = 0; y < height; ++y)
            for (var x = 0; x < width; ++x)
                pixels.push(image.pixel(x0 + x, y0 + y))
        return { pixels: pixels, width: width, height: height, dpr: dpr }
    }

    function test_zMountedMeterWindowRasterAndScopedRows() {
        var s = surface()
        var h = s.headersModel
        var rows = item("timelineTrackHeaderRows")
        var band = item("timelineQuickTrackHeaders")
        verify(band.visible && rows.itemAt(0).visible,
               "the converted window exposes the mounted header band")
        var dpr = s.Screen.devicePixelRatio
        verify(dpr > 0)
        var meterHeight = h.rowHeight - h.separatorWidth
        var otherTitle = rows.itemAt(1).title
        var neighbor = rows.itemAt(1)
        verify(bootstrap.presentHeaderActivity(0, 0, 0, true))
        var silentNeighbor = meterPixels(neighbor)
        verify(bootstrap.presentHeaderActivity(0, 255, 128, true))
        var first = rows.itemAt(0)
        var left = Math.round(meterHeight * dpr) / dpr
        var right = Math.round(128 / 255 * meterHeight * dpr) / dpr
        tryVerify(function() { return near(first.activityLeftHeight, left) },
                  5000, "meter height follows the window's device pixel ratio")
        tryVerify(function() { return near(first.activityRightHeight, right) },
                  5000, "right meter height follows the window's device pixel ratio")
        verify(near(first.activityLeftHeight * dpr, Math.round(first.activityLeftHeight * dpr)),
               "the meter snaps to whole device pixels at the window's ratio")
        compare(rows.itemAt(1).activityLeftHeight, 0,
                "activity republishes only the driven row")
        compare(rows.itemAt(1).activityRightHeight, 0,
                "activity republishes only the driven row's right channel")
        compare(rows.itemAt(1), neighbor,
                "activity keeps the neighboring delegate mounted")
        compare(rows.itemAt(1).title, otherTitle,
                "an activity publication preserves the neighboring row title")
        var undriven = meterPixels(neighbor)
        compare(undriven.width, silentNeighbor.width,
                "an undriven neighbor row's meter keeps its captured width")
        compare(undriven.height, silentNeighbor.height,
                "an undriven neighbor row's meter keeps its captured height")
        compare(undriven.pixels, silentNeighbor.pixels,
                "an undriven neighbor row's meter stays unpainted")
        var activity = item("timelineHeaderActivity_0")
        waitForRendering(activity)
        var before = grabImage(testCase)
        verify(before.width > 0, "the mounted activity meter captures a raster image")
        verify(before.height > 0, "the activity raster has physical rows")
        var origin = activity.mapToItem(testCase, 0, 0)
        var scale = before.width / testCase.width
        var x = Math.round((origin.x + activity.width / 4) * scale)
        var top = Math.round(origin.y * scale)
        var bottom = Math.round((origin.y + activity.height) * scale)
        verify(x >= 0 && x < before.width && top >= 0 && bottom > top
               && bottom <= before.height)
        var active = first.activityActiveColor
        var count = 0
        for (var y = top; y < bottom; ++y) {
            var pixel = before.pixel(x, y)
            if (Math.abs(pixel.r - active.r) * 255 <= 8
                && Math.abs(pixel.g - active.g) * 255 <= 8
                && Math.abs(pixel.b - active.b) * 255 <= 8)
                count++
        }
        compare(count, Math.round(meterHeight * dpr),
                "the meter paints its active bar at the snapped device-pixel height")
        compare(before.width, Math.round(testCase.width * dpr),
                "the raster matches the window's device-pixel geometry")
        compare(before.height, Math.round(testCase.height * dpr),
                "the raster matches the window's physical row count")
        var stereo = meterPixels(first)
        compare(stereo.width,
                Math.round((origin.x + h.activityWidth) * stereo.dpr)
                  - Math.round(origin.x * stereo.dpr),
                "the meter raster spans exact device pixels")
        compare(stereo.height,
                Math.round((origin.y + meterHeight) * stereo.dpr)
                  - Math.round(origin.y * stereo.dpr),
                "the meter raster height spans exact device pixels")
        var rightColumn = Math.floor(stereo.width * 3 / 4)
        var leftColumn = Math.floor(stereo.width / 4)
        var partial = 0
        var bottomColor = stereo.pixels[(stereo.height - 1) * stereo.width + rightColumn]
        for (var ry = stereo.height - 1; ry >= 0; --ry) {
            if (stereo.pixels[ry * stereo.width + rightColumn] !== bottomColor)
                break
            ++partial
        }
        verify(Math.abs(partial - Math.round(right * stereo.dpr)) <= 1
               && stereo.pixels[(stereo.height - 1) * stereo.width + leftColumn] === bottomColor,
               "the stereo right channel paints its partial height")
        verify(bootstrap.presentHeaderActivity(0, 255, 128, true))
        waitForRendering(activity)
        var after = grabImage(testCase)
        var stableX0 = Math.floor(origin.x * scale)
        var stableX1 = Math.ceil((origin.x + activity.width) * scale)
        var withinStable = stableX0 >= 0 && stableX1 > stableX0
                           && stableX1 <= before.width && stableX1 <= after.width
                           && top >= 0 && bottom > top
                           && bottom <= before.height && bottom <= after.height
        var same = true
        if (withinStable) {
            for (var py = top; py < bottom && same; ++py)
                for (var px = stableX0; px < stableX1; ++px)
                    if (before.pixel(px, py) !== after.pixel(px, py)) {
                        same = false
                        break
                    }
        }
        verify(withinStable && same, "an unchanged physical height repaints the same meter raster")
        verify(bootstrap.presentHeaderActivity(0, 0, 0, false))
        tryCompare(first, "activityLeftHeight", left, 5000,
                   "paused activity fills the left channel at the observed ratio")
        compare(first.activityRightHeight, left,
                "paused activity fills the right channel at the observed ratio")
        waitForRendering(activity)
        var pausedImage = grabImage(testCase)
        var rightX = Math.round((origin.x + 3 * activity.width / 4) * scale)
        verify(rightX >= 0 && rightX < pausedImage.width
               && top >= 0 && bottom > top && bottom <= pausedImage.height)
        var filledRightRows = 0
        for (var rowY = top; rowY < bottom; ++rowY) {
            var pausedPixel = pausedImage.pixel(rightX, rowY)
            if (Math.abs(pausedPixel.r - active.r) * 255 <= 8
                && Math.abs(pausedPixel.g - active.g) * 255 <= 8
                && Math.abs(pausedPixel.b - active.b) * 255 <= 8)
                filledRightRows++
        }
        compare(filledRightRows, Math.round(meterHeight * dpr),
                "paused right channel paints a full-height device-pixel raster")
        verify(bootstrap.presentHeaderActivity(0, 0, 0, true))
    }

}
