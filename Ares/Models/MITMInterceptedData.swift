import Foundation
import Compression

/// Captured HTTP data from MITM interception
struct MITMInterceptedData: Sendable {
    let id: String
    let host: String
    let method: String
    let path: String
    let url: String
    let timestamp: Date
    
    // Request data
    var requestHeaders: [String: String]?
    var requestBody: Data?
    var requestSize: Int?
    
    // Response data (filled later)
    var statusCode: Int?
    var responseHeaders: [String: String]?
    var responseBody: Data?
    var responseSize: Int?
    
    // Timing
    var duration: Double?
    
    init(host: String, method: String, path: String) {
        self.id = UUID().uuidString
        self.host = host
        self.method = method
        self.path = path
        self.timestamp = Date()
        
        // Handle path that might already be a full URL (e.g. "http://..." or "/path")
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
            self.url = path
        } else {
            let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
            self.url = "https://\(host)\(normalizedPath)"
        }
    }
}

// MARK: - HTTP Parsing Utilities

enum HTTPParser {
    /// Separator pattern between HTTP headers and body
    private static let headerBodySeparator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
    
    /// Parse HTTP request from raw data
    static func parseRequest(_ data: Data) -> (method: String, path: String, headers: [String: String], bodyOffset: Int)? {
        // Find header/body boundary by searching for \r\n\r\n in raw bytes
        guard let separatorRange = data.range(of: headerBodySeparator) else {
            // No body separator found - might be incomplete data
            // Try to parse headers anyway if we have enough data
            guard let str = String(data: data, encoding: .utf8) else { return nil }
            let lines = str.components(separatedBy: "\r\n")
            guard let requestLine = lines.first else { return nil }
            
            let parts = requestLine.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else { return nil }
            
            return (method: String(parts[0]), path: String(parts[1]), headers: [:], bodyOffset: data.count)
        }
        
        // Convert Data.Index to integer offset from data start
        let bodyOffset = data.distance(from: data.startIndex, to: separatorRange.upperBound)
        let headerData = data[data.startIndex..<separatorRange.lowerBound]
        
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        
        let method = String(parts[0])
        let path = String(parts[1])
        
        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        return (method: method, path: path, headers: headers, bodyOffset: bodyOffset)
    }
    
    /// Parse HTTP response from raw data
    static func parseResponse(_ data: Data) -> (statusCode: Int, headers: [String: String], bodyOffset: Int)? {
        // Find header/body boundary by searching for \r\n\r\n in raw bytes
        guard let separatorRange = data.range(of: headerBodySeparator) else {
            // No body separator found - data might only contain headers (chunked encoding)
            // Try to parse status line at minimum
            guard let str = String(data: data, encoding: .utf8) else { return nil }
            let lines = str.components(separatedBy: "\r\n")
            guard let statusLine = lines.first else { return nil }
            
            let parts = statusLine.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2, let statusCode = Int(parts[1]) else { return nil }
            
            // Parse whatever headers we have
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                if line.isEmpty { break }
                if let colonIdx = line.firstIndex(of: ":") {
                    let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    headers[key] = value
                }
            }
            
            // No body available in this packet
            return (statusCode: statusCode, headers: headers, bodyOffset: data.count)
        }
        
        // Convert Data.Index to integer offset from data start
        let bodyOffset = data.distance(from: data.startIndex, to: separatorRange.upperBound)
        let headerData = data[data.startIndex..<separatorRange.lowerBound]
        
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { return nil }
        
