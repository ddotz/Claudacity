//
//  IconGenerator.swift
//  Claudacity
//

// MARK: - Imports
import AppKit
import SwiftUI

// MARK: - Icon Generator
/// Generates status icons programmatically for the menu bar
@MainActor
final class IconGenerator {

    // MARK: - Properties
    static let shared = IconGenerator()

    private init() {}

    // MARK: - Icon Size Constants
    private enum Size {
        static let menuBar: CGFloat = 18
        static let status: CGFloat = 8
    }

    // MARK: - Status Icon Generation

    /// Creates a colored status dot icon
    /// - Parameters:
    ///   - color: The fill color for the status dot
    ///   - size: The size of the icon
    /// - Returns: An NSImage with the status dot
    func createStatusIcon(color: NSColor, size: CGFloat = Size.status) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))

        color.setFill()
        path.fill()

        image.unlockFocus()
        image.isTemplate = false

        return image
    }

    /// Creates a status icon based on usage percentage
    /// - Parameter percentage: Current usage percentage (0-100)
    /// - Returns: An appropriately colored status icon
    func createStatusIcon(forPercentage percentage: Double) -> NSImage {
        let color: NSColor
        if percentage >= 50 {
            color = NSColor(Color.claudacity.safe)
        } else if percentage >= 30 {
            color = NSColor(Color.claudacity.caution)
        } else if percentage >= 10 {
            color = NSColor(Color.claudacity.warning)
        } else {
            color = NSColor(Color.claudacity.danger)
        }

        return createStatusIcon(color: color)
    }

    // MARK: - Menu Bar Icon Generation

    /// Creates a gauge-style menu bar icon
    /// - Parameter percentage: Current usage percentage (0-100)
    /// - Returns: A gauge icon showing the current level
    func createGaugeIcon(forPercentage percentage: Double) -> NSImage {
        let size = Size.menuBar
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()

        let center = NSPoint(x: size / 2, y: size / 2)
        let radius = (size - 4) / 2

        // 배경 원 투명 처리 (그리지 않음)

        // Progress arc
        let startAngle: CGFloat = 90
        let endAngle = startAngle - CGFloat(percentage / 100.0 * 360.0)

        let progressPath = NSBezierPath()
        progressPath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )

        // 프로그레스 색상: 시스템 라벨 색상 사용 (테마에 맞게 자동 조정)
        let progressColor = NSColor.labelColor

        progressColor.setStroke()
        progressPath.lineWidth = 2
        progressPath.lineCapStyle = .round
        progressPath.stroke()

        image.unlockFocus()
        image.isTemplate = false

        return image
    }

    /// Creates a battery-style menu bar icon
    /// - Parameter percentage: Current usage percentage (0-100)
    /// - Returns: A battery icon showing the current level
    func createBatteryIcon(forPercentage percentage: Double) -> NSImage {
        let width: CGFloat = 22
        let height: CGFloat = 12
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()

        // Battery outline
        let bodyRect = NSRect(x: 0, y: 1, width: width - 3, height: height - 2)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 2, yRadius: 2)
        NSColor.labelColor.setStroke()
        bodyPath.lineWidth = 1
        bodyPath.stroke()

        // Battery cap
        let capRect = NSRect(x: width - 3, y: 3, width: 2, height: height - 6)
        let capPath = NSBezierPath(roundedRect: capRect, xRadius: 1, yRadius: 1)
        NSColor.labelColor.setFill()
        capPath.fill()

        // Fill level
        let fillWidth = CGFloat(percentage / 100.0) * (bodyRect.width - 4)
        if fillWidth > 0 {
            let fillRect = NSRect(x: 2, y: 3, width: fillWidth, height: height - 6)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1, yRadius: 1)

            let fillColor: NSColor
            if percentage >= 50 {
                fillColor = NSColor(Color.claudacity.safe)
            } else if percentage >= 30 {
                fillColor = NSColor(Color.claudacity.caution)
            } else if percentage >= 10 {
                fillColor = NSColor(Color.claudacity.warning)
            } else {
                fillColor = NSColor(Color.claudacity.danger)
            }

            fillColor.setFill()
            fillPath.fill()
        }

        image.unlockFocus()
        image.isTemplate = false

        return image
    }
}
