import SwiftUI

/// Provides file-type-specific SF Symbol icons and colors for the SFTP browser
struct FileIconProvider {
    
    struct FileIcon {
        let systemName: String
        let color: Color
    }
    
    /// Returns the appropriate icon for a given filename
    static func icon(for filename: String, isDirectory: Bool) -> FileIcon {
        if isDirectory {
            return directoryIcon(for: filename)
        }
        
        let ext = (filename as NSString).pathExtension.lowercased()
        let name = filename.lowercased()
        
        // Match by extension first
        if let icon = extensionIcons[ext] {
            return icon
        }
        
        // Match by exact filename (dotfiles, Makefile, etc.)
        if let icon = filenameIcons[name] {
            return icon
        }
        
        // Fallback: generic document
        return FileIcon(systemName: "doc", color: .secondary)
    }
    
    // MARK: - Directory Icons
    
    private static func directoryIcon(for name: String) -> FileIcon {
        let lower = name.lowercased()
        switch lower {
        case ".git":
            return FileIcon(systemName: "folder.fill.badge.gearshape", color: .orange)
        case "node_modules":
            return FileIcon(systemName: "folder.fill.badge.questionmark", color: .green)
        case ".ssh", ".gnupg":
            return FileIcon(systemName: "folder.fill.badge.person.crop", color: .red)
        case "downloads":
            return FileIcon(systemName: "arrow.down.circle.fill", color: .blue)
        case "documents":
            return FileIcon(systemName: "doc.on.doc.fill", color: .blue)
        case "pictures", "images", "photos":
            return FileIcon(systemName: "photo.on.rectangle.fill", color: .teal)
        case "music", "audio":
            return FileIcon(systemName: "music.note.list", color: .pink)
        case "videos", "movies":
            return FileIcon(systemName: "film.fill", color: .purple)
        case "desktop":
            return FileIcon(systemName: "desktopcomputer", color: .blue)
        case "bin", "sbin", "usr":
            return FileIcon(systemName: "folder.fill.badge.gearshape", color: .gray)
        case "tmp", "temp", "cache", ".cache":
            return FileIcon(systemName: "clock.fill", color: .orange)
        case "log", "logs":
            return FileIcon(systemName: "doc.text.fill", color: .yellow)
        case "config", ".config", "etc":
            return FileIcon(systemName: "gearshape.fill", color: .gray)
        case "src", "source", "sources", "lib":
            return FileIcon(systemName: "chevron.left.forwardslash.chevron.right", color: .cyan)
        case "test", "tests", "__tests__", "spec", "specs":
            return FileIcon(systemName: "checkmark.circle.fill", color: .green)
        case "build", "dist", "out", "target", "output":
            return FileIcon(systemName: "shippingbox.fill", color: .brown)
        case "public", "static", "assets":
            return FileIcon(systemName: "globe", color: .blue)
        default:
            return FileIcon(systemName: "folder.fill", color: .blue)
        }
    }
    
    // MARK: - Extension → Icon Map
    
