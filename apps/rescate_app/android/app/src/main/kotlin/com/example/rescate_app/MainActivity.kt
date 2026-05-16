package com.example.rescate_app

import com.graphhopper.GHRequest
import com.graphhopper.GraphHopper
import com.graphhopper.config.CHProfile
import com.graphhopper.config.Profile
import com.graphhopper.routing.util.EncodingManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.cos
import kotlin.math.sqrt
import java.util.Locale
import com.graphhopper.util.shapes.GHPoint

class MainActivity : FlutterActivity() {
    private val channelName = "rescate/offline_routing"
    private var hopper: GraphHopper? = null

    private data class RoutePoint(val lat: Double, val lng: Double)
    private data class DangerZone(val lat: Double, val lng: Double, val radius: Double)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "findRoute" -> findRoute(call.arguments, result)
                    else -> result.notImplemented()
                }
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

        var bestRoute = directRoute
        var bestScore = dangerScore(directRoute, dangerZones)

        for (zone in dangerZones) {
            if (!routeTouchesDanger(bestRoute, zone)) continue

            for (detour in detourOptions(start, destination, zone)) {
                val candidate = routeThrough(graphHopper, listOf(start, detour, destination)) ?: continue
                val candidateScore = dangerScore(candidate, dangerZones)
                if (candidateScore < bestScore) {
                    bestRoute = candidate
                    bestScore = candidateScore
                }
                if (candidateScore == 0) return candidate
            }
        }

        return bestRoute
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
        return route.any { point -> distanceMeters(point, RoutePoint(zone.lat, zone.lng)) < zone.radius + 60.0 }
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

        val offsetMeters = zone.radius + 180.0
        val metersPerLatDegree = 111_320.0
        val metersPerLngDegree = 111_320.0 * cos(Math.toRadians(zone.lat))
        val perpLat = dx / length
        val perpLng = -dy / length

        return listOf(
            RoutePoint(
                center.lat + (perpLat * offsetMeters / metersPerLatDegree),
                center.lng + (perpLng * offsetMeters / metersPerLngDegree),
            ),
            RoutePoint(
                center.lat - (perpLat * offsetMeters / metersPerLatDegree),
                center.lng - (perpLng * offsetMeters / metersPerLngDegree),
            ),
        )
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

    private fun loadGraphHopper(): GraphHopper? {
        hopper?.let { return it }

        val graphDir = File(filesDir, "offline_routing/graph-cache")
        if (!graphDir.exists()) return null

        return try {
            GraphHopper().apply {
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
