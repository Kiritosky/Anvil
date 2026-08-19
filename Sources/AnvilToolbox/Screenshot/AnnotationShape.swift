import AnvilKit
import AnvilUI
import Foundation
import SwiftUI

/// One mark, drawn on screen.
struct AnnotationShape: View {
    let annotation: Annotation
    /// Where the picture sits inside its pane.
    let frame: CGRect

    var body: some View {
        let color = annotation.color.color
            .opacity(annotation.kind == .highlight ? 0.35 : 1)
        let rect = viewRect
        let width = annotation.lineWidth

        Group {
            switch annotation.kind {
            case .rectangle:
                Rectangle()
                    .strokeBorder(color, lineWidth: width)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            case .ellipse:
                Ellipse()
                    .strokeBorder(color, lineWidth: width)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            case .highlight, .redact:
                Rectangle()
                    .fill(color)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            case .line:
                Path { path in
                    path.move(to: viewPoint(annotation.start))
                    path.addLine(to: viewPoint(annotation.end))
                }
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            case .arrow:
                arrow.fill(color)
            }
        }
        .allowsHitTesting(false)
    }

    /// Shaft and head as one filled path, so the two never come apart at a
    /// corner the way a stroked line and a filled triangle do.
    private var arrow: Path {
        let start = viewPoint(annotation.start)
        let end = viewPoint(annotation.end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(annotation.lineWidth * 4, 12)
        let spread = CGFloat.pi / 7
        let half = annotation.lineWidth / 2

        let shaftEnd = CGPoint(
            x: end.x - cos(angle) * headLength * 0.8,
            y: end.y - sin(angle) * headLength * 0.8
        )
        let normal = CGPoint(x: -sin(angle) * half, y: cos(angle) * half)

        return Path { path in
            path.move(to: CGPoint(x: start.x + normal.x, y: start.y + normal.y))
            path.addLine(to: CGPoint(x: shaftEnd.x + normal.x, y: shaftEnd.y + normal.y))
            path.addLine(to: CGPoint(x: shaftEnd.x - normal.x, y: shaftEnd.y - normal.y))
            path.addLine(to: CGPoint(x: start.x - normal.x, y: start.y - normal.y))
            path.closeSubpath()

            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - cos(angle - spread) * headLength,
                y: end.y - sin(angle - spread) * headLength
            ))
            path.addLine(to: CGPoint(
                x: end.x - cos(angle + spread) * headLength,
                y: end.y - sin(angle + spread) * headLength
            ))
            path.closeSubpath()
        }
    }

    private var viewRect: CGRect {
        let normalized = annotation.normalizedRect
        return CGRect(
            x: frame.minX + normalized.minX * frame.width,
            y: frame.minY + normalized.minY * frame.height,
            width: normalized.width * frame.width,
            height: normalized.height * frame.height
        )
    }

    private func viewPoint(_ normalized: CGPoint) -> CGPoint {
        CGPoint(
            x: frame.minX + normalized.x * frame.width,
            y: frame.minY + normalized.y * frame.height
        )
    }
}

// MARK: - Settings keys

extension SettingKey {
    public static var annotationKind: SettingKey<Annotation.Kind> {
        SettingKey<Annotation.Kind>("screenshot.annotation.kind", default: .arrow)
    }

    public static var annotationColor: SettingKey<String> {
        SettingKey<String>("screenshot.annotation.color", default: "#FF3B30")
    }

    public static var annotationWidth: SettingKey<Int> {
        SettingKey<Int>("screenshot.annotation.width", default: 4)
    }
}
