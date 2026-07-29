#if DEBUG
    import Foundation

    actor GitLabPipelineFixtureJobTraceLoader:
        GitLabJobTraceLoading
    {
        private let indexer =
            GitLabJobTraceIndexer()
        private let rootDirectoryURL:
            URL
        private var descriptors:
            [String: GitLabJobTraceDescriptor] =
            [:]
        private var loadCounts:
            [GitLabJobTraceKey: Int] = [:]

        init() {
            rootDirectoryURL =
                FileManager.default
                .temporaryDirectory
                .appending(
                    path:
                        "p3-10-job-trace-fixtures-"
                        + UUID().uuidString,
                    directoryHint:
                        .isDirectory
                )
        }

        func cachedDescriptor(
            for key: GitLabJobTraceKey
        ) async -> GitLabJobTraceDescriptor? {
            guard
                key.route.projectID == 42,
                key.route.jobID == 910
                    || key.route.jobID == 909
            else {
                return nil
            }
            return try? await descriptor(
                for: key,
                revision: 1
            )
        }

        func loadTrace(
            for key: GitLabJobTraceKey
        ) async throws(GitLabJobTraceLoadError)
            -> GitLabJobTraceDescriptor
        {
            guard key.route.projectID == 42
            else {
                throw .noTrace
            }
            switch key.route.jobID {
            case 906:
                throw .noTrace
            case 905:
                throw .tooLarge
            case 908:
                let revision =
                    (loadCounts[key] ?? 0)
                    + 1
                loadCounts[key] = revision
                return try await loadDescriptor(
                    for: key,
                    revision: revision
                )
            case 907, 910, 909, 1001:
                return try await loadDescriptor(
                    for: key,
                    revision: 1
                )
            default:
                throw .noTrace
            }
        }

        private func loadDescriptor(
            for key: GitLabJobTraceKey,
            revision: Int
        ) async throws(GitLabJobTraceLoadError)
            -> GitLabJobTraceDescriptor
        {
            do {
                return try await descriptor(
                    for: key,
                    revision: revision
                )
            } catch is CancellationError {
                throw .cancelled
            } catch {
                throw .storage
            }
        }

        private func descriptor(
            for key: GitLabJobTraceKey,
            revision: Int
        ) async throws
            -> GitLabJobTraceDescriptor
        {
            try Task.checkCancellation()
            let identity =
                key.storageIdentifier
                + "-r\(revision)"
            if let descriptor =
                descriptors[identity]
            {
                return descriptor
            }

            let fileManager =
                FileManager.default
            let directoryURL =
                rootDirectoryURL
                .appending(
                    path: identity,
                    directoryHint:
                        .isDirectory
                )
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories:
                    true
            )
            let rawData =
                Self.traceData(
                    jobID:
                        key.route.jobID,
                    revision: revision
                )
            let traceFileURL =
                directoryURL.appending(
                    path: ".glab-fixture.raw",
                    directoryHint:
                        .notDirectory
                )
            try rawData.write(
                to: traceFileURL,
                options: .atomic
            )
            let workspace =
                GitLabJobTraceImportWorkspace(
                    key: key,
                    directoryURL:
                        directoryURL,
                    identifier: UUID()
                )
            let prepared =
                try await indexer.prepare(
                    traceFileURL:
                        traceFileURL,
                    byteCount:
                        rawData.count,
                    in: workspace
                )
            let descriptor =
                GitLabJobTraceDescriptor(
                    key: key,
                    traceFileURL:
                        prepared
                        .traceFileURL,
                    indexFileURL:
                        prepared
                        .indexFileURL,
                    byteCount:
                        prepared.byteCount,
                    lineCount:
                        prepared.lineCount,
                    storedAt:
                        Date(
                            timeIntervalSince1970:
                                1_785_340_000
                                + Double(
                                    revision
                                )
                        ),
                    rawContentDigest:
                        prepared
                        .rawContentDigest,
                    longLineCount:
                        prepared
                        .longLineCount,
                    firstLikelyFailure:
                        prepared
                        .firstLikelyFailure
                )
            descriptors[identity] =
                descriptor
            return descriptor
        }

        private nonisolated static func
            traceData(
                jobID: Int,
                revision: Int
            ) -> Data
        {
            switch jobID {
            case 909:
                return Data()
            case 908:
                return growingTraceData(
                    revision: revision
                )
            case 907:
                return largeTraceData()
            case 1001:
                return invalidAndUnicodeTraceData()
            default:
                return representativeTraceData()
            }
        }

        private nonisolated static func
            representativeTraceData() -> Data
        {
            var data = Data()
            append(
                "$ swift build --configuration release\r\n",
                to: &data
            )
            append(
                "\u{1B}[32mResolving dependencies\u{1B}[0m\n",
                to: &data
            )
            append(
                "Compiling Glab for iPhone 17 Pro ✅\n",
                to: &data
            )
            for index in 0..<1_200 {
                append(
                    "step \(index) compile Sources/Feature\(index % 97).swift\n",
                    to: &data
                )
            }
            append(
                "warning: fixture warning remains non-fatal\n",
                to: &data
            )
            append(
                "error: deterministic fixture failure for jump testing\n",
                to: &data
            )
            append(
                "\u{1B}]8;;https://example.invalid\u{07}unsafe link\u{1B}]8;;\u{07}\n",
                to: &data
            )
            append(
                String(
                    repeating: "x",
                    count: 40_000
                ) + "\n",
                to: &data
            )
            append(
                "Finished fixture log\n",
                to: &data
            )
            return data
        }

        private nonisolated static func
            growingTraceData(
                revision: Int
            ) -> Data
        {
            let lineCount =
                revision == 1
                ? 120
                : 420
            var data = Data()
            append(
                "Running pipeline log revision \(revision)\n",
                to: &data
            )
            for index in 0..<lineCount {
                append(
                    "live step \(index) still running\n",
                    to: &data
                )
            }
            if revision > 1 {
                append(
                    "error: refreshed fixture output\n",
                    to: &data
                )
            }
            return data
        }

        private nonisolated static func
            largeTraceData() -> Data
        {
            var data = Data()
            data.reserveCapacity(
                4 * 1_024 * 1_024
            )
            for index in 0..<50_000 {
                let marker =
                    index == 32_768
                    ? "error: large fixture marker"
                    : "running"
                append(
                    "line \(index) \(marker) module-\(index % 113)\n",
                    to: &data
                )
            }
            return data
        }

        private nonisolated static func
            invalidAndUnicodeTraceData()
            -> Data
        {
            var data = Data()
            append(
                "Packaging RésuméKit 日本語 🚀\r\n",
                to: &data
            )
            data.append(
                contentsOf: [
                    0x69,
                    0x6E,
                    0x76,
                    0x61,
                    0x6C,
                    0x69,
                    0x64,
                    0x3A,
                    0x20,
                    0xFF,
                    0xFE,
                    0x0A,
                ]
            )
            append(
                "control\u{00}sequence removed\n",
                to: &data
            )
            append(
                "Finished archived fixture\n",
                to: &data
            )
            return data
        }

        private nonisolated static func
            append(
                _ string: String,
                to data: inout Data
            )
        {
            data.append(
                contentsOf: string.utf8
            )
        }
    }
#endif
