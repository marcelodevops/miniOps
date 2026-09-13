import Foundation

public final class GraphifyScanner: @unchecked Sendable {
    public static let shared = GraphifyScanner()

    public init() {}

    public func discoverDatasets(workspacePath: String, repositories: [RepoInfo] = []) -> [GraphDatasetChoice] {
        var datasets: [GraphDatasetChoice] = []
        var seenDirs = Set<String>()

        func checkDir(_ dirURL: URL, key: String, label: String, repoPath: String? = nil) {
            let stdPath = dirURL.standardized.path
            guard !seenDirs.contains(stdPath) else { return }
            let jsonURL = dirURL.appendingPathComponent("graph.json")
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                seenDirs.insert(stdPath)
                datasets.append(GraphDatasetChoice(
                    key: key,
                    label: label,
                    directoryPath: stdPath,
                    repoPath: repoPath
                ))
            }
        }

        let wsURL = URL(fileURLWithPath: (workspacePath as NSString).expandingTildeInPath)
        checkDir(wsURL.appendingPathComponent("graphify-out"), key: "workspace", label: "Workspace Graph")
        checkDir(wsURL.appendingPathComponent(".graphify"), key: "workspace-hidden", label: "Workspace Graph (.graphify)")
        checkDir(wsURL.appendingPathComponent("tickets").appendingPathComponent("graphify-out"), key: "tickets", label: "Tickets Graph")
        checkDir(wsURL.appendingPathComponent("tickets").appendingPathComponent(".graphify"), key: "tickets-hidden", label: "Tickets Graph (.graphify)")

        let duplicateNames = Set(
            Dictionary(grouping: repositories, by: \.name)
                .filter { $0.value.count > 1 }
                .map(\.key)
        )

        for repo in repositories {
            let repoURL = URL(fileURLWithPath: (repo.path as NSString).expandingTildeInPath)
            let canonicalRepoPath = repoURL.standardized.path

            let displayLabel: String
            if duplicateNames.contains(repo.name) {
                let parentName = repoURL.deletingLastPathComponent().lastPathComponent
                displayLabel = "\(repo.name) (\(parentName))"
            } else {
                displayLabel = repo.name
            }

            checkDir(
                repoURL.appendingPathComponent("graphify-out"),
                key: "repo:\(canonicalRepoPath)",
                label: "\(displayLabel) Graph",
                repoPath: repo.path
            )
            checkDir(
                repoURL.appendingPathComponent(".graphify"),
                key: "repo:\(canonicalRepoPath):hidden",
                label: "\(displayLabel) Graph (.graphify)",
                repoPath: repo.path
            )
        }

