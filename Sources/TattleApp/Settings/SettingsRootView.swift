import AppKit
import SwiftUI

enum SettingsTabID: CaseIterable, Hashable {
    case sound, general, behavior, browsers, permissions, about

    /// The sidebar's visual groups, in order. Flattened this must equal `allCases`
    /// (every tab exactly once). The header-less Sections draw the gaps.
    static let sections: [[SettingsTabID]] = [
        [.sound],
        [.general, .behavior],
        [.browsers, .permissions],
        [.about],
    ]

    var title: String {
        switch self {
        case .sound: "Sound"
        case .general: "General"
        case .behavior: "Behavior"
        case .browsers: "Browsers"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .sound: "speaker.wave.2"
        case .general: "gearshape"
        case .behavior: "slider.horizontal.3"
        case .browsers: "globe"
        case .permissions: "hand.raised"
        case .about: "info.circle"
        }
    }
    /// Panes that own user-tunable settings get a "Reset to Defaults" button.
    var isResettable: Bool { self == .general || self == .behavior }
}

/// Sidebar + detail, laid out exactly like Continuo's Settings: a native
/// `NavigationSplitView` pinned to `.all` (sidebar can't collapse), grouped
/// sidebar sections, a chromeless window with a tall transparent titlebar, a
/// sticky pane title above the grouped form, and an opaque content ground.
/// The window's size and minimum are owned by AppKit (`SettingsWindowPresenter`);
/// SwiftUI just fills it. An ideal size here would re-apply on every re-layout.
struct SettingsRootView: View {
    @Bindable var model: SettingsModel
    var noise: NoiseModel? = nil
    @State private var selection: SettingsTabID

    init(model: SettingsModel, noise: NoiseModel? = nil, selection: SettingsTabID = .sound) {
        self.model = model
        self.noise = noise
        _selection = State(initialValue: selection)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: sidebarSelection) {
                ForEach(SettingsTabID.sections, id: \.self) { group in
                    Section {
                        ForEach(group, id: \.self) { tab in
                            Label(tab.title, systemImage: tab.symbol).tag(tab)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(275)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Pull the content up under the tall titlebar so the title sits level
                // with the traffic lights instead of below the toolbar's inset.
                .ignoresSafeArea(.container, edges: .top)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChromelessWindow(showsMinimizeZoom: true, tallTitlebar: true))
        // `.navigationSplitViewColumnWidth` is ignored on macOS 26, so also pin the
        // sidebar with a width constraint, the same way Continuo does.
        .background(SidebarWidthLock(width: 240))
    }

    /// `List` selection is optional; ignore nil so a row can't be deselected.
    private var sidebarSelection: Binding<SettingsTabID?> {
        Binding(get: { selection }, set: { if let new = $0 { selection = new } })
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sticky pane title, pinned above the scrolling form (not in the titlebar).
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(selection.title)
                    .font(.system(size: 15, weight: .medium))
                Spacer(minLength: 8)
                if selection.isResettable {
                    Button("Reset to Defaults") { reset() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)     // clear the traffic lights above
            .padding(.bottom, 10)
            // Opaque strip above the form so scrolling content is occluded by the
            // header instead of drawing over the title.
            .background(Color(nsColor: .windowBackgroundColor))
            .zIndex(1)

            paneContent
        }
        // Solid content ground (System Settings look): the sidebar keeps its glass, the
        // content is an opaque window colour so grouped cards read as solid surfaces.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var paneContent: some View {
        switch selection {
        case .sound: SoundTab(noise: noise)
        case .general: GeneralTab(model: model)
        case .behavior: BehaviorTab(model: model)
        case .browsers: BrowsersTab(model: model)
        case .permissions: PermissionsTab()
        case .about: AboutTab()
        }
    }

    private func reset() {
        switch selection {
        case .general: model.resetGeneral()
        case .behavior: model.resetBehavior()
        default: break
        }
    }
}

/// Pins the sidebar column to a fixed width by constraining the split view's first
/// arranged subview directly, retrying while the view tree is built.
private struct SidebarWidthLock: NSViewRepresentable {
    let width: CGFloat

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        schedule(from: v)
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { schedule(from: nsView) }

    private func schedule(from view: NSView) {
        for tick in 0...6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30 * tick)) { [weak view] in
                guard let view else { return }
                apply(from: view)
            }
        }
    }

    @MainActor private func apply(from view: NSView) {
        guard let split = Self.firstSplitView(in: view.window?.contentView),
              let sidebar = split.arrangedSubviews.first else { return }
        for c in sidebar.constraints where c.identifier == "tattleSidebarWidthLock" { c.isActive = false }
        let c = sidebar.widthAnchor.constraint(equalToConstant: width)
        c.identifier = "tattleSidebarWidthLock"
        c.priority = .required
        c.isActive = true
    }

    @MainActor private static func firstSplitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let s = view as? NSSplitView { return s }
        for sub in view.subviews { if let s = firstSplitView(in: sub) { return s } }
        return nil
    }
}