        // Parse "HTTP/1.1 200 OK"
        let parts = statusLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, let statusCode = Int(parts[1]) else { return nil }
        
        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        return (statusCode: statusCode, headers: headers, bodyOffset: bodyOffset)
    }
    
    /// Check if content type is text-based (safe to capture body)
    static func isTextContent(_ contentType: String?) -> Bool {
        guard let ct = contentType?.lowercased() else { 
            // If no content type, assume it might be text (common for APIs)
            return true 
        }
        
        // Explicitly binary types to skip
        let binaryTypes = [
            // Media types
            "image/", "video/", "audio/",
            // Archives and compressed
            "application/octet-stream", "application/pdf", "application/zip", 
            "application/gzip", "application/x-tar", "application/x-rar",
            // Binary serialization formats
            "application/vnd.apple.flatbuffer", "application/x-protobuf",
            "application/x-google-protobuf", "application/protobuf",
            "application/msgpack", "application/x-msgpack",
            "application/cbor", "application/x-thrift",
            // Apple-specific binary
            "application/x-apple-aspen-mdm", "application/x-plist",
            // Font and other binary
            "font/", "application/font", "application/x-font"
        ]
        for bt in binaryTypes {
            if ct.contains(bt) { return false }
        }
        
        // All other types (text, json, xml, html, etc.) are captured
        return true
    }
    
    /// Decode chunked transfer-encoded body
    static func decodeChunkedBody(_ data: Data) -> Data? {
        let crlf = Data([0x0D, 0x0A])  // \r\n
        var result = Data()
        var offset = 0
        
        print("[HTTPParser] 🔍 Decoding chunked body (\(data.count) bytes)")
        
        while offset < data.count {
            // Find the CRLF that ends the chunk size line
            let searchRange = offset..<data.count
            guard let crlfIndex = data.range(of: crlf, in: searchRange)?.lowerBound else {
                print("[HTTPParser] ⚠️ No CRLF found after offset \(offset)")
                break
            }
            
            // Extract chunk size line (as hex string)
            let sizeLineData = data[offset..<crlfIndex]
            guard let sizeLine = String(data: Data(sizeLineData), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) else {
                print("[HTTPParser] ⚠️ Cannot parse size line as ASCII")
                break
            }
            
            // Parse hex size (handle chunk extensions after semicolon)
            let sizeHex = sizeLine.split(separator: ";").first.map(String.init) ?? sizeLine
            guard let chunkSize = Int(sizeHex, radix: 16), chunkSize >= 0 else {
                print("[HTTPParser] ⚠️ Invalid hex size: '\(sizeHex)'")
                break
            }
            
            // End of chunked data
            if chunkSize == 0 {
                print("[HTTPParser] ✅ Chunked decoding complete: \(result.count) bytes decoded")
                break
            }
            
            // Move past the size line and CRLF
            let chunkStart = crlfIndex + 2
            let chunkEnd = chunkStart + chunkSize
            
            // Check if we have enough data for this chunk
            guard chunkEnd <= data.count else {
                print("[HTTPParser] ⚠️ Incomplete chunk: need \(chunkSize), have \(data.count - chunkStart)")
                break
            }
            
            // Extract chunk data and convert to Data explicitly
            let chunkData = Data(data[chunkStart..<chunkEnd])
            result.append(chunkData)
            
            // Move past chunk data and trailing CRLF
            offset = chunkEnd
            if offset + 2 <= data.count && data[offset] == 0x0D && data[offset + 1] == 0x0A {
                offset += 2
            }
        }
        
        let success = !result.isEmpty
        print("[HTTPParser] \(success ? "✅" : "❌") Chunked decode result: \(result.count) bytes (input: \(data.count) bytes)")
        
        // Debug: verify the result is valid UTF-8
        if success {
            if let _ = String(data: result, encoding: .utf8) {
                print("[HTTPParser] ✅ Result is valid UTF-8")
            } else {
                print("[HTTPParser] ⚠️ Result is NOT valid UTF-8, first 20 bytes: \(result.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " "))")
            }
        }
        
        return success ? result : nil
    }
    
    /// Decompress gzip/deflate encoded data
    static func decompressGzip(_ data: Data) -> Data? {
        // Check for gzip magic bytes (1F 8B)
        guard data.count >= 2 else { return nil }
        let isGzip = data[0] == 0x1F && data[1] == 0x8B
        
        // Use zlib decompression
        var decompressed = Data()
        let bufferSize = 32_768
        
        // For gzip, skip the header and use raw inflate
        // For deflate, use raw inflate directly
        let inputData: Data
        if isGzip {
            // Skip gzip header (minimum 10 bytes)
            guard data.count > 10 else { return nil }
            
            // Parse gzip header to find where compressed data starts
            var offset = 10
            let flags = data[3]
            
            // FEXTRA
            if flags & 0x04 != 0 && offset + 2 <= data.count {
                let extraLen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
                offset += 2 + extraLen
            }
            // FNAME
            if flags & 0x08 != 0 {
                while offset < data.count && data[offset] != 0 { offset += 1 }
                offset += 1
            }
            // FCOMMENT
            if flags & 0x10 != 0 {
                while offset < data.count && data[offset] != 0 { offset += 1 }
                offset += 1
            }
            // FHCRC
            if flags & 0x02 != 0 { offset += 2 }
            
            guard offset < data.count - 8 else { return nil }
            inputData = data.subdata(in: offset..<(data.count - 8)) // Remove 8-byte trailer
        } else {
            inputData = data
        }
        
        // Use Compression framework
        let bufferPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { bufferPtr.deallocate() }
        
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        
        var status = compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(streamPtr) }
        
        return inputData.withUnsafeBytes { (inputPtr: UnsafeRawBufferPointer) -> Data? in
            guard let inputBaseAddress = inputPtr.baseAddress else { return nil }
            
            streamPtr.pointee.src_ptr = inputBaseAddress.assumingMemoryBound(to: UInt8.self)
            streamPtr.pointee.src_size = inputData.count
            streamPtr.pointee.dst_ptr = bufferPtr
            streamPtr.pointee.dst_size = bufferSize
            
            repeat {
                status = compression_stream_process(streamPtr, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                
                if status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END {
                    let bytesWritten = bufferSize - streamPtr.pointee.dst_size
                    decompressed.append(bufferPtr, count: bytesWritten)
                    streamPtr.pointee.dst_ptr = bufferPtr
                    streamPtr.pointee.dst_size = bufferSize
                }
            } while status == COMPRESSION_STATUS_OK
            
            guard status == COMPRESSION_STATUS_END else { return nil }
            return decompressed.isEmpty ? nil : decompressed
        }
    }
    
    /// Decompress Brotli encoded data
    static func decompressBrotli(_ data: Data) -> Data? {
        var decompressed = Data()
        let bufferSize = 32_768
        
        let bufferPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { bufferPtr.deallocate() }
        
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        
        var status = compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_BROTLI)
        guard status == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(streamPtr) }
        
        return data.withUnsafeBytes { rawBufferPointer -> Data? in
            guard let srcPtr = rawBufferPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            
            streamPtr.pointee.src_ptr = srcPtr
            streamPtr.pointee.src_size = data.count
            streamPtr.pointee.dst_ptr = bufferPtr
            streamPtr.pointee.dst_size = bufferSize
            
            repeat {
                status = compression_stream_process(streamPtr, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                
                if status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END {
                    let bytesWritten = bufferSize - streamPtr.pointee.dst_size
                    decompressed.append(bufferPtr, count: bytesWritten)
                    streamPtr.pointee.dst_ptr = bufferPtr
                    streamPtr.pointee.dst_size = bufferSize
                }
            } while status == COMPRESSION_STATUS_OK
            
            guard status == COMPRESSION_STATUS_END else { return nil }
            return decompressed.isEmpty ? nil : decompressed
        }
    }
    
    /// Maximum body size to capture (64KB)
    static let maxBodyCapture = 64 * 1024
}
