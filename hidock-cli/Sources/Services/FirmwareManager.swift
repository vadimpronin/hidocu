import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Shared info struct
struct FirmwareInfo {
    let id: String
    let model: String
    let version: String
    let versionNumber: UInt32
    let signature: String
    let fileName: String
    let fileLength: Int
    let remark: String
    
    var downloadURL: String {
        return "https://hinotes.hidock.com/v2/device/firmware/get?id=\(id)"
    }
}

class FirmwareManager {
    
    private struct APIResponse: Codable {
        let error: Int
        let message: String
        let data: FirmwareData?
        
        struct FirmwareData: Codable {
            let id: String
            let model: String
            let versionCode: String
            let versionNumber: Int
            let signature: String
            let fileName: String
            let fileLength: Int
            let remark: String?
        }
    }
    
    static func fetchLatestFirmware(model: String, accessToken: String) -> Result<FirmwareInfo, Error> {
        let urlString = "https://hinotes.hidock.com/v2/device/firmware/latest"
        guard let url = URL(string: urlString) else {
           return .failure(NSError(domain: "FirmwareAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue(accessToken, forHTTPHeaderField: "AccessToken")
        
        let bodyString = "version=-1&model=\(model)&lang=en"
        request.httpBody = bodyString.data(using: .utf8)
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<FirmwareInfo, Error> = .failure(NSError(domain: "FirmwareAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timeout"]))
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                result = .failure(error)
                return
            }
            
            guard let data = data else {
                result = .failure(NSError(domain: "FirmwareAPI", code: 3, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                return
            }
            
            do {
                let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
                if apiResponse.error != 0 {
                     result = .failure(NSError(domain: "FirmwareAPI", code: apiResponse.error, userInfo: [NSLocalizedDescriptionKey: apiResponse.message]))
                     return
                }
                
                guard let fwData = apiResponse.data else {
                    result = .failure(NSError(domain: "FirmwareAPI", code: 4, userInfo: [NSLocalizedDescriptionKey: "No firmware data"]))
                    return
                }
                
                let info = FirmwareInfo(
                    id: fwData.id,
                    model: fwData.model,
                    version: fwData.versionCode,
                    versionNumber: UInt32(fwData.versionNumber),
                    signature: fwData.signature,
                    fileName: fwData.fileName,
                    fileLength: fwData.fileLength,
                    remark: fwData.remark ?? ""
                )
                result = .success(info)
                
            } catch {
                result = .failure(error)
            }
        }
        task.resume()
        semaphore.wait()
        
        return result
    }
    
    static func download(url: URL, progressHandler: @escaping (Int64, Int64) -> Void) -> Result<Data, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var downloadedData: Data?
        var downloadError: Error?
        
        // Internal delegate class
        class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
            var completion: ((URL?, Error?) -> Void)?
            var progress: ((Int64, Int64) -> Void)?
            
            func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
                completion?(location, nil)
            }
            
            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let error = error {
                    completion?(nil, error)
                }
            }
            
            func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
                progress?(totalBytesWritten, totalBytesExpectedToWrite)
            }
        }
        
        let delegate = DownloadDelegate()
        delegate.progress = progressHandler
        delegate.completion = { location, error in
            if let error = error {
                downloadError = error
            } else if let location = location {
                downloadedData = try? Data(contentsOf: location)
            }
            semaphore.signal()
        }
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        task.resume()
        semaphore.wait()
        
        if let error = downloadError {
            return .failure(error)
        }
        
        guard let data = downloadedData else {
            return .failure(NSError(domain: "Download", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download failed"]))
        }
        
        return .success(data)
    }
}
