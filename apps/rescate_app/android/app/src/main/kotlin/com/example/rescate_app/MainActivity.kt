package com.example.rescate_app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import com.graphhopper.GHRequest
import com.graphhopper.GraphHopper
import com.graphhopper.reader.osm.GraphHopperOSM
import com.graphhopper.config.CHProfile
import com.graphhopper.config.Profile
import com.graphhopper.routing.util.EncodingManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sqrt
import java.util.Locale
import com.graphhopper.util.shapes.GHPoint
import android.util.Log

class MainActivity : FlutterActivity() {
    private val channelName = "rescate/offline_routing"
    private var hopper: GraphHopper? = null

    private data class RoutePoint(val lat: Double, val lng: Double)
    private data class DangerZone(val lat: Double, val lng: Double, val radius: Double)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Android lacks a default StAX provider; pin Aalto so XMLInputFactory.newInstance() resolves.
        System.setProperty(
            "javax.xml.stream.XMLInputFactory",
            "com.fasterxml.aalto.stax.InputFactoryImpl",
        )
        System.setProperty(
            "javax.xml.stream.XMLOutputFactory",
            "com.fasterxml.aalto.stax.OutputFactoryImpl",
        )
        System.setProperty(
            "javax.xml.stream.XMLEventFactory",
            "com.fasterxml.aalto.stax.EventFactoryImpl",
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "findRoute" -> findRoute(call.arguments, result)
                    "prepareRoadGraph" -> prepareRoadGraph(call.arguments, result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.rescate/device_profile")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInfo" -> handleDeviceProfile(result)
                    "getFreeRam" -> handleFreeRam(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleFreeRam(result: MethodChannel.Result) {
        try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memInfo)
            result.success((memInfo.availMem / (1024L * 1024L)).toInt())
        } catch (e: Throwable) {
            result.error("FREE_RAM_ERROR", e.message, null)
        }
    }

    private fun handleDeviceProfile(result: MethodChannel.Result) {
        try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memInfo)
            val socModel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Build.SOC_MODEL
            } else {
                ""
            }
            val info: Map<String, Any?> = mapOf(
                "totalRamMb" to (memInfo.totalMem / (1024L * 1024L)),
                "availRamMb" to (memInfo.availMem / (1024L * 1024L)),
                "isLowRamDevice" to activityManager.isLowRamDevice,
                "socModel" to socModel,
                "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
            )
            result.success(info)
        } catch (e: Throwable) {
            result.error("DEVICE_PROFILE_ERROR", e.message, null)
        }
    }

    private fun prepareRoadGraph(arguments: Any?, result: MethodChannel.Result) {
        Thread {
            val success = try {
                val args = arguments as? Map<*, *> ?: return@Thread finish(result, false)
                val south = (args["south"] as Number).toDouble()
                val west = (args["west"] as Number).toDouble()
                val north = (args["north"] as Number).toDouble()
                val east = (args["east"] as Number).toDouble()
                downloadAndImportRoadGraph(south, west, north, east)
            } catch (t: Throwable) {
                Log.e("OfflineRouting", "prepareRoadGraph failed", t)
                false
            }
            finish(result, success)
        }.start()
    }

    private fun finish(result: MethodChannel.Result, value: Boolean) {
        runOnUiThread {
            result.success(value)
        }
    }

    private fun findRoute(arguments: Any?, result: MethodChannel.Result) {
        try {
            val args = arguments as? Map<*, *> ?: run {
                result.success(emptyList<Map<String, Double>>())
                return
            }

            val start = args["start"] as? Map<*, *> ?: run {
                result.success(emptyList<Map<String, Double>>())
                return
            }
            val destination = args["destination"] as? Map<*, *> ?: run {
                result.success(emptyList<Map<String, Double>>())
                return
            }

            val graphHopper = loadGraphHopper() ?: run {
                result.success(emptyList<Map<String, Double>>())
                return
            }

            val startPoint = RoutePoint(
                (start["lat"] as Number).toDouble(),
                (start["lng"] as Number).toDouble(),
            )
            val destinationPoint = RoutePoint(
                (destination["lat"] as Number).toDouble(),
                (destination["lng"] as Number).toDouble(),
            )
            val dangerZones = ((args["dangerZones"] as? List<*>) ?: emptyList<Any>())
                .mapNotNull { zone ->
                    val map = zone as? Map<*, *> ?: return@mapNotNull null
                    DangerZone(
                        (map["lat"] as Number).toDouble(),
                        (map["lng"] as Number).toDouble(),
                        (map["radius"] as Number).toDouble(),
                    )
                }

            val routePoints = findSafeRoute(graphHopper, startPoint, destinationPoint, dangerZones)
            if (routePoints.isEmpty()) {
                result.success(emptyList<Map<String, Double>>())
                return
            }

            val route = routePoints.map { point ->
                mapOf("lat" to point.lat, "lng" to point.lng)
            }
            result.success(route)
        } catch (error: Throwable) {
            result.success(emptyList<Map<String, Double>>())
        }
    }

    private fun findSafeRoute(
        graphHopper: GraphHopper,
        start: RoutePoint,
        destination: RoutePoint,
        dangerZones: List<DangerZone>,
    ): List<RoutePoint> {
        val directRoute = routeThrough(graphHopper, listOf(start, destination)) ?: return emptyList()
        if (firstDangerOnRoute(directRoute, dangerZones) == null) return directRoute

        val unsafeZones = dangerZones.filter { zone -> routeTouchesDanger(directRoute, zone) }
        val candidateWaypoints = mutableListOf<List<RoutePoint>>()

        for (zone in unsafeZones) {
            detourOptions(start, destination, zone).forEach { detour ->
                candidateWaypoints.add(listOf(start, detour, destination))
            }
        }

        if (unsafeZones.size > 1 && unsafeZones.size <= 5) {
            val leftDetours = mutableListOf(start)
            val rightDetours = mutableListOf(start)
            unsafeZones.forEach { zone ->
                val options = detourOptions(start, destination, zone)
                if (options.size >= 2) {
                    leftDetours.add(options[0])
                    rightDetours.add(options[1])
                }
            }
            leftDetours.add(destination)
            rightDetours.add(destination)
            candidateWaypoints.add(leftDetours)
            candidateWaypoints.add(rightDetours)
        }

        for (waypoints in candidateWaypoints) {
            val candidate = routeThrough(graphHopper, waypoints) ?: continue
            if (!routeTouchesAnyDanger(candidate, dangerZones)) return candidate
        }

        return emptyList()
    }

    private fun routeThrough(graphHopper: GraphHopper, points: List<RoutePoint>): List<RoutePoint>? {
        val request = GHRequest()
            .setProfile("car")
            .setLocale(Locale.US)

        points.forEach { point ->
            request.addPoint(GHPoint(point.lat, point.lng))
        }

        val response = graphHopper.route(request)
        if (response.hasErrors()) return null

        val pointList = response.best.points
        val route = mutableListOf<RoutePoint>()
        for (index in 0 until pointList.size()) {
            route.add(RoutePoint(pointList.getLat(index), pointList.getLon(index)))
        }
        return route
    }

    private fun firstDangerOnRoute(route: List<RoutePoint>, dangerZones: List<DangerZone>): DangerZone? {
        return dangerZones.firstOrNull { zone -> routeTouchesDanger(route, zone) }
    }

    private fun routeTouchesDanger(route: List<RoutePoint>, zone: DangerZone): Boolean {
        if (route.size < 2) return false
        val center = RoutePoint(zone.lat, zone.lng)
        for (index in 0 until route.size - 1) {
            if (segmentDistanceMeters(route[index], route[index + 1], center) <= zone.radius) {
                return true
            }
        }
        return false
    }

    private fun routeTouchesAnyDanger(route: List<RoutePoint>, dangerZones: List<DangerZone>): Boolean {
        return dangerZones.any { zone -> routeTouchesDanger(route, zone) }
    }

    private fun dangerScore(route: List<RoutePoint>, dangerZones: List<DangerZone>): Int {
        return dangerZones.sumOf { zone ->
            route.count { point -> distanceMeters(point, RoutePoint(zone.lat, zone.lng)) < zone.radius + 60.0 }
        }
    }

    private fun detourOptions(start: RoutePoint, destination: RoutePoint, zone: DangerZone): List<RoutePoint> {
        val center = RoutePoint(zone.lat, zone.lng)
        val dx = destination.lng - start.lng
        val dy = destination.lat - start.lat
        val length = sqrt(dx * dx + dy * dy)
        if (length == 0.0) return emptyList()

        val offsetDistances = listOf(zone.radius + 250.0, zone.radius + 500.0, zone.radius + 850.0)
        val metersPerLatDegree = 111_320.0
        val metersPerLngDegree = 111_320.0 * cos(Math.toRadians(zone.lat))
        val perpLat = dx / length
        val perpLng = -dy / length

        val options = mutableListOf<RoutePoint>()
        offsetDistances.forEach { offsetMeters ->
            options.add(
                RoutePoint(
                    center.lat + (perpLat * offsetMeters / metersPerLatDegree),
                    center.lng + (perpLng * offsetMeters / metersPerLngDegree),
                )
            )
            options.add(
                RoutePoint(
                    center.lat - (perpLat * offsetMeters / metersPerLatDegree),
                    center.lng - (perpLng * offsetMeters / metersPerLngDegree),
                )
            )
        }

        for (bearing in 0 until 360 step 45) {
            val radians = Math.toRadians(bearing.toDouble())
            val offsetMeters = zone.radius + 650.0
            options.add(
                RoutePoint(
                    center.lat + (kotlin.math.cos(radians) * offsetMeters / metersPerLatDegree),
                    center.lng + (kotlin.math.sin(radians) * offsetMeters / metersPerLngDegree),
                )
            )
        }

        return options
    }

    private fun distanceMeters(a: RoutePoint, b: RoutePoint): Double {
        val earthRadiusMeters = 6_371_000.0
        val dLat = Math.toRadians(b.lat - a.lat)
        val dLng = Math.toRadians(b.lng - a.lng)
        val lat1 = Math.toRadians(a.lat)
        val lat2 = Math.toRadians(b.lat)
        val haversine = kotlin.math.sin(dLat / 2) * kotlin.math.sin(dLat / 2) +
            kotlin.math.sin(dLng / 2) * kotlin.math.sin(dLng / 2) *
            kotlin.math.cos(lat1) * kotlin.math.cos(lat2)
        return 2 * earthRadiusMeters * kotlin.math.atan2(sqrt(haversine), sqrt(1 - haversine))
    }

    private fun segmentDistanceMeters(a: RoutePoint, b: RoutePoint, point: RoutePoint): Double {
        val metersPerLatDegree = 111_320.0
        val metersPerLngDegree = metersPerLatDegree * cos(Math.toRadians(point.lat))
        val ax = a.lng * metersPerLngDegree
        val ay = a.lat * metersPerLatDegree
        val bx = b.lng * metersPerLngDegree
        val by = b.lat * metersPerLatDegree
        val px = point.lng * metersPerLngDegree
        val py = point.lat * metersPerLatDegree
        val dx = bx - ax
        val dy = by - ay
        val lengthSquared = dx * dx + dy * dy
        if (lengthSquared == 0.0) return distanceMeters(a, point)
        val t = max(0.0, kotlin.math.min(1.0, (((px - ax) * dx) + ((py - ay) * dy)) / lengthSquared))
        val nearestX = ax + dx * t
        val nearestY = ay + dy * t
        return sqrt(((px - nearestX) * (px - nearestX)) + ((py - nearestY) * (py - nearestY)))
    }

    private fun downloadAndImportRoadGraph(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
    ): Boolean {
        val routingDir = File(filesDir, "offline_routing")
        if (!routingDir.exists()) routingDir.mkdirs()
        val graphDir = File(routingDir, "graph-cache")
        val osmFile = File(routingDir, "road-data.osm.xml")
        Log.i("OfflineRouting", "Downloading OSM bbox south=$south west=$west north=$north east=$east")
        val query =
            "[out:xml][timeout:120];(way[\"highway\"]($south,$west,$north,$east);>;);out body;"

        val connection = URL("https://overpass-api.de/api/interpreter").openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = 30_000
        connection.readTimeout = 180_000
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        connection.outputStream.use { stream ->
            stream.write("data=${URLEncoder.encode(query, "UTF-8")}".toByteArray())
        }
        if (connection.responseCode !in 200..299) {
            Log.e("OfflineRouting", "Overpass HTTP ${connection.responseCode}")
            return false
        }
        connection.inputStream.use { input ->
            osmFile.outputStream().use { output -> input.copyTo(output) }
        }
        Log.i("OfflineRouting", "Downloaded OSM file: ${osmFile.length()} bytes")
        if (!osmFile.exists() || osmFile.length() < 1024L) {
            Log.e("OfflineRouting", "OSM file too small or missing: ${osmFile.length()}")
            return false
        }

        hopper?.close()
        hopper = null
        if (graphDir.exists()) graphDir.deleteRecursively()
        graphDir.mkdirs()

        return try {
            GraphHopperOSM().apply {
                setDataReaderFile(osmFile.absolutePath)
                graphHopperLocation = graphDir.absolutePath
                encodingManager = EncodingManager.create("car")
                setProfiles(
                    Profile("car")
                        .setVehicle("car")
                        .setWeighting("fastest")
                        .setTurnCosts(false)
                )
                chPreparationHandler.setCHProfiles(CHProfile("car"))
                importOrLoad()
            }.also {
                hopper = it
            }
            Log.i("OfflineRouting", "GraphHopper graph built successfully at ${graphDir.absolutePath}")
            true
        } catch (t: Throwable) {
            Log.e("OfflineRouting", "GraphHopper import failed", t)
            if (graphDir.exists()) graphDir.deleteRecursively()
            hopper = null
            false
        }
    }

    private fun loadGraphHopper(): GraphHopper? {
        hopper?.let { return it }

        val graphDir = File(filesDir, "offline_routing/graph-cache")
        if (!graphDir.exists()) return null

        return try {
            GraphHopperOSM().apply {
                graphHopperLocation = graphDir.absolutePath
                encodingManager = EncodingManager.create("car")
                setProfiles(
                    Profile("car")
                        .setVehicle("car")
                        .setWeighting("fastest")
                        .setTurnCosts(false)
                )
                chPreparationHandler.setCHProfiles(CHProfile("car"))
                importOrLoad()
            }.also {
                hopper = it
            }
        } catch (_: Throwable) {
            null
        }
    }
}
