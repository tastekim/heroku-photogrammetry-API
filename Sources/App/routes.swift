import Vapor
import Alamofire


func routes(_ app: Application) throws {
    app.on(.POST, "upload", body: .collect(maxSize: "2gb")) { req async throws -> String in
        struct Input: Content {
            var files: [File]
        }
        let input = try req.content.decode(Input.self)
        
        guard let result = await PhotogrammetryManager.instance.startObjectCapture(input.files) else {
            throw Abort(.internalServerError)
        }
        return result.uuidString
    }
    // Note: EventLoopFuture is a temporary solution to use async/await until Vapor 5 completes async/await integration
    app.webSocket("progress") { req, ws async -> () in
        guard let idStr = req.query[String.self, at: "id"],
              let id = UUID(uuidString: idStr)
        else { try? await ws.close(code: .unacceptableData); return }
        Hack.lastProgress = 0
        
        // Should subscribe for changes but this is good enough for demo
        let repeatedTask = req.eventLoop.scheduleRepeatedTask(initialDelay: .zero, delay: .seconds(1)) { _ in
            Task {
                guard let progress = PhotogrammetryManager.instance.getProgress(id) else {
                    try await ws.send("Job failed")
                    try await ws.close(code: .unacceptableData) // Not an existing job ID
                    return
                }
                
                if progress.error != nil {
                    try await ws.send("Job failed")
                    try await ws.close(code: .normalClosure)
                } else if progress.result != nil {
                    try await ws.send("Job complete")
                    try await ws.close(code: .normalClosure)
                } else if (progress.progress != Hack.lastProgress) {
                    Hack.lastProgress = progress.progress
                    try await ws.send("\(progress.progress)%")
                }
            }
        }
        
        ws.onClose.whenComplete { _ in
            repeatedTask.cancel()
        }
    }
    
    app.get("result") { req -> Response in
        guard let idStr = req.query[String.self, at: "id"],
              let id = UUID(uuidString: idStr),
              let progress = PhotogrammetryManager.instance.getProgress(id)
        else { throw Abort(.badRequest) }
        
        if progress.error != nil {
            throw Abort(.internalServerError)
        }
        
        if progress.result == nil {
            throw Abort(.processing)
        }
        
        print("Result found. Reading file.")
        
        guard let fileUrl = progress.fileUrl else { throw Abort(.internalServerError) }
    
        print("파일위치 \(fileUrl.path)")
        
        let fileURL = URL(fileURLWithPath: fileUrl.path)
        print("파일유알엘 \(fileURL)")
        let usdzData = try! Data(contentsOf: fileURL)
        print("유에스디지 \(usdzData)")
  
        
        //AF 도오전
        let parameters: [String: Any] = [
            "name": "file.usdz",
            "user_id": 123,
        ]
        AF.upload(multipartFormData: { (multipartFormData) in
            multipartFormData.append(fileURL, withName: "file")
            for (key, value) in parameters {
                multipartFormData.append("\(value)".data(using: .utf8)!, withName: key)
            }
        }, to: "http://52.221.198.249:3000/usdz2glb")
            .response { response in
                if response.error == nil {
                    // File uploaded successfully
                    print("승긍")
                } else {
                    // Handle error
                    print("슬프")
                }
            }

        return req.fileio.streamFile(at: fileUrl.path)
    }
 
    
    app.get("health") { req -> String in
        return "Up!"
    }
    
    
    app.get("test") { req -> String in
        
        return "hi"
    }
}

class Hack {
    static var lastProgress: UInt = 0
}
