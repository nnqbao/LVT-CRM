import Foundation

/// Bounded, security-scoped read of a picked workbook (roster XLSX import in Danh mục / Học sinh).
enum WorkbookFile {
    static func read(url: URL, maxBytes: Int) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var result: Result<Data, Error> = .failure(ConvexException(code: "IMPORT_READ_FAILED"))
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            result = Result {
                try boundedRead(url: target, maxBytes: maxBytes)
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Reads at most `maxBytes + 1` bytes so an oversize file is detectable without loading it all.
    static func boundedRead(url: URL, maxBytes: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var bytes = Data()
        while bytes.count <= maxBytes {
            guard let chunk = try file.read(upToCount: min(8192, maxBytes + 1 - bytes.count)), !chunk.isEmpty else { break }
            bytes.append(chunk)
        }
        return bytes
    }
}

/// Upload/import requests never follow redirects.
final class UploadRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
