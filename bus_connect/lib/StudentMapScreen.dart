import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart'; // ⭐️ Import FMTC
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;


class Studentmapscreen extends StatefulWidget {
  final String routeName;
  const Studentmapscreen({required this.routeName, Key? key}) : super(key: key);

  @override
  State<Studentmapscreen> createState() => _StudentMapScreenState();
}

class _StudentMapScreenState extends State<Studentmapscreen> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final MapController mapController = MapController();

  // ⭐️ ADDED: FMTC Store Instance
  final FMTCStore mapStore = FMTCStore('mapCache');

  final String orsApiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjQ4NWE5ZTllNzBkYjQxMWY4ODY4ZDJhNTJkNTAyNmE2IiwiaCI6Im11cm11cjY0In0=';

  bool isStreet = true;
  bool showLayerButtons = false;

  LatLng? studentLocation;
  LatLng? busLocation;
  List<LatLng> routePoints = [];
  List<Map<String, dynamic>> stops = [];

  late String routeName;
  StreamSubscription<DocumentSnapshot>? busStream;

  @override
  void initState() {
    super.initState();
    routeName = widget.routeName;
    _initStudentLocation();
    _fetchRouteData();
    _listenToBusLocation();
  }

  @override
  void dispose() {
    busStream?.cancel();
    super.dispose();
  }

  // Get student current location
  Future<void> _initStudentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) await Geolocator.openLocationSettings();

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return;

    Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      studentLocation = LatLng(pos.latitude, pos.longitude);
    });
  }

  // Listen to bus live location from Firestore
  void _listenToBusLocation() {
    busStream = firestore.collection('routes').doc(routeName).snapshots().listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data()!;
        final busLoc = data['bus_location'];
        if (mounted) {
          setState(() {
            busLocation = LatLng(busLoc['latitude'], busLoc['longitude']);
          });
        }
      }
    });
  }

  // Fetch stops and route from Firestore
  Future<void> _fetchRouteData() async {
    final routeDoc = await firestore.collection('routes').doc(routeName).get();
    if (routeDoc.exists) {
      final data = routeDoc.data()!;
      stops = List<Map<String, dynamic>>.from(data['stops']);
      final rawPoints = List<Map<String, dynamic>>.from(data['route_points'])
          .map((e) => LatLng((e['latitude'] as num).toDouble(), (e['longitude'] as num).toDouble()))
          .toList();
      routePoints = await _getRouteFromORS(rawPoints);
      if (mounted) setState(() {});
    }
  }

  // Get route from OpenRouteService
  Future<List<LatLng>> _getRouteFromORS(List<LatLng> points) async {
    if (points.length < 2) return points;
    try {
      final response = await http.post(
        Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car/geojson'),
        headers: {'Authorization': orsApiKey, 'Content-Type': 'application/json'},
        body: jsonEncode({
          "coordinates": [for (var p in points) [p.longitude, p.latitude]]
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coordsList = data['features'][0]['geometry']['coordinates'] as List;
        return coordsList.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
      } else {
        print('ORS API error: ${response.statusCode}');
        return points;
      }
    } catch (e) {
      print('ORS Exception: $e');
      return points;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Student Map",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFF6BF3E),
      ),
      body: (studentLocation == null)
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: studentLocation!,
          initialZoom: 13,
          maxZoom: 19,
          minZoom: 7,
        ),
        children: [
          TileLayer(
            urlTemplate: isStreet
                ? 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'
                : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            subdomains: isStreet ? ['a', 'b', 'c'] : [], // Subdomains are for OSM not the other tile server
            userAgentPackageName: 'com.example.saarthi',
            // ⭐️ APPLIED: Use the FMTC Tile Provider for caching
            tileProvider: mapStore.getTileProvider(),
          ),

          // Route Polyline
          if (routePoints.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(points: routePoints, color: Colors.blue, strokeWidth: 4.0),
              ],
            ),

          // Stops
          MarkerLayer(
            markers: stops
                .map((stop) => Marker(
              point: LatLng(stop['latitude'], stop['longitude']),
              width: 100,
              height: 60,
              child: Row(
                children: [
                  const Icon(Icons.location_on,
                      color: Colors.red, size: 28),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        stop['name'],
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.black),
                      ),
                    ),
                  ),
                ],
              ),
            ))
                .toList(),
          ),

          // Bus Marker
          if (busLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: busLocation!,
                  width: 50,
                  height: 50,
                  child: const Icon(Icons.directions_bus,
                      color: Colors.orange, size: 30),
                ),
              ],
            ),

          // Student Marker
          if (studentLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: studentLocation!,
                  width: 50,
                  height: 50,
                  child: const Icon(Icons.person_pin_circle,
                      color: Colors.blue, size: 33),
                ),
              ],
            ),
        ],
      ),

      // Floating buttons for layers
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (showLayerButtons) ...[
            FloatingActionButton.extended(
              heroTag: "street",
              backgroundColor: const Color(0xFFF6BF3E),
              onPressed: () {
                setState(() {
                  isStreet = true;
                  showLayerButtons = false;
                });
              },
              label: const Text("Street", style: TextStyle(color: Colors.black)),
              icon: const Icon(Icons.map, color: Colors.black),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.extended(
              heroTag: "satellite",
              backgroundColor: const Color(0xFFF6BF3E),
              onPressed: () {
                setState(() {
                  isStreet = false;
                  showLayerButtons = false;
                });
              },
              label:
              const Text("Satellite", style: TextStyle(color: Colors.black)),
              icon: const Icon(Icons.satellite_alt, color: Colors.black),
            ),
            const SizedBox(height: 10),
          ],
          FloatingActionButton(
            heroTag: "layer_main",
            backgroundColor: const Color(0xFFF6BF3E),
            onPressed: () {
              setState(() {
                showLayerButtons = !showLayerButtons;
              });
            },
            child: const Icon(Icons.layers, color: Colors.black),
          ),
        ],
      ),
    );
  }
}