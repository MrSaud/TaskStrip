import SwiftUI

/// The paper, drawn over the page and under whatever is drawn next.
///
/// Over, not under: a page is a PNG of cream paper with the strokes already on it, so a tint has
/// to be multiplied over that image to colour the paper without losing the ink, and the rules are
/// printed on top the way they are on a real pad — the ink still goes over them, since strokes
/// drawn from here on are drawn above this.
struct SketchPaperLayer: View {
    let paper: SketchPaper
    let size: CGSize

    var body: some View {
        ZStack {
            if let tint = paper.tint {
                Color(red: tint.red, green: tint.green, blue: tint.blue)
                    .blendMode(.multiply)
            }
            rules
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private var rules: some View {
        Canvas { context, canvasSize in
            // The faint blue a ruled pad is actually printed in.
            let colour = Color(red: 0.16, green: 0.26, blue: 0.42).opacity(paper.ruleOpacity)

            for y in paper.lineOffsets(forHeight: canvasSize.height) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: canvasSize.width, y: y))
                context.stroke(line, with: .color(colour), lineWidth: 1)
            }

            let grid = paper.gridOffsets(forSize: canvasSize)
            if case .dots = paper.ruling {
                let radius: CGFloat = 1.1
                for x in grid.columns {
                    for y in grid.rows {
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                   width: radius * 2, height: radius * 2)),
                            with: .color(colour)
                        )
                    }
                }
            } else {
                for x in grid.columns {
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    context.stroke(line, with: .color(colour), lineWidth: 1)
                }
                for y in grid.rows {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    context.stroke(line, with: .color(colour), lineWidth: 1)
                }
            }
        }
    }
}

/// The paper this note is on, as a menu of samples. Each one shows what it does rather than
/// naming a colour the person then has to picture.
struct SketchPaperPicker: View {
    @Binding var paper: SketchPaper

    var body: some View {
        Menu {
            Picker("Paper", selection: $paper) {
                ForEach(SketchPaper.allCases) { candidate in
                    Text(candidate.title).tag(candidate)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Paper: \(paper.title)", systemImage: "doc.plaintext")
        }
    }
}
