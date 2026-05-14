import Flutter
import UIKit
import Foundation

/**
 * FlutterLlamaPlugin - плагин для работы с llama.cpp моделями на iOS
 * 
 * Поддерживает:
 * - Загрузку GGUF моделей
 * - GPU ускорение через Metal
 * - Потоковую и обычную генерацию
 */
@available(iOS 13.0, *)
public class FlutterLlamaPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var modelLoaded = false
    private var modelPath: String?
    private let queue = DispatchQueue(label: "net.nativemind.flutter_llama", qos: .userInitiated)
    private var eventSink: FlutterEventSink?
    private var shouldStop = false
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_llama",
            binaryMessenger: registrar.messenger()
        )
        
        let eventChannel = FlutterEventChannel(
            name: "flutter_llama/stream",
            binaryMessenger: registrar.messenger()
        )
        
        let instance = FlutterLlamaPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
        
        NSLog("[FlutterLlama] Plugin registered")
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            loadModel(call: call, result: result)
        case "generate":
            generate(call: call, result: result)
        case "generateStream":
            generateStream(call: call, result: result)
        case "unloadModel":
            unloadModel(result: result)
        case "getModelInfo":
            getModelInfo(result: result)
        case "stopGeneration":
            stopGeneration(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        shouldStop = true
        return nil
    }
    
    // MARK: - Load Model
    
    private func loadModel(call: FlutterMethodCall, result: @escaping FlutterResult) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let args = call.arguments as? [String: Any],
                  let modelPath = args["modelPath"] as? String else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INVALID_ARGS",
                        message: "Missing required arguments",
                        details: nil
                    ))
                }
                return
            }
            
            let nThreads = args["nThreads"] as? Int ?? 4
            let nGpuLayers = args["nGpuLayers"] as? Int ?? 0
            let contextSize = args["contextSize"] as? Int ?? 2048
            let batchSize = args["batchSize"] as? Int ?? 512
            let useGpu = args["useGpu"] as? Bool ?? true
            let verbose = args["verbose"] as? Bool ?? false
            
            // Check if model file exists
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: modelPath) else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "MODEL_NOT_FOUND",
                        message: "Model file not found: \(modelPath)",
                        details: nil
                    ))
                }
                return
            }
            
            self.modelPath = modelPath
            
            // Initialize model through llama.cpp C++ bridge
            let success = llama_init_model(
                modelPath,
                Int32(nThreads),
                Int32(nGpuLayers),
                Int32(contextSize),
                Int32(batchSize),
                useGpu,
                verbose
            )
            
            self.modelLoaded = success
            
            DispatchQueue.main.async {
                if success {
                    NSLog("[FlutterLlama] Model loaded: \(modelPath)")
                    NSLog("[FlutterLlama] GPU layers: \(nGpuLayers), threads: \(nThreads), context: \(contextSize)")
                    result(true)
                } else {
                    result(FlutterError(
                        code: "INIT_FAILED",
                        message: "Failed to initialize model",
                        details: nil
                    ))
                }
            }
        }
    }
    
    // MARK: - Generate (blocking)
    
    private func generate(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard modelLoaded else {
            result(FlutterError(
                code: "MODEL_NOT_LOADED",
                message: "Model not loaded",
                details: nil
            ))
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let args = call.arguments as? [String: Any],
                  let prompt = args["prompt"] as? String else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INVALID_ARGS",
                        message: "Missing prompt",
                        details: nil
                    ))
                }
                return
            }
            
            let temperature = (args["temperature"] as? Double) ?? 0.8
            let topP = (args["topP"] as? Double) ?? 0.95
            let topK = (args["topK"] as? Int) ?? 40
            let maxTokens = (args["maxTokens"] as? Int) ?? 512
            let repeatPenalty = (args["repeatPenalty"] as? Double) ?? 1.1
            
            self.shouldStop = false
            let startTime = Date()
            
            // Generate through llama.cpp C++ bridge
            var outputBuffer = [CChar](repeating: 0, count: 16384)
            var tokensGenerated: Int32 = 0
            
            let success = llama_generate(
                prompt,
                Float(temperature),
                Float(topP),
                Int32(topK),
                Int32(maxTokens),
                Float(repeatPenalty),
                &outputBuffer,
                Int32(outputBuffer.count),
                &tokensGenerated
            )
            
            let generationTime = Int(Date().timeIntervalSince(startTime) * 1000)
            
            DispatchQueue.main.async {
                if success {
                    let responseText = String(cString: outputBuffer)
                    let response: [String: Any] = [
                        "text": responseText,
                        "tokensGenerated": Int(tokensGenerated),
                        "generationTimeMs": generationTime
                    ]
                    NSLog("[FlutterLlama] Generated: \(tokensGenerated) tokens in \(generationTime)ms")
                    result(response)
                } else {
                    result(FlutterError(
                        code: "GENERATION_FAILED",
                        message: "Failed to generate response",
                        details: nil
                    ))
                }
            }
        }
    }
    
    // MARK: - Generate Stream
    
    private func generateStream(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard modelLoaded else {
            result(FlutterError(
                code: "MODEL_NOT_LOADED",
                message: "Model not loaded",
                details: nil
            ))
            return
        }
        
        guard let eventSink = self.eventSink else {
            result(FlutterError(
                code: "NO_EVENT_SINK",
                message: "Event channel not initialized",
                details: nil
            ))
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let args = call.arguments as? [String: Any],
                  let prompt = args["prompt"] as? String else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INVALID_ARGS",
                        message: "Missing prompt",
                        details: nil
                    ))
                }
                return
            }
            
            let temperature = (args["temperature"] as? Double) ?? 0.8
            let topP = (args["topP"] as? Double) ?? 0.95
            let topK = (args["topK"] as? Int) ?? 40
            let maxTokens = (args["maxTokens"] as? Int) ?? 512
            let repeatPenalty = (args["repeatPenalty"] as? Double) ?? 1.1
            
            self.shouldStop = false
            
            // Initialize streaming generation
            llama_generate_stream_init(
                prompt,
                Float(temperature),
                Float(topP),
                Int32(topK),
                Int32(maxTokens),
                Float(repeatPenalty)
            )
            
            // Stream tokens one by one
            var tokenBuffer = [CChar](repeating: 0, count: 256)
            while !self.shouldStop {
                let hasMore = llama_generate_stream_next(&tokenBuffer, Int32(tokenBuffer.count))
                
                if hasMore {
                    let token = String(cString: tokenBuffer)
                    DispatchQueue.main.async {
                        eventSink(token)
                    }
                } else {
                    break
                }
            }
            
            llama_generate_stream_end()
            
            DispatchQueue.main.async {
                eventSink(FlutterEndOfEventStream)
                result(nil)
            }
        }
    }
    
    // MARK: - Unload Model
    
    private func unloadModel(result: @escaping FlutterResult) {
        if modelLoaded {
            llama_cpp_bridge_free_model()
            modelLoaded = false
            modelPath = nil
            NSLog("[FlutterLlama] Model unloaded")
        }
        result(nil)
    }
    
    // MARK: - Get Model Info
    
    private func getModelInfo(result: @escaping FlutterResult) {
        guard modelLoaded, let modelPath = modelPath else {
            result(nil)
            return
        }
        
        var nParams: Int64 = 0
        var nLayers: Int32 = 0
        var contextSize: Int32 = 0
        
        llama_get_model_info(&nParams, &nLayers, &contextSize)
        
        let info: [String: Any] = [
            "modelPath": modelPath,
            "nParams": nParams,
            "nLayers": nLayers,
            "contextSize": contextSize
        ]
        
        result(info)
    }
    
    // MARK: - Stop Generation
    
    private func stopGeneration(result: @escaping FlutterResult) {
        shouldStop = true
        llama_stop_generation()
        result(nil)
    }
}

