import Darwin.Mach
import Foundation
import Testing
@testable import Glab

@Suite(
    "GitLab job trace performance",
    .serialized
)
struct GitLabJobTracePerformanceTests {
    @Test("Meets the five MiB index budget")
    func fiveMiBIndexBudget() async throws {
        try await withPerformanceWorkspace(
            byteCount: 5 * 1_024 * 1_024
        ) { workspace, traceURL, byteCount in
            _ = try await measureIndex(
                traceURL: traceURL,
                byteCount: byteCount,
                workspace: workspace
            )
            var measurements: [Double] = []
            for _ in 0..<5 {
                let measurement =
                    try await measureIndex(
                        traceURL: traceURL,
                        byteCount: byteCount,
                        workspace: workspace
                    )
                measurements.append(
                    measurement.milliseconds
                )
                try FileManager.default
                    .removeItem(
                        at:
                            measurement
                            .prepared
                            .indexFileURL
                    )
            }
            let p95 =
                percentile95(measurements)

            print(
                "JOB_TRACE_PERFORMANCE "
                    + "5m_index_p95_ms="
                    + format(p95)
            )
            #expect(p95 < fiveMiBIndexBudget)
        }
    }

    @Test("Meets large index, read, search, memory, and disk budgets")
    func largeTraceBudgets() async throws {
        try await withPerformanceWorkspace(
            byteCount: 100 * 1_024 * 1_024
        ) { workspace, traceURL, byteCount in
            let warmup =
                try await measureIndex(
                    traceURL: traceURL,
                    byteCount: byteCount,
                    workspace: workspace
                )
            try FileManager.default
                .removeItem(
                    at:
                        warmup.prepared
                        .indexFileURL
                )
            var indexMeasurements: [Double] = []
            var memoryDeltas: [UInt64] = []
            var retained:
                GitLabJobTracePreparedEntry?
            for iteration in 0..<3 {
                let memoryBefore =
                    try residentMemoryBytes()
                let measurement =
                    try await measureIndex(
                        traceURL: traceURL,
                        byteCount: byteCount,
                        workspace: workspace
                    )
                indexMeasurements.append(
                    measurement.milliseconds
                )
                let memoryAfter =
                    try residentMemoryBytes()
                memoryDeltas.append(
                    memoryAfter
                        > memoryBefore
                    ? memoryAfter
                        - memoryBefore
                    : 0
                )
                if iteration == 2 {
                    retained =
                        measurement.prepared
                } else {
                    try FileManager.default
                        .removeItem(
                            at:
                                measurement
                                .prepared
                                .indexFileURL
                        )
                }
            }
            let prepared = try #require(retained)
            let memoryDelta =
                memoryDeltas.max() ?? 0
            let indexSize =
                try #require(
                    prepared.indexFileURL
                        .resourceValues(
                            forKeys: [
                                .fileSizeKey,
                            ]
                        )
                        .fileSize
                )
            let descriptor =
                GitLabJobTraceDescriptor(
                    key: workspace.key,
                    traceFileURL: traceURL,
                    indexFileURL:
                        prepared.indexFileURL,
                    byteCount: byteCount,
                    lineCount:
                        prepared.lineCount,
                    storedAt:
                        Date(
                            timeIntervalSince1970:
                                1_000
                        ),
                    rawContentDigest:
                        prepared
                        .rawContentDigest,
                    longLineCount:
                        prepared.longLineCount,
                    firstLikelyFailure:
                        prepared
                        .firstLikelyFailure
                )

            var coldReads: [Double] = []
            for _ in 0..<10 {
                let document =
                    GitLabJobTraceDocument(
                        descriptor: descriptor
                    )
                let start =
                    ContinuousClock.now
                let lines =
                    try await document.lines(
                        in: 0..<200
                    )
                coldReads.append(
                    milliseconds(
                        start.duration(
                            to:
                                ContinuousClock
                                .now
                        )
                    )
                )
                #expect(lines.count == 200)
            }

            let warmDocument =
                GitLabJobTraceDocument(
                    descriptor: descriptor
                )
            _ = try await warmDocument.lines(
                in: 0..<200
            )
            var warmReads: [Double] = []
            for _ in 0..<20 {
                let start =
                    ContinuousClock.now
                let lines =
                    try await warmDocument.lines(
                        in: 0..<200
                    )
                warmReads.append(
                    milliseconds(
                        start.duration(
                            to:
                                ContinuousClock
                                .now
                        )
                    )
                )
                #expect(lines.count == 200)
            }

            var searches: [Double] = []
            for _ in 0..<3 {
                let document =
                    GitLabJobTraceDocument(
                        descriptor: descriptor
                    )
                let start =
                    ContinuousClock.now
                let result =
                    try await document.search(
                        "not-present"
                    )
                searches.append(
                    milliseconds(
                        start.duration(
                            to:
                                ContinuousClock
                                .now
                        )
                    )
                )
                #expect(
                    result.lineIndexes
                        .isEmpty
                )
            }

            let indexP95 =
                percentile95(
                    indexMeasurements
                )
            let coldP95 =
                percentile95(coldReads)
            let warmP95 =
                percentile95(warmReads)
            let searchP95 =
                percentile95(searches)

            print(
                "JOB_TRACE_PERFORMANCE "
                    + "100m_index_p95_ms="
                    + format(indexP95)
                    + " memory_delta_mib="
                    + format(
                        mebibytes(memoryDelta)
                    )
                    + " cold_200_p95_ms="
                    + format(coldP95)
                    + " warm_200_p95_ms="
                    + format(warmP95)
                    + " search_p95_ms="
                    + format(searchP95)
                    + " index_bytes="
                    + String(indexSize)
            )

