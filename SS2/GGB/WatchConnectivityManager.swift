import Foundation
import WatchConnectivity
import os

class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    private let logger = Logger(subsystem: "generouscorp.ggb", category: "iOS")
    private let dataInteractor = SharedDataInteractor()
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    // Required WCSessionDelegate methods for iOS
    func sessionDidBecomeInactive(_ session: WCSession) {
        logger.notice("⚠️ WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        logger.notice("⚠️ WCSession deactivated")
        WCSession.default.activate()
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            logger.error("❌ WCSession activation failed: \(error.localizedDescription)")
            return
        }
        logger.notice("✅ WCSession activated with state: \(activationState.rawValue)")
    }
    
    // Handle watch requests
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        logger.notice("📥 Received message from Watch: \(message)")
        
        if message["type"] as? String == "requestData",
           message["request"] as? String == "weatherData" {
            Task {
                do {
                    // 1. Get the cached weather data
                    guard let weatherData = try await dataInteractor.loadWeatherData() else {
                        logger.error("❌ No weather data available in cache")
                        replyHandler(["status": "error", "message": "No data available"])
                        return
                    }
                    
                    // 2. Encode the data
                    guard let encodedData = try? JSONEncoder().encode(weatherData) else {
                        logger.error("❌ Failed to encode weather data")
                        replyHandler(["status": "error", "message": "Failed to encode data"])
                        return
                    }
                    
                    // 3. Calculate chunks
                    let chunkSize = message["chunkSize"] as? Int ?? 16384
                    let chunks = encodedData.chunks(ofSize: chunkSize)
                    logger.notice("📦 Preparing to send \(chunks.count) chunks of size \(chunkSize)")
                    
                    // 4. Send start transfer message
                    replyHandler(["status": "ready", "chunks": chunks.count])
                    
                    // 5. Send chunks with delay to prevent overwhelming
                    for (index, chunk) in chunks.enumerated() {
                        if index > 0 {
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay between chunks
                        }
                        
                        session.sendMessage(
                            ["type": "chunk", "data": chunk, "index": index],
                            replyHandler: { reply in
                                self.logger.notice("✅ Chunk \(index + 1)/\(chunks.count) sent: \(reply)")
                            },
                            errorHandler: { error in
                                self.logger.error("❌ Error sending chunk \(index + 1): \(error.localizedDescription)")
                            }
                        )
                    }
                } catch {
                    logger.error("❌ Failed to process weather data request: \(error.localizedDescription)")
                    replyHandler(["status": "error", "message": error.localizedDescription])
                }
            }
        }
    }
}

// Helper extension for chunking data
private extension Data {
    func chunks(ofSize size: Int) -> [Data] {
        stride(from: 0, to: count, by: size).map {
            self[$0..<Swift.min($0 + size, count)]
        }
    }
}