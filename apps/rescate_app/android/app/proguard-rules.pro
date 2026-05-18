# R8 / ProGuard rules for the Rescate app.
#
# The offline-routing path pulls in GraphHopper 1.0, which transitively
# depends on Apache XmlGraphics Commons. XmlGraphics references JDK classes
# that don't exist on Android (java.awt.*, javax.imageio.*). These paths
# are only reached for EPS/TIFF image preloading — never executed by us —
# but R8's full-mode reachability check fails without an explicit dontwarn.

-dontwarn java.awt.**
-dontwarn javax.imageio.**
-dontwarn javax.swing.**
-dontwarn org.apache.xmlgraphics.**

# StAX shim: we pin com.fasterxml.aalto as the XMLInputFactory impl from
# MainActivity.kt. Without the keep rule R8 strips the service entries and
# XMLInputFactory.newInstance() fails at runtime.
-keep class com.fasterxml.aalto.** { *; }
-dontwarn com.fasterxml.aalto.**

# GraphHopper uses reflective config loading; keep its public surface so
# 1.0's data-reader factory selection still works after shrink.
-keep class com.graphhopper.** { *; }
-dontwarn com.graphhopper.**

# SLF4J: simple impl is loaded via ServiceLoader.
-dontwarn org.slf4j.**

# Nearby Connections plugin uses deprecated reflection paths under the hood.
-dontwarn com.google.android.gms.nearby.**