    private static let extensionIcons: [String: FileIcon] = [
        // --- Source Code ---
        "swift":    FileIcon(systemName: "swift", color: .orange),
        "java":     FileIcon(systemName: "cup.and.saucer.fill", color: .red),
        "kt":       FileIcon(systemName: "k.circle.fill", color: .purple),
        "py":       FileIcon(systemName: "chevron.left.forwardslash.chevron.right", color: .yellow),
        "rb":       FileIcon(systemName: "diamond.fill", color: .red),
        "go":       FileIcon(systemName: "chevron.left.forwardslash.chevron.right", color: .cyan),
        "rs":       FileIcon(systemName: "gearshape.2.fill", color: .orange),
        "c":        FileIcon(systemName: "c.circle.fill", color: .blue),
        "h":        FileIcon(systemName: "h.circle.fill", color: .blue),
        "cpp":      FileIcon(systemName: "c.circle.fill", color: .indigo),
        "hpp":      FileIcon(systemName: "h.circle.fill", color: .indigo),
        "m":        FileIcon(systemName: "m.circle.fill", color: .blue),
        "cs":       FileIcon(systemName: "c.circle.fill", color: .green),
        "php":      FileIcon(systemName: "chevron.left.forwardslash.chevron.right", color: .indigo),
        "pl":       FileIcon(systemName: "chevron.left.forwardslash.chevron.right", color: .teal),
        "lua":      FileIcon(systemName: "moon.fill", color: .blue),
        "r":        FileIcon(systemName: "r.circle.fill", color: .blue),
        "scala":    FileIcon(systemName: "s.circle.fill", color: .red),
        "dart":     FileIcon(systemName: "d.circle.fill", color: .cyan),
        "ex":       FileIcon(systemName: "e.circle.fill", color: .purple),
        "exs":      FileIcon(systemName: "e.circle.fill", color: .purple),
        "hs":       FileIcon(systemName: "chevron.left.forwardslash.chevron.right", color: .purple),
        "erl":      FileIcon(systemName: "e.circle.fill", color: .red),
        
        // --- Web / Frontend ---
        "js":       FileIcon(systemName: "j.circle.fill", color: .yellow),
        "jsx":      FileIcon(systemName: "j.circle.fill", color: .yellow),
        "ts":       FileIcon(systemName: "t.circle.fill", color: .blue),
        "tsx":      FileIcon(systemName: "t.circle.fill", color: .blue),
        "html":     FileIcon(systemName: "globe", color: .orange),
        "htm":      FileIcon(systemName: "globe", color: .orange),
        "css":      FileIcon(systemName: "paintbrush.fill", color: .blue),
        "scss":     FileIcon(systemName: "paintbrush.fill", color: .pink),
        "sass":     FileIcon(systemName: "paintbrush.fill", color: .pink),
        "less":     FileIcon(systemName: "paintbrush.fill", color: .indigo),
        "vue":      FileIcon(systemName: "v.circle.fill", color: .green),
        "svelte":   FileIcon(systemName: "s.circle.fill", color: .orange),
        
        // --- Data / Config ---
        "json":     FileIcon(systemName: "curlybraces", color: .yellow),
        "yaml":     FileIcon(systemName: "list.bullet.indent", color: .green),
        "yml":      FileIcon(systemName: "list.bullet.indent", color: .green),
        "xml":      FileIcon(systemName: "chevron.left.forwardslash.chevron.right", color: .orange),
        "toml":     FileIcon(systemName: "doc.text.fill", color: .gray),
        "ini":      FileIcon(systemName: "gearshape.fill", color: .gray),
        "cfg":      FileIcon(systemName: "gearshape.fill", color: .gray),
        "conf":     FileIcon(systemName: "gearshape.fill", color: .gray),
        "properties": FileIcon(systemName: "list.bullet", color: .gray),
        "env":      FileIcon(systemName: "key.fill", color: .yellow),
        "plist":    FileIcon(systemName: "list.bullet.rectangle.fill", color: .gray),
        "csv":      FileIcon(systemName: "tablecells", color: .green),
        "tsv":      FileIcon(systemName: "tablecells", color: .green),
        
        // --- SQL / Database ---
        "sql":      FileIcon(systemName: "cylinder.fill", color: .blue),
        "sqlite":   FileIcon(systemName: "cylinder.fill", color: .blue),
        "db":       FileIcon(systemName: "cylinder.fill", color: .gray),
        
        // --- Shell / Scripts ---
        "sh":       FileIcon(systemName: "terminal.fill", color: .green),
        "bash":     FileIcon(systemName: "terminal.fill", color: .green),
        "zsh":      FileIcon(systemName: "terminal.fill", color: .green),
        "fish":     FileIcon(systemName: "terminal.fill", color: .green),
        "ps1":      FileIcon(systemName: "terminal.fill", color: .blue),
        "bat":      FileIcon(systemName: "terminal.fill", color: .gray),
        "cmd":      FileIcon(systemName: "terminal.fill", color: .gray),
        
        // --- Documentation ---
        "md":       FileIcon(systemName: "doc.richtext.fill", color: .blue),
        "markdown": FileIcon(systemName: "doc.richtext.fill", color: .blue),
        "rst":      FileIcon(systemName: "doc.richtext.fill", color: .teal),
        "txt":      FileIcon(systemName: "doc.text.fill", color: .gray),
        "rtf":      FileIcon(systemName: "doc.richtext.fill", color: .gray),
        "pdf":      FileIcon(systemName: "doc.fill", color: .red),
        "doc":      FileIcon(systemName: "doc.fill", color: .blue),
        "docx":     FileIcon(systemName: "doc.fill", color: .blue),
        "xls":      FileIcon(systemName: "tablecells.fill", color: .green),
        "xlsx":     FileIcon(systemName: "tablecells.fill", color: .green),
        "ppt":      FileIcon(systemName: "rectangle.fill.on.rectangle.fill", color: .orange),
        "pptx":     FileIcon(systemName: "rectangle.fill.on.rectangle.fill", color: .orange),
        
        // --- Images ---
        "png":      FileIcon(systemName: "photo.fill", color: .teal),
        "jpg":      FileIcon(systemName: "photo.fill", color: .teal),
        "jpeg":     FileIcon(systemName: "photo.fill", color: .teal),
        "gif":      FileIcon(systemName: "photo.fill", color: .purple),
        "bmp":      FileIcon(systemName: "photo.fill", color: .teal),
        "tiff":     FileIcon(systemName: "photo.fill", color: .teal),
        "tif":      FileIcon(systemName: "photo.fill", color: .teal),
        "webp":     FileIcon(systemName: "photo.fill", color: .teal),
        "svg":      FileIcon(systemName: "square.on.circle", color: .orange),
        "ico":      FileIcon(systemName: "photo.fill", color: .teal),
        "icns":     FileIcon(systemName: "app.fill", color: .blue),
        "psd":      FileIcon(systemName: "paintpalette.fill", color: .blue),
        "ai":       FileIcon(systemName: "paintpalette.fill", color: .orange),
        "sketch":   FileIcon(systemName: "paintpalette.fill", color: .yellow),
        "fig":      FileIcon(systemName: "paintpalette.fill", color: .purple),
        
        // --- Video ---
        "mp4":      FileIcon(systemName: "film.fill", color: .purple),
        "mov":      FileIcon(systemName: "film.fill", color: .purple),
        "avi":      FileIcon(systemName: "film.fill", color: .purple),
        "mkv":      FileIcon(systemName: "film.fill", color: .purple),
        "wmv":      FileIcon(systemName: "film.fill", color: .purple),
        "flv":      FileIcon(systemName: "film.fill", color: .purple),
        "webm":     FileIcon(systemName: "film.fill", color: .purple),
        
        // --- Audio ---
        "mp3":      FileIcon(systemName: "music.note", color: .pink),
        "wav":      FileIcon(systemName: "music.note", color: .pink),
        "aac":      FileIcon(systemName: "music.note", color: .pink),
        "flac":     FileIcon(systemName: "music.note", color: .pink),
        "ogg":      FileIcon(systemName: "music.note", color: .pink),
        "m4a":      FileIcon(systemName: "music.note", color: .pink),
        "wma":      FileIcon(systemName: "music.note", color: .pink),
        
        // --- Archives ---
        "zip":      FileIcon(systemName: "doc.zipper", color: .yellow),
        "tar":      FileIcon(systemName: "doc.zipper", color: .brown),
        "gz":       FileIcon(systemName: "doc.zipper", color: .brown),
        "bz2":      FileIcon(systemName: "doc.zipper", color: .brown),
        "xz":       FileIcon(systemName: "doc.zipper", color: .brown),
        "7z":       FileIcon(systemName: "doc.zipper", color: .purple),
        "rar":      FileIcon(systemName: "doc.zipper", color: .purple),
        "tgz":      FileIcon(systemName: "doc.zipper", color: .brown),
        "dmg":      FileIcon(systemName: "externaldrive.fill", color: .gray),
        "iso":      FileIcon(systemName: "opticaldisc.fill", color: .gray),
        "pkg":      FileIcon(systemName: "shippingbox.fill", color: .brown),
        "deb":      FileIcon(systemName: "shippingbox.fill", color: .red),
        "rpm":      FileIcon(systemName: "shippingbox.fill", color: .red),
        
        // --- DevOps / Container ---
        "dockerfile": FileIcon(systemName: "shippingbox.fill", color: .blue),
        "dockerignore": FileIcon(systemName: "shippingbox.fill", color: .gray),
        
        // --- Certificates / Security ---
        "pem":      FileIcon(systemName: "lock.fill", color: .green),
        "crt":      FileIcon(systemName: "lock.fill", color: .green),
        "cer":      FileIcon(systemName: "lock.fill", color: .green),
        "key":      FileIcon(systemName: "key.fill", color: .yellow),
        "p12":      FileIcon(systemName: "lock.shield.fill", color: .green),
        "pfx":      FileIcon(systemName: "lock.shield.fill", color: .green),
        "pub":      FileIcon(systemName: "key.horizontal.fill", color: .teal),
        
        // --- Fonts ---
        "ttf":      FileIcon(systemName: "textformat", color: .gray),
        "otf":      FileIcon(systemName: "textformat", color: .gray),
        "woff":     FileIcon(systemName: "textformat", color: .gray),
        "woff2":    FileIcon(systemName: "textformat", color: .gray),
        
        // --- Logs ---
        "log":      FileIcon(systemName: "doc.text.fill", color: .yellow),
        
        // --- Binary / Executable ---
        "bin":      FileIcon(systemName: "cpu.fill", color: .gray),
        "exe":      FileIcon(systemName: "cpu.fill", color: .gray),
        "so":       FileIcon(systemName: "cpu.fill", color: .gray),
        "dylib":    FileIcon(systemName: "cpu.fill", color: .gray),
        "a":        FileIcon(systemName: "cpu.fill", color: .gray),
        "o":        FileIcon(systemName: "cpu.fill", color: .gray),
        "class":    FileIcon(systemName: "cup.and.saucer.fill", color: .red),
        "jar":      FileIcon(systemName: "cup.and.saucer.fill", color: .red),
        "war":      FileIcon(systemName: "cup.and.saucer.fill", color: .red),
    ]
    
