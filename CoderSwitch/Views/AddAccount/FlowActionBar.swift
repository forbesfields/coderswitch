import SwiftUI

/// Bottom bar shared by the add-account forms: an optional error and one primary button.
struct FlowActionBar: View {
    let primaryTitle: String
    var canSubmit = true
    var errorMessage: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Divider()
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
            HStack {
                Spacer()
                Button(primaryTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }
}
