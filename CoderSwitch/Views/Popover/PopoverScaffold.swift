import SwiftUI

/// Fixed header and footer around a scrolling body. The body grows with its content up to
/// `maxContentHeight`, then scrolls, so the popover only takes the space it needs.
struct PopoverScaffold<Header: View, Content: View, Footer: View>: View {
    static var width: CGFloat { 360 }
    static var maxContentHeight: CGFloat { 540 }

    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                content
                    .frame(width: Self.width, alignment: .leading)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        }
                    )
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: contentHeight == 0 ? 200 : min(contentHeight, Self.maxContentHeight))
            Divider()
            footer
        }
        .frame(width: Self.width)
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
