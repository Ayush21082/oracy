import SwiftUI

/// Typewriter or sequenced fade lines for conversational onboarding copy.
struct ConversationalText: View {
    enum Mode {
        case typewriter(charactersPerSecond: Double = 28)
        case sequenced(delay: TimeInterval = 0.55)
    }

    let lines: [String]
    var mode: Mode = .sequenced()
    var font: Font = Theme.fraunces(32, weight: .bold)
    var secondaryFont: Font = Theme.grotesk(16)
    var alignment: TextAlignment = .center
    var onComplete: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleLineCount = 0
    @State private var typedText = ""
    @State private var typewriterLineIndex = 0
    @State private var showCursor = true
    @State private var didComplete = false

    var body: some View {
        VStack(spacing: 14) {
            switch mode {
            case .typewriter:
                typewriterContent
            case .sequenced:
                sequencedContent
            }
        }
        .multilineTextAlignment(alignment)
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .task(id: lines.joined()) {
            await runReveal()
        }
        .onDisappear {
            didComplete = false
        }
    }

    private var typewriterContent: some View {
        VStack(alignment: alignment == .leading ? .leading : .center, spacing: 12) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let lineFont = index == 0 ? font : secondaryFont
                let color: Color = index == 0 ? Theme.textPrimary : Theme.textSecondary
                if index < typewriterLineIndex {
                    Text(line)
                        .font(lineFont)
                        .foregroundStyle(color)
                        .multilineTextAlignment(alignment)
                } else if index == typewriterLineIndex {
                    HStack(spacing: 0) {
                        Text(typedText)
                            .font(lineFont)
                            .foregroundStyle(color)
                        if !didComplete {
                            Text("|")
                                .font(lineFont)
                                .foregroundStyle(Theme.textSecondary.opacity(showCursor ? 0.7 : 0))
                        }
                        if alignment == .leading {
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.joined(separator: " "))
    }

    private var sequencedContent: some View {
        VStack(alignment: alignment == .leading ? .leading : .center, spacing: 12) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if index < visibleLineCount {
                    Text(line)
                        .font(index == 0 ? font : secondaryFont)
                        .foregroundStyle(index == 0 ? Theme.textPrimary : Theme.textSecondary)
                        .multilineTextAlignment(alignment)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.prefix(visibleLineCount).joined(separator: " "))
    }

    @MainActor
    private func runReveal() async {
        didComplete = false
        visibleLineCount = 0
        typedText = ""
        typewriterLineIndex = 0

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) {
                visibleLineCount = lines.count
                typewriterLineIndex = lines.count
                typedText = lines.last ?? ""
            }
            finish()
            return
        }

        switch mode {
        case .typewriter(let cps):
            showCursor = true
            let blink = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 480_000_000)
                    showCursor.toggle()
                }
            }
            defer { blink.cancel() }

            Haptics.prepare()
            for (index, line) in lines.enumerated() {
                typewriterLineIndex = index
                typedText = ""
                let interval = 1.0 / max(cps, 1)
                for ch in line {
                    typedText.append(ch)
                    Haptics.typewriterTick()
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
                Haptics.soft()
                try? await Task.sleep(nanoseconds: 320_000_000)
            }
            typewriterLineIndex = lines.count
            finish()

        case .sequenced(let delay):
            for i in 1...lines.count {
                withAnimation(.themeBounce) {
                    visibleLineCount = i
                }
                Haptics.soft()
                if i < lines.count {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
            finish()
        }
    }

    private func finish() {
        guard !didComplete else { return }
        didComplete = true
        onComplete?()
    }
}

/// Soft fade-in for CTAs after copy finishes — opacity only, no motion that shifts layout.
struct OnboardingReveal: ViewModifier {
    var isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.4), value: isVisible)
            .allowsHitTesting(isVisible)
    }
}

extension View {
    func onboardingReveal(_ visible: Bool) -> some View {
        modifier(OnboardingReveal(isVisible: visible))
    }
}
