import SwiftUI

/// The time beside the date, as digits or as a face.
///
/// Both are drawn from a date handed in rather than read from the clock, so the board decides how
/// often it moves — once a minute, with the date line it sits in.
struct BoardClock: View {
    let date: Date
    var style: BoardClockStyle = .digital
    /// The face's diameter; the digits follow it, so one number sizes the clock on any screen.
    var size: CGFloat = 30

    var body: some View {
        switch style {
        case .off:
            EmptyView()
        case .digital:
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: size * 0.46, weight: .semibold, design: .monospaced))
                .foregroundStyle(TaskStripTheme.amber)
                .monospacedDigit()
                .accessibilityLabel("The time")
        case .analog:
            face
                .frame(width: size, height: size)
                .accessibilityLabel("The time, \(date.formatted(date: .omitted, time: .shortened))")
        }
    }

    private var face: some View {
        let hands = ClockFace.hands(at: date)
        return Canvas { context, canvasSize in
            let radius = min(canvasSize.width, canvasSize.height) / 2
            let centre = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            context.stroke(
                Path(ellipseIn: CGRect(x: centre.x - radius + 1, y: centre.y - radius + 1,
                                       width: (radius - 1) * 2, height: (radius - 1) * 2)),
                with: .color(TaskStripTheme.amber.opacity(0.7)),
                lineWidth: 1.5
            )

            // Quarter marks only: at this size twelve ticks turn into a smudge.
            for quarter in 0..<4 {
                let angle = Double(quarter) / 4 * 2 * .pi
                var tick = Path()
                tick.move(to: point(from: centre, angle: angle, distance: radius * 0.78))
                tick.addLine(to: point(from: centre, angle: angle, distance: radius * 0.92))
                context.stroke(tick, with: .color(TaskStripTheme.amber.opacity(0.45)), lineWidth: 1)
            }

            hand(&context, from: centre, turn: hands.hour, length: radius * 0.5, width: 2.2,
                 colour: TaskStripTheme.paper)
            hand(&context, from: centre, turn: hands.minute, length: radius * 0.78, width: 1.6,
                 colour: TaskStripTheme.paper.opacity(0.85))

            let pin = radius * 0.1
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - pin, y: centre.y - pin, width: pin * 2, height: pin * 2)),
                with: .color(TaskStripTheme.amber)
            )
        }
    }

    private func hand(
        _ context: inout GraphicsContext, from centre: CGPoint, turn: Double,
        length: CGFloat, width: CGFloat, colour: Color
    ) {
        var path = Path()
        path.move(to: centre)
        path.addLine(to: point(from: centre, angle: turn * 2 * .pi, distance: length))
        context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    /// Angles are measured from twelve o'clock and run clockwise, which is a quarter turn off the
    /// way a screen measures them.
    private func point(from centre: CGPoint, angle: Double, distance: CGFloat) -> CGPoint {
        CGPoint(x: centre.x + distance * sin(angle), y: centre.y - distance * cos(angle))
    }
}
