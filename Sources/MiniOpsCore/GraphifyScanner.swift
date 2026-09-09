import Foundation

public final class GraphifyScanner: @unchecked Sendable {
    public static let shared = GraphifyScanner()

    public init() {}

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
            let jsonURL = dir.appendingPathComponent("graph.json")
            if FileManager.default.fileExists(atPath: jsonURL.path),
               let data = try? Data(contentsOf: jsonURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

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
        }

        return nil
    }

    public func computeGodNodes(data: GraphifyData, limit: Int = 10) -> [(node: GraphifyNode, degree: Int)] {
        var degreeCount: [String: Int] = [:]
        for link in data.links {
            degreeCount[link.source, default: 0] += 1
            degreeCount[link.target, default: 0] += 1
        }

        let sorted = data.nodes.map { node in
            (node: node, degree: degreeCount[node.id, default: 0])
        }
        .sorted { $0.degree > $1.degree }

        return Array(sorted.prefix(limit))
    }
}
