import Foundation
import Logging

final class LogsCache<T: Codable> {

  private let isDebug: Bool
  private let maximumNumberOfLogsToPopAtOnce = 100

  private let queue = DispatchQueue(
    label: "co.binaryscraping.supabase-log-cache", attributes: .concurrent)
  private var cachedLogs: [T] = []

  func push(_ log: T) {
    queue.sync { self.cachedLogs.append(log) }
  }

  func push(_ logs: [T]) {
    queue.sync { self.cachedLogs.append(contentsOf: logs) }
  }

  func pop() -> [T] {
    var poppedLogs: [T] = []
    queue.sync(flags: .barrier) {
      let sliceSize = min(maximumNumberOfLogsToPopAtOnce, cachedLogs.count)
      poppedLogs = Array(cachedLogs[..<sliceSize])
      cachedLogs.removeFirst(sliceSize)
    }
    return poppedLogs
  }
    
    func backupCache() {
        queue.sync(flags: .barrier) {
            do {
                let jsonCompatibleLogs = cachedLogs.map { log -> [String: Any] in
                    if let logEntry = log as? LogEntry {
                        return [
                            "label": logEntry.label,
                            "file": logEntry.file,
                            "line": logEntry.line,  
                            "source": logEntry.source,
                            "function": logEntry.function,
                            "level": logEntry.level,
                            "message": logEntry.message,
                            "loggedAt": ISO8601DateFormatter().string(from: logEntry.loggedAt), // Convert Date to String
                            "metadata": makeJSONCompatible(logEntry.metadata ?? [:])
                        ]
                    }
                    return [:] // Return an empty dictionary if conversion fails
                }
                
                if JSONSerialization.isValidJSONObject(jsonCompatibleLogs) {
                    let data = try JSONSerialization.data(withJSONObject: jsonCompatibleLogs, options: .prettyPrinted)
                    try data.write(to: LogsCache.fileURL())
                } else {
                    print("Error saving logs to cache.  Logs are not json compatiable.  Discarding")
                    let invalidElements = findInvalidElements(in: jsonCompatibleLogs)
                    print("Invalid JSON elements found at paths:")
                    invalidElements.forEach { print($0) }
                }
                
                self.cachedLogs = []

            } catch {
                if isDebug {
                    print("Error saving logs to cache: \(error.localizedDescription)")
                    print("Error details: \(error)")
                }
            }
        }
    }
    
    func makeJSONCompatible(_ metadata: Logger.Metadata) -> [String: Any] {
        var jsonCompatibleDict: [String: Any] = [:]
        
        for (key, value) in metadata {
            jsonCompatibleDict[key] = unpackMetadataValue(value)
        }
        
        return jsonCompatibleDict
    }

    func unpackMetadataValue(_ value: Logger.MetadataValue) -> Any {
        switch value {
        case .string(let str):
            return str
        case .stringConvertible(let convertible):
            return convertible.description
        case .array(let array):
            return array.map { unpackMetadataValue($0) }
        case .dictionary(let dict):
            return makeJSONCompatible(dict)
        }
    }
    
    func findInvalidElements(in object: Any, path: String = "") -> [String] {
        var invalidPaths = [String]()
        
        if JSONSerialization.isValidJSONObject(object) {
            return invalidPaths
        }
        
        if let array = object as? [Any] {
            for (index, element) in array.enumerated() {
                let newPath = "\(path)[\(index)]"
                invalidPaths.append(contentsOf: findInvalidElements(in: element, path: newPath))
            }
        } else if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                let newPath = path.isEmpty ? key : "\(path).\(key)"
                invalidPaths.append(contentsOf: findInvalidElements(in: value, path: newPath))
            }
        } else if !(object is String || object is NSNumber || object is NSNull) {
            invalidPaths.append(path)
        }
        
        return invalidPaths
    }
    
  private static func fileURL() throws -> URL {
    try FileManager.default.url(
      for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false
    )
    .appendingPathComponent("supabase-log-cache")
  }

  init(isDebug: Bool) {
    self.isDebug = isDebug
    do {
      let data = try Data(contentsOf: LogsCache.fileURL())
      try FileManager.default.removeItem(at: LogsCache.fileURL())

      let logs = try decoder.decode([T].self, from: data)
      self.cachedLogs = logs
    } catch {
      if isDebug {
          print("Error recovering logs from cache: \(error.localizedDescription)")
          print("Error details: \(error)")
      }
    }
  }
}
