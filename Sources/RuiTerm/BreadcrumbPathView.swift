import SwiftUI

/// A clickable breadcrumb path view where each path segment is a button
/// that navigates to that directory level.
struct BreadcrumbPathView: View {
    let path: String
    let navigateTo: (String) -> Void
    
    private var segments: [(name: String, fullPath: String)] {
        // Handle home directory shorthand
        if path == "~" || path == "/" {
            return [(name: path, fullPath: path)]
        }
        
        var result: [(name: String, fullPath: String)] = []
        let isHomePath = path.hasPrefix("~/")
        let workingPath = isHomePath ? String(path.dropFirst(2)) : path
        
        // Add root or ~ as first segment
        if isHomePath {
            result.append((name: "~", fullPath: "~"))
        } else {
            result.append((name: "/", fullPath: "/"))
        }
        
        // Split remaining path into segments
        let components = workingPath.split(separator: "/", omittingEmptySubsequences: true)
        for (index, component) in components.enumerated() {
            let prefix = isHomePath ? "~/" : "/"
            let subPath = prefix + components[0...index].joined(separator: "/")
            result.append((name: String(component), fullPath: subPath))
        }
        
        return result
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.quaternary)
                    }
                    
                    let isLast = index == segments.count - 1
                    Button {
                        if !isLast {
                            navigateTo(segment.fullPath)
                        }
                    } label: {
                        Text(segment.name)
                            .font(.caption.monospaced())
                            .foregroundStyle(isLast ? .primary : .secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isLast ? Color.clear : Color.primary.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLast)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
