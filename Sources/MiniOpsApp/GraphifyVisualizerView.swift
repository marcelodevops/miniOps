import SwiftUI
import AppKit
import MiniOpsCore

public struct GraphifyVisualizerView: View {
    public let graphData: GraphifyData?
    public let onSelectFile: (String) -> Void
    public let onRefresh: () -> Void

    @State private var searchKeyword: String = ""
    @State private var selectedCommunity: Int? = nil

    public init(graphData: GraphifyData?, onSelectFile: @escaping (String) -> Void, onRefresh: @escaping () -> Void) {
        self.graphData = graphData
        self.onSelectFile = onSelectFile
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "circle.hexagongrid")
                    .foregroundColor(.accentColor)
                Text("Knowledge Graph (Graphify)")
                    .font(.system(size: 12, weight: .bold))

                Spacer()

                if let g = graphData {
                    if let report = g.reportPath {
                        Button("Report") {
                            onSelectFile(report)
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .help("View GRAPH_REPORT.md")
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

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            guard let graph = graphData else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "network")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No Graphify Knowledge Graph Found")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Run 'graphify' or create graphify-out/graph.json to visualize architecture and god nodes.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                return AnyView(EmptyView())
            }

            // Stats bar
            HStack(spacing: 16) {
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

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HSplitView {
                // Left: Top God Nodes
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 10))
                        Text("Top God Nodes (Core Abstractions)")
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    let godNodes = GraphifyScanner.shared.computeGodNodes(data: graph, limit: 12)
                    List(godNodes, id: \.node.id) { item in
                        HStack(spacing: 6) {
                            Text("\(item.degree)")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                                .foregroundColor(.orange)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.node.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Text(item.node.communityName)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if let sf = item.node.sourceFile {
                                Button("Open") {
                                    onSelectFile(sf)
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 350)

                // Right: Communities & Node Search
                VStack(alignment: .leading, spacing: 0) {
                    // Filter bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search nodes by label or file...", text: $searchKeyword)
                            .textFieldStyle(.roundedBorder)

                        Picker("Community", selection: $selectedCommunity) {
                            Text("All Communities").tag(Int?.none)
                            ForEach(graph.communities, id: \.self) { c in
                                Text("Community \(c)").tag(Int?.some(c))
                            }
                        }
                        .frame(maxWidth: 140)
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    let filtered = graph.nodes.filter { n in
                        if let comm = selectedCommunity, n.community != comm {
                            return false
                        }
                        if !searchKeyword.isEmpty {
                            return n.label.localizedCaseInsensitiveContains(searchKeyword) || (n.sourceFile?.localizedCaseInsensitiveContains(searchKeyword) == true)
                        }
                        return true
                    }

                    List(filtered) { node in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(communityColor(node.community))
                                .frame(width: 7, height: 7)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.label)
                                    .font(.system(size: 11, weight: .medium))
                                if let sf = node.sourceFile {
                                    Text(sf)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Text(node.communityName)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)

                            if let sf = node.sourceFile {
                                Button("Jump") {
                                    onSelectFile(sf)
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
                .frame(minWidth: 280, maxWidth: .infinity)
            }
        }
    }

    private func communityColor(_ c: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .yellow]
        return colors[abs(c) % colors.count]
    }
}
