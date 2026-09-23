import SwiftUI

/// The time beside the date, as digits or as a face.
///
/// Both are drawn from a date handed in rather than read from the clock, so the board decides how
/// often it moves — once a minute, with the date line it sits in.
/// What it's like outside, in the same breath as the time.
struct BoardTemperature: View {
    var size: CGFloat = 15
    @ObservedObject private var reader = BoardWeatherReader.shared

    var body: some View {
        Button {
            // Tapping means now: a reading that never arrived is the only reason anyone taps it.
            reader.refresh(force: true)
        } label: {
            if let weather = reader.weather {
                Label(weather.label(), systemImage: weather.symbol)
                    .foregroundStyle(TaskStripTheme.amber)
                    .accessibilityLabel("\(weather.label()) outside. Tap to read it again.")
            } else {
                // Switched on and nothing to show yet: better a dash that can be tapped than a
                // gap that looks like the setting did nothing.
                Label("—°", systemImage: reader.state == .refused ? "location.slash" : "thermometer.medium")
                    .foregroundStyle(TaskStripTheme.paper.opacity(0.4))
                    .accessibilityLabel(
                        reader.state == .refused
                            ? "No temperature: Task Strips can't see where you are"
                            : "Waiting for the temperature"
                    )
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: size, weight: .semibold, design: .monospaced))
        .help(reader.state == .refused ? "Location is off for Task Strips" : "The temperature where you are")
    }
}

struct BoardClock: View {
    let date: Date
    var style: BoardClockStyle = .digital
    /// The face's diameter when the clock has hands — big enough to read the hands at a glance,
    /// which is the whole point of a face.
    var faceSize: CGFloat = 48
    /// The digits' point size when it hasn't. Kept apart from the face: a face wants to be as
    /// big as the header allows, digits only as big as the words beside them.
    var digitSize: CGFloat = 15

    var body: some View {
        switch style {
        case .off:
            EmptyView()
        case .digital:
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: digitSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(TaskStripTheme.amber)
                .monospacedDigit()
                .accessibilityLabel("The time")
        case .analog:
            face
                .frame(width: faceSize, height: faceSize)
                .accessibilityLabel("The time, \(date.formatted(date: .omitted, time: .shortened))")
        }
    }

    private var face: some View {
        let hands = ClockFace.hands(at: date)
        return Canvas { context, canvasSize in
            let radius = min(canvasSize.width, canvasSize.height) / 2
            let centre = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            let inset = max(1, radius * 0.05)
            context.stroke(
                Path(ellipseIn: CGRect(x: centre.x - radius + inset, y: centre.y - radius + inset,
                                       width: (radius - inset) * 2, height: (radius - inset) * 2)),
                with: .color(TaskStripTheme.amber.opacity(0.7)),
                lineWidth: max(1.5, radius * 0.06)
            )

            // All twelve hours once there's room for them; below that they'd run together, so a
            // small face keeps the quarters only.
            let hours = radius >= 16 ? 12 : 4
            for mark in 0..<hours {
                let angle = Double(mark) / Double(hours) * 2 * .pi
                let isQuarter = mark % (hours / 4) == 0
                var tick = Path()
                tick.move(to: point(from: centre, angle: angle, distance: radius * (isQuarter ? 0.74 : 0.82)))
                tick.addLine(to: point(from: centre, angle: angle, distance: radius * 0.92))
                context.stroke(
                    tick,
                    with: .color(TaskStripTheme.amber.opacity(isQuarter ? 0.65 : 0.35)),
                    lineWidth: isQuarter ? 1.5 : 1
                )
            }

            // Hands thicken with the face, so a big clock doesn't read as a spider.
            hand(&context, from: centre, turn: hands.hour, length: radius * 0.5,
                 width: max(2.2, radius * 0.13), colour: TaskStripTheme.paper)
            hand(&context, from: centre, turn: hands.minute, length: radius * 0.8,
                 width: max(1.6, radius * 0.09), colour: TaskStripTheme.paper.opacity(0.85))

            let pin = max(1.5, radius * 0.09)
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
