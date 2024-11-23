import Foundation
import UIKit

class NetworkManager {
    static let shared = NetworkManager()
    private let baseURL = "http://54.164.209.236"
    
    func trainShape(image: UIImage, label: String) async throws -> String {
        guard let imageData = image.pngData() else {
            throw NetworkError.invalidImage
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "\(baseURL)/train?label=\(label)")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"drawing.png\"\r\n")
        body.append("Content-Type: image/png\r\n\r\n")
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n")
        
        request.httpBody = body
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw NetworkError.serverError(statusCode: httpResponse.statusCode)
            }
            
            let decodedResponse = try JSONDecoder().decode(TrainingResponse.self, from: data)
            return "\(decodedResponse.message) (Total: \(decodedResponse.total_samples))"
        } catch {
            print("Network error: \(error.localizedDescription)")
            throw error
        }
    }
    
    func predictShape(image: UIImage) async throws -> String {
        guard let imageData = image.pngData() else {
            throw NetworkError.invalidImage
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "\(baseURL)/predict")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"drawing.png\"\r\n")
        body.append("Content-Type: image/png\r\n\r\n")
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n")
        
        request.httpBody = body
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw NetworkError.serverError(statusCode: httpResponse.statusCode)
            }
            
            let prediction = try JSONDecoder().decode(PredictionResponse.self, from: data)
            return """
            KNN: \(prediction.knn_prediction) (\(Int(prediction.knn_confidence * 100))%)
            SVM: \(prediction.svm_prediction) (\(Int(prediction.svm_confidence * 100))%)
            """
        } catch {
            print("Network error: \(error.localizedDescription)")
            throw error
        }
    }
}

enum NetworkError: Error {
    case invalidImage
    case invalidResponse
    case serverError(statusCode: Int)
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

struct TrainingResponse: Codable {
    let status: String
    let message: String
    let total_samples: Int
}

struct PredictionResponse: Codable {
    let knn_prediction: String
    let knn_confidence: Double
    let svm_prediction: String
    let svm_confidence: Double
}
