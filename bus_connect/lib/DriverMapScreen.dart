import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:flutter/animation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;


class DriverMapScreen extends StatefulWidget {
  final String routeName; //  route name received from SignInPage

  const DriverMapScreen({required this.routeName, Key? key}) : super(key: key);

  @override
  State<DriverMapScreen> createState() => _DriverMapScreenState();
}

class _DriverMapScreenState extends State<DriverMapScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final MapController mapController = MapController();
  bool isStreet = true;
  bool showLayerButtons = false;
  final String mapTilerApiKey = 'XrzK3nDmgIYoJx5S843I';
  final String orsApiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjQ4NWE5ZTllNzBkYjQxMWY4ODY4ZDJhNTJkNTAyNmE2IiwiaCI6Im11cm11cjY0In0='; // Replace with your ORS API Key

  late String routeName;// route name .

  final FMTCStore mapStore = FMTCStore('mapCache');

  LatLng? driverLocation;
  List<LatLng> routePoints = [];
  List<Map<String, dynamic>> stops = [];
  StreamSubscription<Position>? positionStream;

  late AnimationController _animationController;
  Tween<LatLng>? _latLngTween;
  LatLng? _startLatLng;
  LatLng? _endLatLng;

  @override
  void initState() {
    super.initState();
    routeName = widget.routeName;
    fetchRouteData();
    startLocationUpdates();

    _animationController = AnimationController(vsync: this, duration: const Duration(seconds: 1));

    _animationController.addListener(() {
      if (_latLngTween != null) {
        LatLng newCenter = _latLngTween!.evaluate(_animationController);
        mapController.move(newCenter, mapController.camera.zoom);
      }
    });
  }

  @override
  void dispose() {
    positionStream?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  // ORS ROUTE FUNCTION
  Future<List<LatLng>> getRouteFromORS(List<LatLng> points) async {
    if (points.length < 2) return [];

    try {
      final url = Uri.parse(
          'https://api.openrouteservice.org/v2/directions/driving-car/geojson');

      final response = await http.post(
        url,
        headers: {
          'Authorization': orsApiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "coordinates": [
            for (var p in points) [p.longitude, p.latitude]
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coordsList = data['features'][0]['geometry']['coordinates'] as List;
        return coordsList.map((c) => LatLng(c[1], c[0])).toList();
      } else {
        print('ORS API Error: ${response.statusCode}');
        return points; // fallback to raw points if API fails
      }
    } catch (e) {
      print('ORS Exception: $e');
      return points; // fallback
    }
  }

  // FETCH ROUTE DATA
  Future<void> fetchRouteData() async {
    DocumentSnapshot routeDoc =
    await firestore.collection('routes').doc(routeName).get();

    if (routeDoc.exists) {
      var data = routeDoc.data() as Map<String, dynamic>;

      // Stops
      stops = List<Map<String, dynamic>>.from(data['stops']);

      // Raw route points
      final rawPoints = List<Map<String, dynamic>>.from(data['route_points'])
          .map((e) => LatLng(e['latitude'], e['longitude']))
          .toList();

      // Get route following roads using ORS
      routePoints = await getRouteFromORS(rawPoints);

      // Initial driver location
      var busLoc = data['bus_location'];
      driverLocation = LatLng(busLoc['latitude'], busLoc['longitude']);

      setState(() {});
    }
  }

  void animateMapMove(LatLng newLocation) {
    _startLatLng = mapController.camera.center;
    _endLatLng = newLocation;
    _latLngTween = Tween(begin: _startLatLng, end: _endLatLng);
    _animationController.reset();
    _animationController.forward();
  }

  // LIVE LOCATION
  void startLocationUpdates() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return;
    }

    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      LatLng newLocation = LatLng(position.latitude, position.longitude);

      setState(() {
        driverLocation = newLocation;
      });

      animateMapMove(newLocation);

      // Update Firestore
      await firestore.collection('routes').doc(routeName).update({
        'bus_location': {
          'latitude': newLocation.latitude,
          'longitude': newLocation.longitude,
        }
      });
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Driver Map",style: TextStyle(color: Colors.black,fontWeight: FontWeight.bold),),backgroundColor: const Color(0xFFF6BF3E),),
      body: driverLocation == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: driverLocation!,
              initialZoom: 13.0,
              maxZoom: 19.0,
              minZoom: 7.0,// 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'
            ),
            children: [
              // Map Layers
              TileLayer(
                urlTemplate: isStreet
                    ? 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png' // 🛰 Satellite
                    : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', // 🌍 Default street map
                subdomains: ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.saarthi',
                tileProvider: mapStore.getTileProvider(), // ✅ supports cache
              ),


              // Route polyline
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routePoints,
                    color: Colors.blue,
                    strokeWidth: 4.0,
                  ),
                ],
              ),

              // Driver marker
              MarkerLayer(
                markers: [
                  Marker(
                    point: driverLocation!,
                    width: 50,
                    height: 50,
                    child: const Icon(Icons.directions_bus,
                        color: Colors.orange, size: 30),
                  ),
                ],
              ),

              // Stops markers
              MarkerLayer(
                markers: stops
                    .map((stop) => Marker(
                  point: LatLng(
                      stop['latitude'], stop['longitude']),
                  width: 100,
                  height: 60,
                  child:
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 28,
                      ),
                      SizedBox(height: 2),


                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal:3, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            stop['name'],
                            style: TextStyle(
                              fontSize:9,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ))
                    .toList(),
              ),


            ],
          ),
        ],
      ),

      // Layer switch buttons
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showLayerButtons) ...[

            FloatingActionButton.extended(
              heroTag: "street",
              backgroundColor: const Color(0xFFF6BF3E),
              onPressed: () {
                setState(() {
                  isStreet = true ;
                  showLayerButtons = false;
                });
              },
              label:
              const Text("Street", style: TextStyle(color: Colors.black)),
              icon: const Icon(Icons.map, color: Colors.black),
            ),//street layer button

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
              label: const Text("Satellite", style: TextStyle(color: Colors.black)),
              icon: const Icon(Icons.satellite_alt, color: Colors.black),
            ),//satellite layer button

            const SizedBox(height: 10),
          ],
          FloatingActionButton(
            heroTag: "layer_main",
            backgroundColor: const Color(0xFFF6BF3E),
            foregroundColor: Colors.white,
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