    // MARK: - Filename → Icon Map (for dotfiles, special names)
    
    private static let filenameIcons: [String: FileIcon] = [
        ".gitignore":       FileIcon(systemName: "eye.slash.fill", color: .orange),
        ".gitattributes":   FileIcon(systemName: "text.badge.checkmark", color: .orange),
        ".gitmodules":      FileIcon(systemName: "arrow.triangle.branch", color: .orange),
        ".editorconfig":    FileIcon(systemName: "gearshape.fill", color: .gray),
        ".eslintrc":        FileIcon(systemName: "checkmark.shield.fill", color: .purple),
        ".eslintrc.json":   FileIcon(systemName: "checkmark.shield.fill", color: .purple),
        ".prettierrc":      FileIcon(systemName: "paintbrush.fill", color: .pink),
        ".bashrc":          FileIcon(systemName: "terminal.fill", color: .green),
        ".bash_profile":    FileIcon(systemName: "terminal.fill", color: .green),
        ".bash_logout":     FileIcon(systemName: "terminal.fill", color: .green),
        ".zshrc":           FileIcon(systemName: "terminal.fill", color: .green),
        ".zprofile":        FileIcon(systemName: "terminal.fill", color: .green),
        ".profile":         FileIcon(systemName: "terminal.fill", color: .green),
        ".env":             FileIcon(systemName: "key.fill", color: .yellow),
        ".env.local":       FileIcon(systemName: "key.fill", color: .yellow),
        ".env.production":  FileIcon(systemName: "key.fill", color: .yellow),
        ".env.development": FileIcon(systemName: "key.fill", color: .yellow),
        ".dockerignore":    FileIcon(systemName: "shippingbox.fill", color: .gray),
        ".npmrc":           FileIcon(systemName: "shippingbox.fill", color: .red),
        ".yarnrc":          FileIcon(systemName: "shippingbox.fill", color: .blue),
        "dockerfile":       FileIcon(systemName: "shippingbox.fill", color: .blue),
        "docker-compose.yml": FileIcon(systemName: "shippingbox.fill", color: .blue),
        "docker-compose.yaml": FileIcon(systemName: "shippingbox.fill", color: .blue),
        "makefile":         FileIcon(systemName: "hammer.fill", color: .brown),
        "cmakelists.txt":   FileIcon(systemName: "hammer.fill", color: .blue),
        "rakefile":         FileIcon(systemName: "hammer.fill", color: .red),
        "gemfile":          FileIcon(systemName: "diamond.fill", color: .red),
        "gemfile.lock":     FileIcon(systemName: "lock.fill", color: .red),
        "podfile":          FileIcon(systemName: "shippingbox.fill", color: .red),
        "podfile.lock":     FileIcon(systemName: "lock.fill", color: .red),
        "package.json":     FileIcon(systemName: "shippingbox.fill", color: .red),
        "package-lock.json": FileIcon(systemName: "lock.fill", color: .red),
        "yarn.lock":        FileIcon(systemName: "lock.fill", color: .blue),
        "cargo.toml":       FileIcon(systemName: "shippingbox.fill", color: .orange),
        "cargo.lock":       FileIcon(systemName: "lock.fill", color: .orange),
        "go.mod":           FileIcon(systemName: "shippingbox.fill", color: .cyan),
        "go.sum":           FileIcon(systemName: "lock.fill", color: .cyan),
        "pom.xml":          FileIcon(systemName: "shippingbox.fill", color: .red),
        "build.gradle":     FileIcon(systemName: "hammer.fill", color: .teal),
        "build.gradle.kts": FileIcon(systemName: "hammer.fill", color: .teal),
        "settings.gradle":  FileIcon(systemName: "gearshape.fill", color: .teal),
        "license":          FileIcon(systemName: "doc.text.fill", color: .yellow),
        "license.md":       FileIcon(systemName: "doc.text.fill", color: .yellow),
        "readme.md":        FileIcon(systemName: "book.fill", color: .blue),
        "changelog.md":     FileIcon(systemName: "clock.fill", color: .green),
        "contributing.md":  FileIcon(systemName: "person.2.fill", color: .blue),
    ]
}
