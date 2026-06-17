import SwiftUI

// MARK: - Hex Dump View for Binary Data

/// View to display binary data as hex dump with ASCII sidebar
struct HexDumpView: View {
    let data: Data
    let bytesPerRow: Int = 16
    let maxRows: Int = 64 // Limit to ~1KB display

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "01.square")
                    .foregroundStyle(.purple)
                Text("Binary Data")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(data.count) bytes")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Column headers
                    HStack(spacing: 0) {
                        Text("Offset")
                            .frame(width: 60, alignment: .leading)
                        Text("00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F")
                            .frame(width: 380, alignment: .leading)
                        Text("ASCII")
                            .frame(width: 140, alignment: .leading)
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 4)

                    // Data rows
                    let totalRows = min((data.count + bytesPerRow - 1) / bytesPerRow, maxRows)
                    ForEach(0..<totalRows, id: \.self) { rowIndex in
                        HexRow(data: data, rowIndex: rowIndex, bytesPerRow: bytesPerRow)
                    }

                    if data.count > maxRows * bytesPerRow {
                        Text("... \(data.count - maxRows * bytesPerRow) more bytes truncated")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
}

/// Single row in hex dump view
struct HexRow: View {
    let data: Data
    let rowIndex: Int
    let bytesPerRow: Int

    var body: some View {
        let startOffset = rowIndex * bytesPerRow
        let endOffset = min(startOffset + bytesPerRow, data.count)
        let rowData = data[startOffset..<endOffset]

        HStack(spacing: 0) {
            // Offset
            Text(String(format: "%06X", startOffset))
                .frame(width: 60, alignment: .leading)
                .foregroundStyle(.blue)

            // Hex bytes
            HStack(spacing: 0) {
                ForEach(0..<bytesPerRow, id: \.self) { i in
                    let byteIndex = startOffset + i
                    if byteIndex < data.count {
                        Text(String(format: "%02X ", data[byteIndex]))
                            .foregroundStyle(isPrintable(data[byteIndex]) ? .primary : .secondary)
                    } else {
                        Text("   ")
                    }
                    if i == 7 {
                        Text(" ")
                    }
                }
            }
            .frame(width: 380, alignment: .leading)

            // ASCII
            Text(asciiRepresentation(rowData))
                .frame(width: 140, alignment: .leading)
                .foregroundStyle(.green.opacity(0.8))
        }
        .font(.system(size: 9, design: .monospaced))
    }

    private func isPrintable(_ byte: UInt8) -> Bool {
        byte >= 32 && byte < 127
    }

    private func asciiRepresentation(_ data: Data.SubSequence) -> String {
        String(data.map { isPrintable($0) ? Character(UnicodeScalar($0)) : "." })
    }
}
