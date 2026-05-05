import Foundation

enum MLXMetallib {
    static func installIfNeeded() throws {
        let environment = ProcessInfo.processInfo.environment
        let forceBuild = environment["SWIFT_AUTORESEARCH_REBUILD_MLX_METALLIB"] == "1"
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let destination = executable.deletingLastPathComponent().appendingPathComponent("mlx.metallib")

        if !forceBuild, let bundled = bundledMetallib(near: executable) {
            if FileManager.default.contentsEqual(atPath: bundled.path, andPath: destination.path) {
                return
            }
            try replaceItem(at: destination, with: bundled)
            return
        }

        if !forceBuild, FileManager.default.isReadableNonEmptyFile(at: destination) {
            return
        }

        let kernelDirectory = try locateKernelDirectory(executable: executable, environment: environment)
        let toolchain = try MetalToolchain.locate()
        try buildMetallib(kernelDirectory: kernelDirectory, output: destination, toolchain: toolchain)
    }

    private static func bundledMetallib(near executable: URL) -> URL? {
        let executableDirectory = executable.deletingLastPathComponent()
        let candidates = [
            executableDirectory.appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"),
            executableDirectory.appendingPathComponent("mlx-swift_Cmlx.bundle/default.metallib"),
            executableDirectory.appendingPathComponent("default.metallib"),
        ]

        return candidates.first { FileManager.default.isReadableNonEmptyFile(at: $0) }
    }

    private static func locateKernelDirectory(
        executable: URL,
        environment: [String: String]
    ) throws -> URL {
        if let override = environment["SWIFT_AUTORESEARCH_MLX_KERNEL_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
            if FileManager.default.isDirectory(at: url) {
                return url
            }
            throw MLXMetallibError("SWIFT_AUTORESEARCH_MLX_KERNEL_DIR does not exist: \(url.path)")
        }

        let suffixes = [
            "checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal",
            "SourcePackages/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal",
            ".build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal",
        ]

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for root in uniqueAncestors(of: [executable, currentDirectory]) {
            for suffix in suffixes {
                let candidate = root.appendingPathComponent(suffix, isDirectory: true)
                if FileManager.default.isDirectory(at: candidate) {
                    return candidate
                }
            }
        }

        throw MLXMetallibError(
            """
            Unable to find MLX Metal kernels. Run `swift package resolve`, or set \
            SWIFT_AUTORESEARCH_MLX_KERNEL_DIR to mlx-swift/Source/Cmlx/mlx-generated/metal.
            """
        )
    }

    private static func uniqueAncestors(of urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for url in urls {
            var current = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
            while true {
                let path = current.standardizedFileURL.path
                if seen.insert(path).inserted {
                    result.append(current)
                }

                let parent = current.deletingLastPathComponent()
                if parent.path == current.path {
                    break
                }
                current = parent
            }
        }

        return result
    }

    private static func buildMetallib(
        kernelDirectory: URL,
        output: URL,
        toolchain: MetalToolchain
    ) throws {
        let fileManager = FileManager.default
        let workDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("swift-autoresearch-mlx-\(UUID().uuidString)", isDirectory: true)
        let airDirectory = workDirectory.appendingPathComponent("air", isDirectory: true)
        let moduleCache = workDirectory.appendingPathComponent("module-cache", isDirectory: true)
        let temporaryMetallib = workDirectory.appendingPathComponent("mlx.metallib")

        defer {
            try? fileManager.removeItem(at: workDirectory)
        }

        try fileManager.createDirectory(at: airDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: moduleCache, withIntermediateDirectories: true)

        let sources = try fileManager
            .recursiveFiles(at: kernelDirectory, extension: "metal")
            .sorted { $0.path < $1.path }

        guard !sources.isEmpty else {
            throw MLXMetallibError("No MLX Metal kernels were found under \(kernelDirectory.path).")
        }

        var airFiles: [URL] = []
        for source in sources {
            let relativePath = String(source.path.dropFirst(kernelDirectory.path.count + 1))
            let airPath = airDirectory
                .appendingPathComponent(relativePath)
                .deletingPathExtension()
                .appendingPathExtension("air")

            try fileManager.createDirectory(
                at: airPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            try run(
                toolchain.metal,
                arguments: [
                    "-x", "metal",
                    "-Wall",
                    "-Wextra",
                    "-fno-fast-math",
                    "-Wno-c++17-extensions",
                    "-Wno-c++20-extensions",
                    "-fmodules-cache-path=\(moduleCache.path)",
                    "-mmacosx-version-min=14.0",
                    "-c", source.path,
                    "-I\(kernelDirectory.path)",
                    "-o", airPath.path,
                ]
            )

            airFiles.append(airPath)
        }

        try run(toolchain.metallib, arguments: airFiles.map(\.path) + ["-o", temporaryMetallib.path])
        try replaceItem(at: output, with: temporaryMetallib)
    }

    private static func replaceItem(at destination: URL, with source: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}

private struct MetalToolchain {
    var metal: URL
    var metallib: URL

    static func locate() throws -> MetalToolchain {
        let output: String
        do {
            output = try run(
                URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                arguments: ["-showComponent", "MetalToolchain", "-json"]
            )
        } catch {
            throw MLXMetallibError(
                """
                Xcode's Metal Toolchain is required to build MLX kernels.

                Install it once, then rerun the command:

                    xcodebuild -downloadComponent MetalToolchain
                """
            )
        }

        let component: XcodeComponent
        do {
            component = try JSONDecoder().decode(XcodeComponent.self, from: Data(output.utf8))
        } catch {
            throw MLXMetallibError("Unable to read Metal Toolchain path from xcodebuild output.")
        }

        let root = URL(fileURLWithPath: component.toolchainSearchPath)
        let metal = root.appendingPathComponent("Metal.xctoolchain/usr/bin/metal")
        let metallib = root.appendingPathComponent("Metal.xctoolchain/usr/bin/metallib")

        guard FileManager.default.isExecutableFile(atPath: metal.path),
              FileManager.default.isExecutableFile(atPath: metallib.path)
        else {
            throw MLXMetallibError("Metal Toolchain executables were not found under \(root.path).")
        }

        return MetalToolchain(metal: metal, metallib: metallib)
    }

    private struct XcodeComponent: Decodable {
        var toolchainSearchPath: String
    }
}

private struct MLXMetallibError: LocalizedError {
    var errorDescription: String?

    init(_ message: String) {
        self.errorDescription = message
    }
}

@discardableResult
private func run(_ executable: URL, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    if process.terminationStatus != 0 {
        throw MLXMetallibError(
            """
            Command failed: \(executable.path) \(arguments.joined(separator: " "))
            \(stdoutText)
            \(stderrText)
            """
        )
    }

    return stdoutText
}

private extension FileManager {
    func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func isReadableNonEmptyFile(at url: URL) -> Bool {
        guard isReadableFile(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        else {
            return false
        }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }

    func recursiveFiles(at url: URL, extension fileExtension: String) throws -> [URL] {
        guard let enumerator = enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator where file.pathExtension == fileExtension {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(file)
            }
        }
        return files
    }
}