// MARK: - C++ Bridge Function Declarations

// These functions will be implemented in llama_cpp_bridge.cpp
@_silgen_name("llama_init_model")
func llama_init_model(
    _ modelPath: String,
    _ nThreads: Int32,
    _ nGpuLayers: Int32,
    _ contextSize: Int32,
    _ batchSize: Int32,
    _ useGpu: Bool,
    _ verbose: Bool
) -> Bool

@_silgen_name("llama_generate")
func llama_generate(
    _ prompt: String,
    _ temperature: Float,
    _ topP: Float,
    _ topK: Int32,
    _ maxTokens: Int32,
    _ repeatPenalty: Float,
    _ output: UnsafeMutablePointer<CChar>,
    _ outputSize: Int32,
    _ tokensGenerated: UnsafeMutablePointer<Int32>
) -> Bool

@_silgen_name("llama_generate_stream_init")
func llama_generate_stream_init(
    _ prompt: String,
    _ temperature: Float,
    _ topP: Float,
    _ topK: Int32,
    _ maxTokens: Int32,
    _ repeatPenalty: Float
)

@_silgen_name("llama_generate_stream_next")
func llama_generate_stream_next(
    _ output: UnsafeMutablePointer<CChar>,
    _ outputSize: Int32
) -> Bool

@_silgen_name("llama_generate_stream_end")
func llama_generate_stream_end()

@_silgen_name("llama_get_model_info")
func llama_get_model_info(
    _ nParams: UnsafeMutablePointer<Int64>,
    _ nLayers: UnsafeMutablePointer<Int32>,
    _ contextSize: UnsafeMutablePointer<Int32>
)

@_silgen_name("llama_free_model")
func llama_cpp_bridge_free_model()

@_silgen_name("llama_stop_generation")
func llama_stop_generation()
