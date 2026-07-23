import AppKit
import Foundation

struct OffscreenFramePixels: Equatable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let rgba: Data

    func cellRGBA(
        column: Int,
        row: Int,
        frame: RenderFrameInfo
    ) -> Data? {
        let cellWidth = Int((frame.cellSizePoints.width * frame.backingScale).rounded())
        let cellHeight = Int((frame.cellSizePoints.height * frame.backingScale).rounded())
        guard
            cellWidth > 0,
            cellHeight > 0,
            column >= 0,
            row >= 0,
            column < frame.columns,
            row < frame.rows
        else {
            return nil
        }

        let originX = column * cellWidth
        let originY = (frame.rows - row - 1) * cellHeight
        guard originX + cellWidth <= width, originY + cellHeight <= height else {
            return nil
        }

        var result = Data()
        result.reserveCapacity(cellWidth * cellHeight * 4)
        for pixelRow in originY..<(originY + cellHeight) {
            let start = pixelRow * bytesPerRow + originX * 4
            result.append(rgba[start..<(start + cellWidth * 4)])
        }
        return result
    }
}

enum OffscreenRendererError: Error {
    case invalidDimensions
    case contextUnavailable
}

enum OffscreenRenderer {
    static func render(view: TerminalView, scale: Int = 2) throws -> OffscreenFramePixels {
        let width = Int((view.bounds.width * CGFloat(scale)).rounded())
        let height = Int((view.bounds.height * CGFloat(scale)).rounded())
        guard width > 0, height > 0, scale > 0 else {
            throw OffscreenRendererError.invalidDimensions
        }

        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard
            let context = CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else {
            throw OffscreenRendererError.contextUnavailable
        }

        var ownedWindow: NSWindow?
        if view.window == nil {
            let window = NSWindow(
                contentRect: view.bounds,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = view
            ownedWindow = window
        }

        defer {
            if let window = ownedWindow {
                window.contentView = NSView(frame: .zero)
                window.close()
            }
        }

        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        let observer = view.renderObserver
        view.renderObservationScaleForced = true
        view.renderObserver = nil
        defer {
            view.renderObserver = observer
            view.renderObservationScaleForced = false
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        view.needsDisplay = true
        view.displayIgnoringOpacity(view.bounds, in: graphics)
        // AppKit can traverse a detached view more than once. Observation is
        // attached only to this single authoritative draw into the same bitmap.
        view.renderObserver = observer
        view.draw(view.bounds)
        view.renderObserver = nil
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return OffscreenFramePixels(
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            rgba: Data(bytes)
        )
    }
}
