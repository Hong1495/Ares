import Foundation
import Compression
import zlib

/// Captured HTTP data from MITM interception
nonisolated struct MITMInterceptedData: Sendable {
    var id: String
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

nonisolated enum HTTPParser {
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
        
        while offset < data.count {
            // Find the CRLF that ends the chunk size line
            let searchRange = offset..<data.count
            guard let crlfIndex = data.range(of: crlf, in: searchRange)?.lowerBound else {
                break
            }
            
            // Extract chunk size line (as hex string)
            let sizeLineData = data[offset..<crlfIndex]
            guard let sizeLine = String(data: Data(sizeLineData), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) else {
                break
            }
            
            // Parse hex size (handle chunk extensions after semicolon)
            let sizeHex = sizeLine.split(separator: ";").first.map(String.init) ?? sizeLine
            guard let chunkSize = Int(sizeHex, radix: 16), chunkSize >= 0 else {
                break
            }
            
            // End of chunked data
            if chunkSize == 0 {
                break
            }
            
            // Move past the size line and CRLF
            let chunkStart = crlfIndex + 2
            let chunkEnd = chunkStart + chunkSize
            
            // Check if we have enough data for this chunk
            guard chunkEnd <= data.count else {
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
        return success ? result : nil
    }
    
    /// Decompress gzip/deflate encoded data using zlib
    static func decompressGzip(_ data: Data) -> Data? {
        // Minimum valid gzip is 18 bytes (10 header + 8 trailer)
        guard data.count >= 18 else {
            return nil
        }
        
        // Verify gzip magic bytes
        guard data[0] == 0x1F && data[1] == 0x8B else {
            return nil
        }
        
        // Standard zlib decompression with windowBits = 31 (16 + 15)
        // This effectively enables gzip header detection and decoding
        return data.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) -> Data? in
            guard let inputBaseAddress = inputBytes.baseAddress else { return nil }
            
            var stream = z_stream()
            // Initialize with windowBits = 31 (15 + 16) to automatically detect gzip/zlib
            // Use zlibVersion() function instead of ZLIB_VERSION macro for Swift compatibility
            let initResult = inflateInit2_(&stream, 31, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
            if initResult != Z_OK {
                return nil
            }
            defer { inflateEnd(&stream) }
            
            stream.next_in = UnsafeMutablePointer(mutating: inputBaseAddress.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = UInt32(data.count)
            
            var decompressed = Data(capacity: data.count * 4) // Estimate 4x compression ratio
            let bufferSize = 64 * 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            
            var iterations = 0
            let maxIterations = 1000 // Safety limit
            
            while iterations < maxIterations {
                iterations += 1
                stream.next_out = buffer
                stream.avail_out = UInt32(bufferSize)
                
                let status = inflate(&stream, Z_NO_FLUSH)
                
                let bytesRead = bufferSize - Int(stream.avail_out)
                if bytesRead > 0 {
                    decompressed.append(buffer, count: bytesRead)
                }
                
                if status == Z_STREAM_END {
                    break // Successfully decompressed
                } else if status == Z_OK {
                    // Continue decompressing
                    if stream.avail_in == 0 {
                        break // No more input
                    }
                } else if status == Z_BUF_ERROR {
                    // No progress possible - likely incomplete data
                    break
                } else {
                    // Z_DATA_ERROR, Z_MEM_ERROR, etc.
                    return nil
                }
            }
            
            // Return nil if decompression produced no output
            if decompressed.isEmpty {
                return nil
            }
            return decompressed
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
    
    /// Maximum body size to capture (256KB - increased for larger responses)
    static let maxBodyCapture = 256 * 1024
}
