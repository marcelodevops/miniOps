import SwiftUI
import AppKit
import MiniOpsCore

public struct GraphifyVisualizerView: View {
    @ObservedObject public var viewModel: WorkspaceViewModel

    @State private var nodePositions: [String: CGPoint] = [:]
    @State private var nodeDegrees: [String: Int] = [:]
    @State private var selectedNodeId: String? = nil
    @State private var hoveredNodeId: String? = nil
    @State private var neighborhoodDepth: Int = 1
    @State private var searchKeyword: String = ""
    @State private var panOffset: CGSize = .zero
    @State private var currentDragTranslation: CGSize = .zero
    @State private var zoomScale: CGFloat = 1.0
    @State private var pinchBaseScale: CGFloat = 1.0
    @State private var draggingNodeId: String? = nil
    @State private var isPanning: Bool = false
    @State private var isInspectorPresented: Bool = true
    @State private var canvasSize: CGSize = CGSize(width: 800, height: 600)

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            toolbarView
            Divider()

            if let graph = viewModel.graphData, !graph.nodes.isEmpty {
                // Legend and Stats bar
                legendBar(graph: graph)
                Divider()

                HSplitView {
                    // Canvas View
                    ZStack {
                        Color(NSColor.textBackgroundColor)

                        GeometryReader { geo in
                            Canvas { context, size in
                                drawGraph(context: context, size: size, graph: graph)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onAppear {
                                self.canvasSize = geo.size
                                updateLayout(graph: graph, size: geo.size)
                            }
                            .onChange(of: geo.size) { newSize in
                                self.canvasSize = newSize
                            }
                            .onChange(of: viewModel.graphData?.nodes.count) { _ in
                                if let g = viewModel.graphData {
                                    updateLayout(graph: g, size: geo.size)
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { val in
                                        handleDragChanged(val)
                                    }
                                    .onEnded { val in
                                        handleDragEnded(val)
                                    }
                            )
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { scale in
                                        let factor = scale / pinchBaseScale
                                        zoomScale = min(max(zoomScale * factor, 0.2), 4.0)
                                        pinchBaseScale = scale
                                    }
                                    .onEnded { _ in
                                        pinchBaseScale = 1.0
                                    }
                            )
                        }

                        // Floating Zoom & Reset Overlay
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                HStack(spacing: 4) {
                                    Button(action: zoomOut) {
                                        Image(systemName: "minus")
                                            .font(.system(size: 11, weight: .bold))
                                            .frame(width: 22, height: 22)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Zoom Out")

                                    Text("\(Int(zoomScale * 100))%")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 36)

                                    Button(action: zoomIn) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 11, weight: .bold))
                                            .frame(width: 22, height: 22)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Zoom In")

                                    Divider().frame(height: 12)

                                    Button("Fit", action: fitToScreen)
                                        .buttonStyle(.plain)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .help("Fit Graph to Window")
                                }
                                .padding(5)
                                .background(.regularMaterial)
                                .cornerRadius(8)
                                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                                .padding(12)
                            }
                        }
                    }
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)

                    // Right Side: Node Inspector / Overview Panel
                    if isInspectorPresented {
                        inspectorPanel(graph: graph)
                            .frame(minWidth: 260, idealWidth: 310, maxWidth: 420)
                    }
                }
            } else {
                emptyGraphView
            }
        }
        .onAppear {
            if viewModel.availableGraphDatasets.isEmpty {
                viewModel.refreshGraph()
            }
        }
    }

    // MARK: - Toolbar
    private var toolbarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid")
                .foregroundColor(.accentColor)
                .font(.system(size: 13))

            // Dataset Selector
            if !viewModel.availableGraphDatasets.isEmpty {
                Picker("Dataset", selection: Binding(
                    get: { viewModel.selectedGraphDatasetKey ?? viewModel.availableGraphDatasets.first?.key ?? "" },
                    set: { key in
                        viewModel.selectGraphDataset(key: key)
                        selectedNodeId = nil
                    }
                )) {
                    ForEach(viewModel.availableGraphDatasets) { ds in
                        Text(ds.label).tag(ds.key)
                    }
                }
                .frame(maxWidth: 190)
            }

            // Search Field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
                TextField("Search node label or file…", text: $searchKeyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit {
                        performSearch()
                    }
                if !searchKeyword.isEmpty {
                    Button(action: {
                        searchKeyword = ""
                        selectedNodeId = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 240)

            // Neighborhood Focus Depth
            Picker("Depth", selection: $neighborhoodDepth) {
                Text("1 hop").tag(1)
                Text("2 hops").tag(2)
                Text("3 hops").tag(3)
            }
            .frame(maxWidth: 95)
            .help("Neighborhood expansion depth (1–3 hops)")

            if selectedNodeId != nil {
                Button(action: {
                    selectedNodeId = nil
                }) {
                    Text("Clear Focus")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            // Artifact links
            if let g = viewModel.graphData {
                if let report = g.reportPath {
                    Button("Report") {
                        viewModel.selectFile(report)
                        viewModel.selectCenterTab(.editor)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .help("Open GRAPH_REPORT.md in editor")
                }

                if let html = g.htmlPath {
                    Button("HTML") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: html))
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .help("Open interactive graph.html in default browser")
                }
            }

            // Refresh
            Button(action: {
                viewModel.refreshGraph()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Refresh Knowledge Graph")

            // Inspector toggle
            Button(action: { isInspectorPresented.toggle() }) {
                Image(systemName: isInspectorPresented ? "sidebar.right" : "sidebar.right")
                    .foregroundColor(isInspectorPresented ? .accentColor : .secondary)
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Legend Bar
    private func legendBar(graph: GraphifyData) -> some View {
        HStack(spacing: 12) {
            // Stats
            HStack(spacing: 4) {
                Text("\(graph.nodes.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Text("Nodes")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                Text("\(graph.links.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Text("Links")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                Text("\(graph.communities.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Text("Communities")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider().frame(height: 12)

            // Community Swatches
            let commMap = Dictionary(grouping: graph.nodes, by: \.community)
            let topCommunities = commMap.keys.sorted().prefix(5)
            HStack(spacing: 8) {
                ForEach(Array(topCommunities), id: \.self) { commId in
                    let name = commMap[commId]?.first?.communityName ?? "Community \(commId)"
                    HStack(spacing: 3) {
                        Circle()
                            .fill(communityColor(commId))
                            .frame(width: 7, height: 7)
                        Text(name)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if let selId = selectedNodeId, let selNode = graph.nodes.first(where: { $0.id == selId }) {
                let neighborhood = GraphifyScanner.shared.computeNeighborhood(from: selId, depth: neighborhoodDepth, links: graph.links)
                HStack(spacing: 4) {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    Text("Focus: \(selNode.label)")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Text("(\(neighborhood.count) nodes)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Canvas Drawing
    private func drawGraph(context: GraphicsContext, size: CGSize, graph: GraphifyData) {
        let focusedIds: Set<String>? = selectedNodeId.map {
            GraphifyScanner.shared.computeNeighborhood(from: $0, depth: neighborhoodDepth, links: graph.links)
        }

        let effectivePanX = panOffset.width + currentDragTranslation.width
        let effectivePanY = panOffset.height + currentDragTranslation.height

        func screenPoint(for worldPt: CGPoint) -> CGPoint {
            CGPoint(
                x: worldPt.x * zoomScale + effectivePanX,
                y: worldPt.y * zoomScale + effectivePanY
            )
        }

        // 1. Draw Links
        for link in graph.links {
            guard let posA = nodePositions[link.source], let posB = nodePositions[link.target] else { continue }
            let ptA = screenPoint(for: posA)
            let ptB = screenPoint(for: posB)

            let isHighlighted: Bool
            if let focused = focusedIds {
                isHighlighted = focused.contains(link.source) && focused.contains(link.target)
            } else {
                isHighlighted = true
            }

            let alpha: Double = isHighlighted ? 0.65 : 0.07
            let lineWidth: CGFloat = isHighlighted ? 1.4 : 0.8

            var path = Path()
            path.move(to: ptA)
            path.addLine(to: ptB)
            context.stroke(path, with: .color(Color(NSColor.separatorColor).opacity(alpha)), lineWidth: lineWidth)
        }

        // 2. Draw Nodes
        for node in graph.nodes {
            guard let pos = nodePositions[node.id] else { continue }
            let screenPt = screenPoint(for: pos)

            let deg = nodeDegrees[node.id, default: 0]
            let baseRadius = 4.0 + min(CGFloat(deg), 8.0)
            let radius = baseRadius * max(zoomScale, 0.7)

            let isHighlighted: Bool
            if let focused = focusedIds {
                isHighlighted = focused.contains(node.id)
            } else {
                isHighlighted = true
            }

            let isSelected = (node.id == selectedNodeId)
            let isHovered = (node.id == hoveredNodeId)
            let nodeAlpha: Double = isHighlighted ? 1.0 : 0.12

            let circleRect = CGRect(
                x: screenPt.x - radius,
                y: screenPt.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            // Fill circle with community color
            context.fill(Path(ellipseIn: circleRect), with: .color(communityColor(node.community).opacity(nodeAlpha)))

            // Stroke circle (accent if selected)
            if isSelected {
                let ringRect = circleRect.insetBy(dx: -3, dy: -3)
                context.stroke(Path(ellipseIn: ringRect), with: .color(Color.accentColor), lineWidth: 2.5)
                context.stroke(Path(ellipseIn: circleRect), with: .color(Color(NSColor.textBackgroundColor)), lineWidth: 1.5)
            } else {
                context.stroke(Path(ellipseIn: circleRect), with: .color(Color(NSColor.textBackgroundColor).opacity(nodeAlpha)), lineWidth: 1.0)
            }

            // Labels for significant nodes or hovered/selected
            if isSelected || isHovered || (deg >= 4 && isHighlighted && zoomScale >= 0.5) || zoomScale >= 1.5 {
                let labelText = node.label.count > 24 ? String(node.label.prefix(22)) + "…" : node.label
                let text = Text(labelText)
                    .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                    .foregroundColor(Color.primary.opacity(nodeAlpha))

                context.draw(
                    text,
                    at: CGPoint(x: screenPt.x, y: screenPt.y - radius - 8),
                    anchor: .center
                )
            }
        }
    }

    // MARK: - Drag and Tap Handling
    private func handleDragChanged(_ value: DragGesture.Value) {
        let startPt = value.startLocation
        let currentPt = value.location

        if draggingNodeId == nil && !isPanning {
            if let hit = hitTestNode(at: startPt) {
                draggingNodeId = hit.id
            } else {
                isPanning = true
            }
        }

        if let dragId = draggingNodeId {
            let worldPt = screenToWorld(currentPt)
            nodePositions[dragId] = worldPt
        } else if isPanning {
            currentDragTranslation = value.translation
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if draggingNodeId != nil {
            draggingNodeId = nil
        } else {
            let dist = hypot(value.translation.width, value.translation.height)
            if dist < 4.0 {
                // Tap gesture
                if let hit = hitTestNode(at: value.startLocation) {
                    selectedNodeId = hit.id
                    isInspectorPresented = true
                } else {
                    selectedNodeId = nil
                }
            } else {
                panOffset.width += value.translation.width
                panOffset.height += value.translation.height
            }
            currentDragTranslation = .zero
            isPanning = false
        }
    }

    private func hitTestNode(at screenPt: CGPoint) -> GraphifyNode? {
        guard let graph = viewModel.graphData else { return nil }
        let effectivePanX = panOffset.width + currentDragTranslation.width
        let effectivePanY = panOffset.height + currentDragTranslation.height

        for node in graph.nodes.reversed() {
            guard let pos = nodePositions[node.id] else { continue }
            let nodeScreenX = pos.x * zoomScale + effectivePanX
            let nodeScreenY = pos.y * zoomScale + effectivePanY

            let deg = nodeDegrees[node.id, default: 0]
            let hitRadius = max((4.0 + min(CGFloat(deg), 8.0)) * zoomScale + 6.0, 14.0)

            let dx = screenPt.x - nodeScreenX
            let dy = screenPt.y - nodeScreenY
            if dx * dx + dy * dy <= hitRadius * hitRadius {
                return node
            }
        }
        return nil
    }

    private func screenToWorld(_ pt: CGPoint) -> CGPoint {
        let effectivePanX = panOffset.width + currentDragTranslation.width
        let effectivePanY = panOffset.height + currentDragTranslation.height
        return CGPoint(
            x: (pt.x - effectivePanX) / zoomScale,
            y: (pt.y - effectivePanY) / zoomScale
        )
    }

    // MARK: - Search & Navigation
    private func performSearch() {
        guard let graph = viewModel.graphData, !graph.nodes.isEmpty else { return }
        let query = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            selectedNodeId = nil
            return
        }

        let match = graph.nodes.first(where: { $0.label.lowercased() == query })
            ?? graph.nodes.first(where: { $0.label.lowercased().contains(query) })
            ?? graph.nodes.first(where: { $0.sourceFile?.lowercased().contains(query) == true })

        if let found = match {
            selectedNodeId = found.id
            isInspectorPresented = true
            centerOnNode(found.id)
        }
    }

    private func centerOnNode(_ nodeId: String) {
        guard let pos = nodePositions[nodeId] else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            panOffset = CGSize(
                width: canvasSize.width / 2.0 - pos.x * zoomScale,
                height: canvasSize.height / 2.0 - pos.y * zoomScale
            )
            currentDragTranslation = .zero
        }
    }

    private func fitToScreen() {
        guard let graph = viewModel.graphData, !graph.nodes.isEmpty, !nodePositions.isEmpty else { return }
        let xs = nodePositions.values.map(\.x)
        let ys = nodePositions.values.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 100
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 100

        let graphWidth = max(maxX - minX, 60)
        let graphHeight = max(maxY - minY, 60)
        let padding: CGFloat = 80.0

        let availableWidth = max(canvasSize.width - padding * 2, 100)
        let availableHeight = max(canvasSize.height - padding * 2, 100)

        let scaleX = availableWidth / graphWidth
        let scaleY = availableHeight / graphHeight
        let newScale = min(max(min(scaleX, scaleY), 0.25), 2.5)

        let centerX = (minX + maxX) / 2.0
        let centerY = (minY + maxY) / 2.0

        withAnimation(.easeInOut(duration: 0.25)) {
            zoomScale = newScale
            panOffset = CGSize(
                width: canvasSize.width / 2.0 - centerX * newScale,
                height: canvasSize.height / 2.0 - centerY * newScale
            )
            currentDragTranslation = .zero
        }
    }

    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = min(zoomScale * 1.25, 4.0)
        }
    }

    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = max(zoomScale * 0.8, 0.2)
        }
    }

    private func updateLayout(graph: GraphifyData, size: CGSize) {
        let degrees = GraphifyScanner.shared.computeDegrees(data: graph)
        self.nodeDegrees = degrees

        let layout = GraphifyScanner.shared.computeLayout(
            nodes: graph.nodes,
            links: graph.links,
            width: max(Double(size.width), 600),
            height: max(Double(size.height), 500)
        )

        var converted: [String: CGPoint] = [:]
        for (id, pos) in layout {
            converted[id] = CGPoint(x: pos.x, y: pos.y)
        }
        self.nodePositions = converted
        fitToScreen()
    }

    // MARK: - Inspector Panel
    private func inspectorPanel(graph: GraphifyData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selId = selectedNodeId, let node = graph.nodes.first(where: { $0.id == selId }) {
                nodeDetailView(node: node, graph: graph)
            } else {
                overviewInspectorView(graph: graph)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func nodeDetailView(node: GraphifyNode, graph: GraphifyData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.label)
                            .font(.system(size: 14, weight: .bold))
                            .textSelection(.enabled)
                        Text(node.fileType)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { selectedNodeId = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                }

                Divider()

                // Metadata Rows
                VStack(alignment: .leading, spacing: 8) {
                    // Community
                    HStack {
                        Text("Community")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(communityColor(node.community))
                                .frame(width: 10, height: 10)
                            Text(node.communityName)
                                .font(.system(size: 11))
                        }
                    }

                    // Degree
                    HStack {
                        Text("Degree")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Text("\(nodeDegrees[node.id, default: 0]) connections")
                            .font(.system(size: 11, design: .monospaced))
                    }

                    // Source File
                    if let sf = node.sourceFile {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Source")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            HStack {
                                Text(sf + (node.sourceLocation.map { " :\($0)" } ?? ""))
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(2)
                                    .foregroundColor(.primary)
                                Spacer()
                                Button("Open") {
                                    viewModel.selectFile(sf)
                                    viewModel.selectCenterTab(.editor)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                Divider()

                // Quick Context Actions (Tickets / Repos)
                let currentKey = viewModel.selectedGraphDatasetKey ?? ""
                if currentKey.contains("tickets") {
                    if let ticket = viewModel.tickets.first(where: { $0.key == node.label || $0.key == node.id }) {
                        Button(action: {
                            viewModel.selectTicket(ticket)
                        }) {
                            Label("Open Ticket \(ticket.key)", systemImage: "ticket.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                // Connections
                let conns = graph.links.compactMap { link -> (neighbor: GraphifyNode, relation: String)? in
                    if link.source == node.id {
                        if let targetNode = graph.nodes.first(where: { $0.id == link.target }) {
                            return (targetNode, link.relation.isEmpty ? "connects" : link.relation)
                        }
                    } else if link.target == node.id {
                        if let sourceNode = graph.nodes.first(where: { $0.id == link.source }) {
                            return (sourceNode, link.relation.isEmpty ? "connects" : link.relation)
                        }
                    }
                    return nil
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Connections (\(conns.count))")
                        .font(.system(size: 11, weight: .bold))

                    if conns.isEmpty {
                        Text("No direct links.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(Array(conns.prefix(30).enumerated()), id: \.offset) { _, item in
                                Button(action: {
                                    selectedNodeId = item.neighbor.id
                                    centerOnNode(item.neighbor.id)
                                }) {
                                    HStack(spacing: 6) {
                                        Text(item.relation)
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.12))
                                            .foregroundColor(.accentColor)
                                            .cornerRadius(3)

                                        Text(item.neighbor.label)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                            .foregroundColor(.primary)

                                        Spacer()
                                        Image(systemName: "arrow.forward")
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 6)
                                    .background(Color(NSColor.windowBackgroundColor))
                                    .cornerRadius(5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(14)
        }
    }

    private func overviewInspectorView(graph: GraphifyData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 11))
                Text("Top God Nodes")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            let godNodes = GraphifyScanner.shared.computeGodNodes(data: graph, limit: 14)
            List(godNodes, id: \.node.id) { item in
                Button(action: {
                    selectedNodeId = item.node.id
                    centerOnNode(item.node.id)
                }) {
                    HStack(spacing: 6) {
                        Text("\(item.degree)")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundColor(.orange)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.node.label)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .foregroundColor(.primary)
                            Text(item.node.communityName)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "scope")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Empty State
    private var emptyGraphView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "network")
                .font(.system(size: 38))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No Graphify Knowledge Graph Found")
                .font(.system(size: 14, weight: .semibold))
            Text("Run 'graphify' or place graphify-out/graph.json in this workspace to explore the architecture graph.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button("Rescan Graph Datasets") {
                viewModel.refreshGraph()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func communityColor(_ c: Int) -> Color {
        let colors: [Color] = [
            .blue, .purple, .orange, .green, .teal, .indigo, .pink, .mint, .cyan, .yellow
        ]
        return colors[abs(c) % colors.count]
    }
}
