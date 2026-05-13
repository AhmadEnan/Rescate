package dev.rescate.sensor_availability

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.hardware.biometrics.BiometricManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.PowerManager

import androidx.annotation.NonNull

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class SensorAvailabilityPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "dev.rescate/sensor_availability")
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        try {
            when (call.method) {
                "listNativeSensors" -> result.success(listNativeSensors())
                "hasSystemFeature" -> {
                    val name = call.argument<String>("name") ?: ""
                    result.success(context.packageManager.hasSystemFeature(name))
                }
                "motionAvailability" -> result.success(motionAvailability())
                "cameraDepthCapability" -> result.success(cameraDepthCapability())
                "uwbRadarAvailability" -> result.success(uwbRadarAvailability())
                "biometryAvailability" -> result.success(biometryAvailability())
                "thermalAvailability" -> result.success(thermalAvailability())
                "microphoneAvailability" -> result.success(microphoneAvailability())
                "cameraList" -> result.success(cameraList())
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("SENSOR_AVAILABILITY_ERROR", t.message, null)
        }
    }

    private fun listNativeSensors(): List<Map<String, Any>> {
        val sm = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
            ?: return emptyList()
        return sm.getSensorList(Sensor.TYPE_ALL).map { s ->
            mapOf(
                "type" to s.type,
                "name" to (s.name ?: ""),
                "vendor" to (s.vendor ?: "")
            )
        }
    }

    private fun motionAvailability(): Map<String, Boolean> {
        val sm = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val accel = sm?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null
        val gyro = sm?.getDefaultSensor(Sensor.TYPE_GYROSCOPE) != null
        val mag = sm?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) != null
        val baro = sm?.getDefaultSensor(Sensor.TYPE_PRESSURE) != null
        return mapOf("accel" to accel, "gyro" to gyro, "mag" to mag, "baro" to baro)
    }

    private fun cameraDepthCapability(): Map<String, Boolean> {
        var hasDepth = false
        var hasToF = false
        try {
            val cm = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            if (cm != null) {
                for (id in cm.cameraIdList) {
                    val cc = cm.getCameraCharacteristics(id)
                    val capabilities = cc.get(
                        CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES
                    )
                    if (capabilities != null) {
                        for (cap in capabilities) {
                            if (cap == CameraCharacteristics
                                    .REQUEST_AVAILABLE_CAPABILITIES_DEPTH_OUTPUT) {
                                hasDepth = true
                                hasToF = true
                            }
                        }
                    }
                }
            }
        } catch (_: Throwable) {
            // ignore — leave defaults
        }
        return mapOf(
            "hasDepthOutputCamera" to hasDepth,
            "hasToF" to hasToF,
            "hasLidar" to false // Android phones don't ship Apple-style LiDAR
        )
    }

    private fun uwbRadarAvailability(): Map<String, Boolean> {
        val pm = context.packageManager
        val uwb = pm.hasSystemFeature("android.hardware.uwb")
        // Soli radar lives on a small set of Pixels and is not exposed by a public
        // PackageManager feature flag. We use a known-device list as a heuristic.
        val radar = isKnownRadarDevice()
        return mapOf("uwb" to uwb, "radar" to radar)
    }

    private fun isKnownRadarDevice(): Boolean {
        val model = (Build.MODEL ?: "").lowercase()
        val device = (Build.DEVICE ?: "").lowercase()
        // Pixel 4 / 4 XL: "pixel 4", "pixel 4 xl"; Pixel 10 Pro family
        return listOf("pixel 4", "pixel 10 pro").any {
            model.contains(it) || device.contains(it)
        }
    }

    private fun biometryAvailability(): Map<String, Boolean> {
        val pm = context.packageManager
        val fingerprintFeature = pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)
        val faceFeature = if (Build.VERSION.SDK_INT >= 29) {
            pm.hasSystemFeature(PackageManager.FEATURE_FACE)
        } else false
        val irisFeature = if (Build.VERSION.SDK_INT >= 29) {
            pm.hasSystemFeature(PackageManager.FEATURE_IRIS)
        } else false

        var faceStrong = false
        if (Build.VERSION.SDK_INT >= 30 && faceFeature) {
            try {
                val bm = context.getSystemService(BiometricManager::class.java)
                if (bm != null) {
                    val canStrong = bm.canAuthenticate(
                        BiometricManager.Authenticators.BIOMETRIC_STRONG
                    )
                    faceStrong = canStrong == BiometricManager.BIOMETRIC_SUCCESS
                }
            } catch (_: Throwable) {
                // leave faceStrong false
            }
        }

        return mapOf(
            "fingerprint" to fingerprintFeature,
            "face" to faceFeature,
            "iris" to irisFeature,
            "faceStrongGuarantee" to faceStrong
        )
    }

    private fun thermalAvailability(): Map<String, Any> {
        val supported = if (Build.VERSION.SDK_INT >= 29) {
            try {
                val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                pm != null && pm.currentThermalStatus >= PowerManager.THERMAL_STATUS_NONE
            } catch (_: Throwable) {
                false
            }
        } else false
        return mapOf("thermistor" to supported)
    }

    private fun microphoneAvailability(): Map<String, Boolean> {
        val pm = context.packageManager
        return mapOf("available" to pm.hasSystemFeature(PackageManager.FEATURE_MICROPHONE))
    }

    private fun cameraList(): List<String> {
        return try {
            val cm = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            cm?.cameraIdList?.toList() ?: emptyList()
        } catch (_: Throwable) {
            emptyList()
        }
    }
}
