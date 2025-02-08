import Foundation

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
                            "metadata": logEntry.metadata // Assuming metadata is already JSON-compatible
                        ]
                    }
                    return [:] // Return an empty dictionary if conversion fails
                }

                let data = try JSONSerialization.data(withJSONObject: jsonCompatibleLogs, options: .prettyPrinted)
                try data.write(to: LogsCache.fileURL())
                self.cachedLogs = []
            } catch {
                if isDebug {
                    print("Error saving logs to cache: \(error.localizedDescription)")
                    print("Error details: \(error)")
                }
            }
        }
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