            #expect(
                indexP95
                    < largeIndexBudget
            )
            #expect(
                memoryDelta
                    < 64 * 1_024 * 1_024
            )
            #expect(
                coldP95 < coldReadBudget
            )
            #expect(
                warmP95 < warmReadBudget
            )
            #expect(
                searchP95 < searchBudget
            )
            #expect(indexSize <= 20_000_000)
        }
    }

    private func measureIndex(
        traceURL: URL,
        byteCount: Int,
        workspace:
            GitLabJobTraceImportWorkspace
    ) async throws -> (
        prepared: GitLabJobTracePreparedEntry,
        milliseconds: Double
    ) {
        let start = ContinuousClock.now
        let prepared =
            try await GitLabJobTraceIndexer()
            .prepare(
                traceFileURL: traceURL,
                byteCount: byteCount,
                in: workspace
            )
        return (
            prepared,
            milliseconds(
                start.duration(
                    to: ContinuousClock.now
                )
            )
        )
    }

    private func withPerformanceWorkspace(
        byteCount: Int,
        operation: (
            GitLabJobTraceImportWorkspace,
            URL,
            Int
        ) async throws -> Void
    ) async throws {
        let directory =
            FileManager.default
            .temporaryDirectory
            .appending(
                path:
                    "GlabTracePerformanceTests-"
                    + UUID().uuidString,
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let traceURL =
            directory.appending(
                path: "trace.download",
                directoryHint: .notDirectory
            )
        try writeFixture(
            byteCount: byteCount,
            to: traceURL
        )
        let accountID =
            GitLabAccountID(
                host:
                    try GitLabHost(
                        "https://gitlab.example.com"
                    ),
                userID: 7
            )
        let route = try #require(
            GitLabJobTraceRoute(
                projectID: 42,
                jobID: 9
            )
        )
        let workspace =
            GitLabJobTraceImportWorkspace(
                key:
                    GitLabJobTraceKey(
                        accountID: accountID,
                        route: route
                    ),
                directoryURL: directory,
                identifier: UUID()
            )

        try await operation(
            workspace,
            traceURL,
            byteCount
        )
    }

    private func writeFixture(
        byteCount: Int,
        to fileURL: URL
    ) throws {
        var line = Data(
            repeating: 0x61,
            count: 63
        )
        line.append(0x0A)
        var chunk = Data()
        chunk.reserveCapacity(64 * 1_024)
        for _ in 0..<1_024 {
            chunk.append(line)
        }
        guard
            FileManager.default.createFile(
                atPath: fileURL.path,
                contents: nil,
                attributes: [
                    .protectionKey:
                        FileProtectionType
                        .completeUntilFirstUserAuthentication,
                ]
            )
        else {
            throw
                GitLabJobTraceDocumentError
                .invalidFile
        }
        let handle = try FileHandle(
            forWritingTo: fileURL
        )
        defer {
            try? handle.close()
        }
        var remaining = byteCount
        while remaining > 0 {
            let count =
                min(remaining, chunk.count)
            if count == chunk.count {
                try handle.write(
                    contentsOf: chunk
                )
            } else {
                try handle.write(
                    contentsOf:
                        chunk.prefix(count)
                )
            }
            remaining -= count
        }
    }

    private func residentMemoryBytes()
        throws -> UInt64
    {
        var info =
            mach_task_basic_info_data_t()
        var count =
            mach_msg_type_number_t(
                MemoryLayout.size(
                    ofValue: info
                )
                / MemoryLayout<natural_t>
                .size
            )
        let result =
            withUnsafeMutablePointer(
                to: &info
            ) { pointer in
                pointer.withMemoryRebound(
                    to: integer_t.self,
                    capacity: Int(count)
                ) { reboundPointer in
                    task_info(
                        mach_task_self_,
                        task_flavor_t(
                            MACH_TASK_BASIC_INFO
                        ),
                        reboundPointer,
                        &count
                    )
                }
            }
        guard result == KERN_SUCCESS else {
            throw
                GitLabJobTraceDocumentError
                .invalidFile
        }
        return UInt64(info.resident_size)
    }

    private func milliseconds(
        _ duration: Duration
    ) -> Double {
        let components =
            duration.components
        return
            Double(components.seconds)
                * 1_000
            + Double(
                components.attoseconds
            )
                / 1_000_000_000_000_000
    }

    private func percentile95(
        _ values: [Double]
    ) -> Double {
        let sorted = values.sorted()
        let index = min(
            sorted.count - 1,
            Int(
                ceil(
                    Double(sorted.count)
                        * 0.95
                )
            ) - 1
        )
        return sorted[index]
    }

    private func mebibytes(
        _ bytes: UInt64
    ) -> Double {
        Double(bytes)
            / Double(1_024 * 1_024)
    }

    private func format(
        _ value: Double
    ) -> String {
        value.formatted(
            .number.precision(
                .fractionLength(3)
            )
        )
    }

    private var fiveMiBIndexBudget:
        Double
    {
#if DEBUG
        500
#else
        250
#endif
    }

    private var largeIndexBudget: Double {
#if DEBUG
        6_000
#else
        3_000
#endif
    }

    private var coldReadBudget: Double {
#if DEBUG
        100
#else
        50
#endif
    }

    private var warmReadBudget: Double {
#if DEBUG
        10
#else
        5
#endif
    }

    private var searchBudget: Double {
#if DEBUG
        6_000
#else
        3_000
#endif
    }
}
