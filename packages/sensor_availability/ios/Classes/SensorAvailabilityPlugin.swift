import Flutter
import UIKit
import CoreMotion
import AVFoundation
import LocalAuthentication

#if canImport(ARKit)
import ARKit
#endif

#if canImport(NearbyInteraction)
import NearbyInteraction
#endif

public class SensorAvailabilityPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "dev.rescate/sensor_availability",
            binaryMessenger: registrar.messenger()
        )
        let instance = SensorAvailabilityPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "listNativeSensors":
            // iOS does not expose a sensor enumeration API. Return empty list.
            result([])
        case "hasSystemFeature":
            // No equivalent on iOS — always false.
            result(false)
        case "motionAvailability":
            result(motionAvailability())
        case "cameraDepthCapability":
            result(cameraDepthCapability())
        case "uwbRadarAvailability":
            result(uwbRadarAvailability())
        case "biometryAvailability":
            result(biometryAvailability())
        case "thermalAvailability":
            // No public iOS API for thermistor presence — null map.
            result(["thermistor": NSNull()])
        case "microphoneAvailability":
            let session = AVAudioSession.sharedInstance()
            result(["available": session.isInputAvailable])
        case "cameraList":
            result(cameraList())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func motionAvailability() -> [String: Bool] {
        let mm = CMMotionManager()
        var baro = false
        if #available(iOS 11.0, *) {
            baro = CMAltimeter.isRelativeAltitudeAvailable()
        }
        return [
            "accel": mm.isAccelerometerAvailable,
            "gyro": mm.isGyroAvailable,
            "mag": mm.isMagnetometerAvailable,
            "baro": baro
        ]
    }

    private func cameraDepthCapability() -> [String: Bool] {
        var hasLidar = false
        var hasDepth = false
        var hasToF = false
        #if canImport(ARKit)
        if #available(iOS 13.4, *) {
            hasLidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        }
        if #available(iOS 14.0, *) {
            hasDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        }
        // ToF on iOS effectively means LiDAR for now.
        hasToF = hasLidar
        #endif
        return [
            "hasDepthOutputCamera": hasDepth,
            "hasToF": hasToF,
            "hasLidar": hasLidar
        ]
    }

    private func uwbRadarAvailability() -> [String: Bool] {
        var uwb = false
        #if canImport(NearbyInteraction)
        if #available(iOS 14.0, *) {
            uwb = NISession.isSupported
        }
        #endif
        return ["uwb": uwb, "radar": false]
    }

    private func biometryAvailability() -> [String: Bool] {
        let ctx = LAContext()
        var error: NSError?
        let canEvaluate = ctx.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        var fingerprint = false
        var face = false
        var faceStrong = false
        if canEvaluate {
            if #available(iOS 11.0, *) {
                switch ctx.biometryType {
                case .faceID:
                    face = true
                    faceStrong = true // Apple Face ID is class-3 equivalent
                case .touchID:
                    fingerprint = true
                default:
                    break
                }
            } else {
                fingerprint = true // pre-iOS 11 was always Touch ID
            }
        }
        return [
            "fingerprint": fingerprint,
            "face": face,
            "iris": false,
            "faceStrongGuarantee": faceStrong
        ]
    }

    private func cameraList() -> [String] {
        if #available(iOS 10.0, *) {
            return AVCaptureDevice.devices(for: .video).map { $0.uniqueID }
        }
        return []
    }
}
