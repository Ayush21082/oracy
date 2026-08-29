import SwiftUI
import UIKit
import QuartzCore

/// GPU confetti burst — shared by Completion and Profile highlight stories.
struct ConfettiCannonView: UIViewRepresentable {
    func makeUIView(context: Context) -> ConfettiEmitterView {
        let view = ConfettiEmitterView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            view.fire()
        }
        return view
    }

    func updateUIView(_ uiView: ConfettiEmitterView, context: Context) {}
}

final class ConfettiEmitterView: UIView {
    private var emitter: CAEmitterLayer?
    private static let cellImages: [CGImage] = makeCellImages()

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter?.frame = bounds
        emitter?.emitterPosition = CGPoint(x: bounds.midX, y: -12)
        emitter?.emitterSize = CGSize(width: bounds.width, height: 1)
    }

    func fire() {
        guard emitter == nil else { return }

        let layer = CAEmitterLayer()
        layer.emitterShape = .line
        layer.emitterMode = .outline
        layer.renderMode = .unordered
        layer.frame = bounds
        layer.emitterPosition = CGPoint(x: bounds.midX, y: -12)
        layer.emitterSize = CGSize(width: max(bounds.width, 1), height: 1)
        layer.beginTime = CACurrentMediaTime()

        let colors: [UIColor] = [
            UIColor(Theme.accent),
            UIColor(Theme.success),
            UIColor(Theme.warning),
            UIColor(red: 0.92, green: 0.78, blue: 0.55, alpha: 1),
            UIColor(red: 0.75, green: 0.55, blue: 0.70, alpha: 1),
            UIColor(red: 0.55, green: 0.72, blue: 0.85, alpha: 1)
        ]

        layer.emitterCells = zip(Self.cellImages, colors).map { image, color in
            let cell = CAEmitterCell()
            cell.contents = image
            cell.color = color.cgColor
            cell.birthRate = 28
            cell.lifetime = 3.2
            cell.lifetimeRange = 0.5
            cell.velocity = 220
            cell.velocityRange = 80
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 5
            cell.spin = 3.2
            cell.spinRange = 4
            cell.scale = 0.55
            cell.scaleRange = 0.25
            cell.yAcceleration = 280
            cell.xAcceleration = 12
            cell.alphaSpeed = -0.25
            cell.beginTime = 0
            cell.duration = 0.7
            return cell
        }

        self.layer.addSublayer(layer)
        emitter = layer

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.emitter?.birthRate = 0
            self?.emitter?.removeFromSuperlayer()
            self?.emitter = nil
        }
    }

    private static func makeCellImages() -> [CGImage] {
        let sizes: [CGSize] = [
            CGSize(width: 10, height: 14),
            CGSize(width: 8, height: 8),
            CGSize(width: 12, height: 7)
        ]
        return sizes.compactMap { size in
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { _ in
                UIColor.white.setFill()
                let path = UIBezierPath(
                    roundedRect: CGRect(origin: .zero, size: size),
                    cornerRadius: min(size.width, size.height) * 0.25
                )
                path.fill()
            }
            return image.cgImage
        }
    }
}
