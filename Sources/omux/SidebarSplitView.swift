import AppKit
import SwiftUI

enum SidebarSizing {
    static func preferred(_ width: Double) -> Double {
        width.isFinite && width > 0 ? min(420, max(280, width)) : 320
    }

    static func visible(preferred width: Double, available: Double) -> Double {
        min(preferred(width), max(280, available - 366))
    }
}

/// Only a divider drag changes the preference. Window resizing and SwiftUI content
/// updates may constrain the visible width, but never overwrite the user's choice.
struct SidebarSplitView<SidebarContent: View, MainContent: View>: View {
    @AppStorage(Prefs.sidebarWidth) private var savedWidth = 320.0
    @State private var dragStart: Double?
    @State private var draggedWidth: Double?
    private let sidebar: SidebarContent
    private let content: MainContent

    init(@ViewBuilder sidebar: () -> SidebarContent, @ViewBuilder content: () -> MainContent) {
        self.sidebar = sidebar()
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let width = SidebarSizing.visible(preferred: draggedWidth ?? savedWidth, available: geometry.size.width)
            HStack(spacing: 0) {
                sidebar.frame(width: width)
                Rectangle()
                    .fill(.clear)
                    .overlay { Rectangle().fill(.separator).frame(width: 1) }
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .onHover { over in
                        (over ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
                    }
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            if dragStart == nil { dragStart = width }
                            draggedWidth = SidebarSizing.visible(
                                preferred: max(280, (dragStart ?? width) + value.translation.width),
                                available: geometry.size.width)
                        }
                        .onEnded { _ in
                            if let draggedWidth { savedWidth = draggedWidth }
                            dragStart = nil
                            draggedWidth = nil
                        })
                    .accessibilityLabel("Sidebar width")
                    .accessibilityValue("\(Int(width)) points")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: savedWidth = SidebarSizing.preferred(width + 10)
                        case .decrement: savedWidth = SidebarSizing.preferred(width - 10)
                        @unknown default: break
                        }
                    }
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
