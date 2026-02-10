//
//  ImportProgressViews.swift
//  HiDocu
//
//  Shared import progress components: storage bar visualization and progress footer.
//

import SwiftUI

// MARK: - Finder-Style Storage Bar

struct FinderStorageBar: View {
    let storage: DeviceStorageInfo
    let recordingsBytes: Int64

    private var otherBytes: Int64 {
        max(storage.usedBytes - recordingsBytes, 0)
    }

    private var segments: [(color: Color, fraction: Double, label: String, bytes: Int64)] {
        guard storage.totalBytes > 0 else { return [] }
        let total = Double(storage.totalBytes)
        var result: [(Color, Double, String, Int64)] = []

        let recFrac = Double(recordingsBytes) / total
        if recFrac > 0.005 {
            result.append((.accentColor, recFrac, "Recordings", recordingsBytes))
        }

        let otherFrac = Double(otherBytes) / total
        if otherFrac > 0.005 {
            result.append((.gray, otherFrac, "Other", otherBytes))
        }

        let freeFrac = Double(storage.freeBytes) / total
        result.append((Color(nsColor: .separatorColor), freeFrac, "Available", storage.freeBytes))

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(geo.size.width * segment.fraction, 1))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 14)

            HStack(spacing: 12) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 8, height: 8)
                        Text("\(segment.label): \(ByteCountFormatter.string(fromByteCount: segment.bytes, countStyle: .file))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Import Progress Footer

struct ImportProgressFooter: View {
    var session: ImportSession

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if session.importState == .stopping {
                    Text("Stopping after current file\u{2026}")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let file = session.currentFile {
                    Text("Importing \"\(file)\"")
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                ProgressView(value: session.progress)
                    .progressViewStyle(.linear)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(session.formattedBytesProgress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if session.bytesPerSecond > 0 {
                    Text(session.formattedTelemetry)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .fixedSize()
        }
    }
}
