import SwiftUI

/// A numeric duration editor: a text field you can type into, an attached
/// stepper for clicks, and arrow-key stepping while the field is focused.
/// Values are clamped to the range on commit; invalid input reverts.
struct DurationField: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    let step: Int
    var unit: String = "min"

    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .monospacedDigit()
                .focused($fieldFocused)
                .onSubmit(commit)
                .onKeyPress(.upArrow) {
                    increment()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    decrement()
                    return .handled
                }
                .onChange(of: fieldFocused) { _, isFocused in
                    if !isFocused { commit() }
                }

            Text(unit)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()

            Stepper("", value: $minutes, in: range, step: step)
                .labelsHidden()
                .fixedSize()
        }
        .onAppear { text = String(minutes) }
        .onChange(of: minutes) { _, newValue in
            if !fieldFocused { text = String(newValue) }
        }
        .onDisappear { commit() }
    }

    private func increment() {
        minutes = min(range.upperBound, minutes + step)
        text = String(minutes)
    }

    private func decrement() {
        minutes = max(range.lowerBound, minutes - step)
        text = String(minutes)
    }

    private func commit() {
        if let value = Int(text.trimmingCharacters(in: .whitespaces)) {
            minutes = min(range.upperBound, max(range.lowerBound, value))
        }
        text = String(minutes)
    }
}
