import SwiftUI

/// The hero Dashboard element: a large animated circular health score with a
/// status word and caption in the center (Apple-style progress ring).
struct HealthScoreRing: View {
    let score: Int          // 0...100
    let word: String
    let caption: String
    var size: CGFloat = 200

    @State private var animatedFraction: Double = 0
    @State private var animatedScore: Int = 0
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { StatusColor.forScore(score) }
    private var fraction: Double { Double(min(max(score, 0), 100)) / 100 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.secondaryText.opacity(0.14), lineWidth: size * 0.035)

            Circle()
                .trim(from: 0, to: animatedFraction)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(word)
                    .font(.mcCaption.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("\(animatedScore)")
                    .font(.mcMetric(size * 0.34))
                    .foregroundStyle(AppColor.primaryText)
                    .contentTransition(.numericText())
                    .monospacedDigit()
                Text(caption)
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            .frame(width: size * 0.76)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("comp.ring.a11y", score, word))
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            countUp(to: score)
        }
        .onChange(of: score) { _, newValue in
            // Smooth transition only — digits cross-fade via numericText, the ring
            // eases. No distracting count-up-from-zero on every update.
            guard !reduceMotion else {
                animatedFraction = fraction
                animatedScore = newValue
                return
            }
            withAnimation(.easeInOut(duration: 0.6)) {
                animatedFraction = fraction
                animatedScore = newValue
            }
        }
    }

    /// One-time intro: ring sweeps in and the number counts up from zero.
    private func countUp(to newScore: Int) {
        guard !reduceMotion else {
            animatedFraction = fraction
            animatedScore = newScore
            return
        }
        withAnimation(.easeInOut(duration: 0.8)) { animatedFraction = fraction }
        withAnimation(.easeOut(duration: 0.6)) { animatedScore = newScore }
    }
}

#Preview {
    HStack(spacing: 40) {
        HealthScoreRing(score: 92, word: "Good", caption: "양호한 상태입니다")
        HealthScoreRing(score: 48, word: "Poor", caption: "정리가 필요합니다", size: 150)
    }
    .padding(40)
}