        return datasets
    }

    public func loadGraph(from dir: URL) -> GraphifyData? {
        let jsonURL = dir.appendingPathComponent("graph.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let reportURL = dir.appendingPathComponent("GRAPH_REPORT.md")
        let htmlURL = dir.appendingPathComponent("graph.html")
        let reportPath = FileManager.default.fileExists(atPath: reportURL.path) ? reportURL.path : nil
        let htmlPath = FileManager.default.fileExists(atPath: htmlURL.path) ? htmlURL.path : nil

        var nodes: [GraphifyNode] = []
        if let rawNodes = json["nodes"] as? [[String: Any]] {
            for item in rawNodes {
                guard let id = item["id"] as? String else { continue }
                let label = item["label"] as? String ?? item["norm_label"] as? String ?? id
                let comm = item["community"] as? Int ?? 0
                let commName = item["community_name"] as? String ?? "Community \(comm)"
                let fType = item["file_type"] as? String ?? "unknown"
                let srcFile = item["source_file"] as? String
                let srcLoc = item["source_location"] as? String

                nodes.append(GraphifyNode(
                    id: id,
                    label: label,
                    community: comm,
                    communityName: commName,
                    fileType: fType,
                    sourceFile: srcFile,
                    sourceLocation: srcLoc
                ))
            }
        }

        let nodeIDs = Set(nodes.map { $0.id })
        var links: [GraphifyLink] = []
        if let rawLinks = json["links"] as? [[String: Any]] {
            for item in rawLinks {
                guard let s = item["source"] as? String, let t = item["target"] as? String else { continue }
                if nodeIDs.contains(s) && nodeIDs.contains(t) {
                    let rel = item["relation"] as? String ?? ""
                    links.append(GraphifyLink(source: s, target: t, relation: rel))
                }
            }
        }

        let communities = Array(Set(nodes.map { $0.community })).sorted()
        return GraphifyData(
            nodes: nodes,
            links: links,
            communities: communities,
            reportPath: reportPath,
            htmlPath: htmlPath
        )
    }

    public func loadGraph(from directoryPath: String) -> GraphifyData? {
        let dir = URL(fileURLWithPath: (directoryPath as NSString).expandingTildeInPath)
        return loadGraph(from: dir)
    }

    public func loadGraph(for repoPath: String?, workspacePath: String) -> GraphifyData? {
        var candidateDirs: [URL] = []

        if let rp = repoPath {
            let repoURL = URL(fileURLWithPath: (rp as NSString).expandingTildeInPath)
            candidateDirs.append(repoURL.appendingPathComponent("graphify-out"))
            candidateDirs.append(repoURL.appendingPathComponent(".graphify"))
        }

        let wsURL = URL(fileURLWithPath: (workspacePath as NSString).expandingTildeInPath)
        candidateDirs.append(wsURL.appendingPathComponent("graphify-out"))
        candidateDirs.append(wsURL.appendingPathComponent(".graphify"))
        candidateDirs.append(wsURL.appendingPathComponent("tickets").appendingPathComponent("graphify-out"))
        candidateDirs.append(wsURL.appendingPathComponent("tickets").appendingPathComponent(".graphify"))

        for dir in candidateDirs {
            if let data = loadGraph(from: dir) {
                return data
            }
        }

        return nil
    }

    public func computeDegrees(data: GraphifyData) -> [String: Int] {
        var degreeCount: [String: Int] = [:]
        for link in data.links {
            degreeCount[link.source, default: 0] += 1
            degreeCount[link.target, default: 0] += 1
        }
        for node in data.nodes {
            if degreeCount[node.id] == nil {
                degreeCount[node.id] = 0
            }
        }
        return degreeCount
    }

    public func computeNeighborhood(from rootNodeId: String, depth: Int, links: [GraphifyLink]) -> Set<String> {
        guard depth > 0 else { return [rootNodeId] }
        var visited = Set<String>([rootNodeId])
        var currentEdge = Set<String>([rootNodeId])

        for _ in 0..<depth {
            var nextEdge = Set<String>()
            for link in links {
                if currentEdge.contains(link.source) && !visited.contains(link.target) {
                    visited.insert(link.target)
                    nextEdge.insert(link.target)
                }
                if currentEdge.contains(link.target) && !visited.contains(link.source) {
                    visited.insert(link.source)
                    nextEdge.insert(link.source)
                }
            }
            currentEdge = nextEdge
            if currentEdge.isEmpty { break }
        }
        return visited
    }

    public func computeLayout(
        nodes: [GraphifyNode],
        links: [GraphifyLink],
        width: Double = 800,
        height: Double = 600
    ) -> [String: NodePosition] {
        guard !nodes.isEmpty else { return [:] }

        var positions: [String: NodePosition] = [:]
        var vx: [String: Double] = [:]
        var vy: [String: Double] = [:]

        let centerX = width / 2.0
        let centerY = height / 2.0
        let radius = min(width, height) * 0.38
        let count = nodes.count

        // Initialize positions distributed by community around center
        let sortedNodes = nodes.sorted {
            if $0.community != $1.community {
                return $0.community < $1.community
            }
            return $0.label < $1.label
        }

        for (idx, node) in sortedNodes.enumerated() {
            let angle = Double(idx) * 2.0 * .pi / Double(count)
            positions[node.id] = NodePosition(
                x: centerX + cos(angle) * radius,
                y: centerY + sin(angle) * radius
            )
            vx[node.id] = 0.0
            vy[node.id] = 0.0
        }

        // Lightweight force-directed simulation (35 iterations)
        let linkList = links.compactMap { l -> (s: String, t: String)? in
            if positions[l.source] != nil && positions[l.target] != nil {
                return (s: l.source, t: l.target)
            }
            return nil
        }

        let iterations = min(40, max(20, 500 / count))
        for step in 0..<iterations {
            let alpha = 1.0 - (Double(step) / Double(iterations)) * 0.7

            // Repulsion
            for i in 0..<count {
                let idA = nodes[i].id
                guard let posA = positions[idA] else { continue }
                for j in (i + 1)..<count {
                    let idB = nodes[j].id
                    guard let posB = positions[idB] else { continue }
                    let dx = posA.x - posB.x
                    let dy = posA.y - posB.y
                    let d2 = max(dx * dx + dy * dy, 1.0)
                    let d = sqrt(d2)
                    let f = min(1800.0 / d2, 4.0)
                    let fx = (dx / d) * f
                    let fy = (dy / d) * f
                    vx[idA, default: 0] += fx
                    vy[idA, default: 0] += fy
                    vx[idB, default: 0] -= fx
                    vy[idB, default: 0] -= fy
                }
            }

            // Springs along links
            for l in linkList {
                guard let posS = positions[l.s], let posT = positions[l.t] else { continue }
                let dx = posT.x - posS.x
                let dy = posT.y - posS.y
                let d = max(sqrt(dx * dx + dy * dy), 1.0)
                let f = (d - 60.0) * 0.02
                let fx = (dx / d) * f
                let fy = (dy / d) * f
                vx[l.s, default: 0] += fx
                vy[l.s, default: 0] += fy
                vx[l.t, default: 0] -= fx
                vy[l.t, default: 0] -= fy
            }

            // Center gravity & integration
            for node in nodes {
                let id = node.id
                guard var pos = positions[id] else { continue }
                vx[id, default: 0] += (centerX - pos.x) * 0.005
                vy[id, default: 0] += (centerY - pos.y) * 0.005
                let velX = vx[id, default: 0] * 0.85
                let velY = vy[id, default: 0] * 0.85
                vx[id] = velX
                vy[id] = velY
                pos.x += velX * alpha
                pos.y += velY * alpha
                positions[id] = pos
            }
        }

        return positions
    }

    public func computeGodNodes(data: GraphifyData, limit: Int = 10) -> [(node: GraphifyNode, degree: Int)] {
        let degreeCount = computeDegrees(data: data)
        let sorted = data.nodes.map { node in
            (node: node, degree: degreeCount[node.id, default: 0])
        }
        .sorted { $0.degree > $1.degree }

        return Array(sorted.prefix(limit))
    }
}
