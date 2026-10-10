import AppKit
import SwiftUI

/// Keep the number and its unit as separate native controls with a shared text baseline.
struct CuePointField: NSViewRepresentable {
    @Binding var value: Double
    let unit: String
    let accessibilityLabel: String
    let spacing: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> PointFieldStack {
        let stack = PointFieldStack()
        stack.numberField.delegate = context.coordinator
        stack.numberField.setAccessibilityLabel(accessibilityLabel)
        stack.unitLabel.stringValue = unit
        stack.spacing = spacing
        stack.numberField.stringValue = Self.formatter.string(from: NSNumber(value: value)) ?? ""
        return stack
    }

    func updateNSView(_ stack: PointFieldStack, context: Context) {
        context.coordinator.value = $value
        stack.numberField.setAccessibilityLabel(accessibilityLabel)
        stack.unitLabel.stringValue = unit
        stack.spacing = spacing
        let editor = stack.numberField.currentEditor()
        if editor == nil || context.coordinator.renderedValue != value {
            let formatted = Self.formatter.string(from: NSNumber(value: value)) ?? ""
            if editor != nil, context.coordinator.renderedValue != value {
                editor?.string = formatted
            }
            if stack.numberField.stringValue != formatted {
                stack.numberField.stringValue = formatted
            }
        }
        context.coordinator.renderedValue = value
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PointFieldStack, context: Context) -> CGSize? {
        nsView.fittingSize
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var value: Binding<Double>
        var renderedValue: Double

        init(value: Binding<Double>) {
            self.value = value
            self.renderedValue = value.wrappedValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if let number = CuePointField.formatter.number(from: field.stringValue) {
                value.wrappedValue = number.doubleValue
            }
            field.stringValue = CuePointField.formatter.string(from: NSNumber(value: value.wrappedValue)) ?? ""
        }
    }
}

final class PointFieldStack: NSStackView {
    let numberField = NSTextField()
    let unitLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .firstBaseline
        numberField.isBezeled = false
        numberField.drawsBackground = false
        numberField.alignment = .right
        numberField.font = .systemFont(ofSize: NSFont.systemFontSize)
        numberField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        unitLabel.font = numberField.font
        unitLabel.textColor = .secondaryLabelColor
        addArrangedSubview(numberField)
        addArrangedSubview(unitLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
