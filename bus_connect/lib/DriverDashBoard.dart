import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bus_connect/DriverMapScreen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart'; // KEEP
import 'package:http/http.dart' as http;
import 'package:flutter/animation.dart'; // Import for AnimationController

class DriverDashBoard extends StatefulWidget {
  final String routeName;

  const DriverDashBoard({required this.routeName, Key? key}) : super(key: key);

  @override
  State<DriverDashBoard> createState() => _DriverDashBoardState();
}

class _DriverDashBoardState extends State<DriverDashBoard> with SingleTickerProviderStateMixin {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Map<String, int> stopStudentCount = {};
  List<Map<String, dynamic>> stopList = [];
  bool dataFetched = false;

  late String routeName;

  // --- LOCATION UPDATE VARIABLES ADDED ---
  // Position Stream for continuous updates and Firestore write
  StreamSubscription<Position>? positionStream;
  // Map animation variables (moved from DriverMapScreen for map centering)
  late AnimationController _animationController;
  Tween<LatLng>? _latLngTween;
  LatLng? _startLatLng;
  LatLng? _endLatLng;
  // --- END ADDED VARIABLES ---

  final String orsApiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjQ4NWE5ZTllNzBkYjQxMWY4ODY4ZDJhNTJkNTAyNmE2IiwiaCI6Im11cm11cjY0In0=';
  final MapController _mapController = MapController();
  final FMTCStore mapStore = FMTCStore('mapCache');

  String nextStopName = "";
  int no_of_student = 0;
  double busLat = 0.0;
  double busLng = 0.0;

  final ScrollController _scrollController = ScrollController();
  int currentStopIndex = 0;

  // ❌ REMOVED: Timer? _timer; (No longer needed, replaced by positionStream)

  List<LatLng> routePoints = [];
  List<LatLng> rawRoutePoints = [];

  bool isStreet = true;
  // bool showLayerButtons = false;

  @override
  void initState() {
    super.initState();
    routeName = widget.routeName;
    fetchStopsData();
    // ⭐️ START LOCATION UPDATES AS SOON AS THE DASHBOARD LOADS
    startLocationUpdates();

    // Setup map animation (Copied from DriverMapScreen)
    _animationController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _animationController.addListener(() {
      if (_latLngTween != null) {
        LatLng newCenter = _latLngTween!.evaluate(_animationController);
        _mapController.move(newCenter, _mapController.camera.zoom);
      }
    });
  }

  @override
  void dispose() {
    // ⭐️ CRUCIAL: STOP LOCATION UPDATES WHEN THE DASHBOARD IS CLOSED
    positionStream?.cancel();
    _animationController.dispose();
    _scrollController.dispose();
    // ❌ REMOVED: _timer?.cancel();
    super.dispose();
  }

  // --- LOCATION UPDATE FUNCTIONS ADDED ---

  // Helper function for map movement (Copied from DriverMapScreen)
  void animateMapMove(LatLng newLocation) {
    _startLatLng = _mapController.camera.center;
    _endLatLng = newLocation;
    _latLngTween = Tween(begin: _startLatLng, end: _endLatLng);
    _animationController.reset();
    _animationController.forward();
  }

  // ⭐️ LIVE LOCATION UPDATE AND FIRESTORE WRITE (Copied from DriverMapScreen)
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

      if (!mounted) return;
      setState(() {
        busLat = newLocation.latitude;
        busLng = newLocation.longitude;
      });

      // Update Firestore (This is the crucial step that keeps the location live)
      await firestore.collection('routes').doc(routeName).update({
        'bus_location': {
          'latitude': newLocation.latitude,
          'longitude': newLocation.longitude,
        }
      });

      // Update the map view (using the existing map controller)
      animateMapMove(newLocation);

      // Update the next stop whenever a new location is received
      _updateNextStop();
    });
  }

  // --- END LOCATION UPDATE FUNCTIONS ADDED ---

  void _fitRouteBounds() {
    // Only try to fit if we have actual route points AND bus location
    if (routePoints.length > 1 && mounted && (busLat != 0.0 || busLng != 0.0)) {
      final allPoints = [...routePoints, LatLng(busLat, busLng)];
      final bounds = LatLngBounds.fromPoints(allPoints);

      // Use fitCamera and CameraFit.bounds
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.all(40.w),
          maxZoom: 15.0,
        ),
      );
    }
  }

  // ORS Route Function (Kept as is)
  Future<List<LatLng>> getRouteFromORS(List<LatLng> points) async {
    if (points.length < 2) {
      print('DEBUG: Not enough raw points (${points.length}) to request route.');
      return [];
    }

    final coordinates = points.map((p) => [p.longitude, p.latitude]).toList();
    print('DEBUG: ORS Requesting route for ${points.length} raw points. Example: ${coordinates.first}');

    try {
      final url = Uri.parse(
          'https://api.openrouteservice.org/v2/directions/driving-car/geojson');

      final response = await http.post(
        url,
        headers: {
          'Authorization': orsApiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({"coordinates": coordinates}),
      );

      print('DEBUG: ORS Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coordsList = data['features'][0]['geometry']['coordinates'] as List;

        List<LatLng> resultPoints = coordsList.map((c) =>
            LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())
        ).toList();

        print('DEBUG: ✅ Route received! Total polyline points: ${resultPoints.length}');
        return resultPoints;

      } else {
        // Fallback: Use the raw points if API fails
        print('DEBUG: ❌ API Error. Using straight-line fallback. Body (start): ${response.body.substring(0, response.body.length.clamp(0, 500))}');
        return points;
      }
    } catch (e) {
      print('DEBUG: 🚨 Exception during API call: $e');
      return points; // fallback
    }
  }


  // Fetch all route data from Firebase (Kept as is, but relies on positionStream for continuous location updates)
  Future<void> fetchStopsData() async {
    try {
      final doc = await firestore.collection('routes').doc(routeName).get();

      if (doc.exists) {
        final data = doc.data()!;
        final stops = data['stops'] ?? [];

        // --- STOP LIST PROCESSING (Same as before) ---
        Map<String, int> fetchedStops = {};
        int totalStudents = 0;
        stopList.clear();
        for (var stop in stops) {
          fetchedStops[stop['name']] = stop['student_count'];
          totalStudents += stop['student_count'] as int;
          stopList.add({
            "name": stop['name'],
            "latitude": (stop['latitude'] as num).toDouble(),
            "longitude": (stop['longitude'] as num).toDouble(),
            "student_count": stop['student_count']
          });
        }

        // --- RAW ROUTE POINTS PROCESSING (Crucial) ---
        final rawPointsData = data['route_points'] ?? [];
        rawRoutePoints = List<Map<String, dynamic>>.from(rawPointsData)
            .map((e) => LatLng((e['latitude'] as num).toDouble(), (e['longitude'] as num).toDouble()))
            .toList();

        print('DEBUG: Fetched ${rawRoutePoints.length} raw route points from Firebase.');

        final busLoc = data['bus_location'];
        double lat = (busLoc?['latitude'] as num?)?.toDouble() ?? 0.0;
        double lng = (busLoc?['longitude'] as num?)?.toDouble() ?? 0.0;

        if (!mounted) return;
        setState(() {
          stopStudentCount = fetchedStops;
          no_of_student = totalStudents;
          busLat = lat; // Initial location from Firestore
          busLng = lng;
          nextStopName = stopList.isNotEmpty ? stopList[0]['name'] : "";
          dataFetched = true;
        });

        // Fetch route
        await fetchRoutePolyline();
        _updateNextStop();
      } else {
        print('DEBUG: Route document $routeName does not exist.');
      }
    } catch (e) {
      print("DEBUG: 🚨 Error fetching stops: $e");
    }
  }

  // Gets the polyline and fits the map (Kept as is)
  Future<void> fetchRoutePolyline() async {
    if (rawRoutePoints.length < 2) return;

    routePoints = await getRouteFromORS(rawRoutePoints);

    // Fit bounds immediately after receiving points to make sure the route is visible
    if (routePoints.isNotEmpty) {
      _fitRouteBounds();
    }

    if (mounted) setState(() {});
  }


  // ❌ REMOVED: fetchBusLocation() (No longer needed)


  // Compute next stop (Kept as is)
  void _updateNextStop() {
    if (!dataFetched || stopList.isEmpty) return;
    if (busLat == 0.0 && busLng == 0.0) return; // Only run if bus location is valid

    final Distance distance = Distance();
    int newStopIndex = currentStopIndex;

    for (int i = 0; i < stopList.length; i++) {
      final stopLat = stopList[i]['latitude'];
      final stopLng = stopList[i]['longitude'];
      final dist = distance(LatLng(busLat, busLng), LatLng(stopLat, stopLng));

      // Simple logic: move to next stop if within 50 meters
      if (i >= currentStopIndex && dist < 50) {
        newStopIndex = (i + 1).clamp(0, stopList.length - 1);
        break;
      }
    }

    newStopIndex = newStopIndex.clamp(0, stopList.length - 1);

    if (!mounted) return;

    setState(() {
      currentStopIndex = newStopIndex;
      nextStopName = stopList[currentStopIndex]['name'] ?? "Unknown Stop";

      _scrollController.animateTo(
        currentStopIndex * 85.h,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }


  @override
  Widget build(BuildContext context) {
    int noofstop = stopStudentCount.length;

    return Scaffold(
      body: Wrap(
        children: [
          Container(
            width: double.infinity,
            height: 1000.h,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.yellow.shade600, width: 8.w),
              borderRadius: BorderRadius.circular(15.r),
            ),
            child: Column(
              children: [
                // first container with logo and Driver info (UI UNCHANGED)
                Container(
                  width: double.infinity,
                  height: 80.h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(15.r),
                      topRight: Radius.circular(15.r),
                    ),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 3.r,
                        spreadRadius: 1.r,
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 33.r,
                        child: Image.asset("assets/images/Saarathi_logo.png"),
                        backgroundColor: Colors.white,
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        "Saarathi",
                        style: TextStyle(
                            color: Colors.black,
                            fontSize: 27.sp,
                            fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 70.w),
                      Text(
                        "Driver",
                        style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 20.sp),
                      ),
                      SizedBox(width: 2.w),
                      Container(
                        height: 45.h,
                        width: 45.w,
                        decoration: BoxDecoration(shape: BoxShape.circle),
                        child: CircleAvatar(
                          backgroundColor: Colors.white,
                          child: Icon(Icons.account_circle_rounded,
                              color: Colors.grey, size: 48.sp),
                        ),
                      ),
                    ],
                  ),
                ),

                // second container (UI UNCHANGED)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Stack(
                    children: [
                      // Orange container
                      Container(
                        width: double.infinity,
                        height: 103.h,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6BF3E),
                          borderRadius: BorderRadius.circular(10.r),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 3.r,
                                spreadRadius: 1.5.r)
                          ],
                        ),
                      ),

                      // White container with data
                      Container(
                        width: double.infinity,
                        height: 97.h,
                        padding: EdgeInsets.all(10.w),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  "Assigned Route : ",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18.sp,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '$routeName',
                                    style: TextStyle(
                                      color: Colors.orangeAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18.sp,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(left: 3.w, top: 2.h),
                                  child: Text(
                                    "Next Stop : ",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16.sp,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    dataFetched && nextStopName.isNotEmpty
                                        ? nextStopName
                                        : "Fetching next stop...",
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.orangeAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16.sp,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 5.h),
                            Text(
                              dataFetched
                                  ? "$noofstop stops - $no_of_student students assigned"
                                  : "Fetching data...",
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.sp),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Stop List (UI UNCHANGED)
                Container(
                  width: double.infinity,
                  height: 300.h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18.r),
                    color: Colors.white,
                  ),
                  child: ListView.separated(
                    controller: _scrollController,
                    itemCount: dataFetched ? stopStudentCount.length : 5,
                    separatorBuilder: (context, index) =>
                        Divider(height: 7.h, color: Colors.white),
                    itemBuilder: (context, index) {
                      String stopName =
                      dataFetched ? stopStudentCount.keys.elementAt(index) : "Loading...";
                      int studentCount =
                      dataFetched ? stopStudentCount[stopName]! : 0;
                      bool isNextStop = index == currentStopIndex;

                      return Container(
                        height: 75.h,
                        margin: EdgeInsets.symmetric(vertical: 3.w),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10.r),
                          border:
                          isNextStop ? Border.all(color: Colors.orange, width: 3) : null,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4.r,
                                spreadRadius: 1.r)
                          ],
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.shade50,
                            radius: 23.r,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.sp),
                            ),
                          ),
                          title: Text(
                            stopName,
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 18.sp),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                studentCount.toString(),
                                style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22.sp),
                              ),
                              Text(
                                "Students",
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.sp),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Map Section (UI UNCHANGED)
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4.r,
                            spreadRadius: 1.r)
                      ],
                    ),
                    child: Column(
                      children: [
                        // Live route text
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_on,
                                color: Colors.orangeAccent, size: 28.sp),
                            SizedBox(width: 5.w),
                            Text(
                              "Live Route",
                              style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        SizedBox(height: 4.h),

                        // Map
                        Padding(
                          padding: EdgeInsets.all(6.w),
                          child: Container(
                            width: double.infinity,
                            height: 180.h,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10.r),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 4.r,
                                    spreadRadius: 1.r)
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10.r),
                              child: (dataFetched)
                                  ? Stack(
                                children: [

                                  FlutterMap(
                                    mapController: _mapController,
                                    options: MapOptions(
                                      // Note: If you want a starting point, use initialCenter: LatLng(busLat, busLng)
                                      initialZoom: 14.0,
                                      minZoom: 10.0,
                                      maxZoom: 18.0,

                                      // ✅ FIX: In v6/v7, interactiveFlags moved into interactionOptions
                                      interactionOptions: const InteractionOptions(
                                        flags: InteractiveFlag.all,
                                      ),
                                    ),
                                    children: [
                                      TileLayer(
                                        urlTemplate: isStreet
                                            ? "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                                            : "https://{s}.google.com/vt/lyrs=s&x={x}&y={y}&z={z}",
                                        subdomains: isStreet ? ['a', 'b', 'c'] : ['mt0', 'mt1', 'mt2', 'mt3'],
                                        userAgentPackageName: 'com.yourcompany.busconnect',

                                        // ⭐️ FMTC tile provider remains the same
                                        tileProvider: mapStore.getTileProvider(),
                                      ),

                                      // PolylineLayer
                                      if (routePoints.length >= 2)
                                        PolylineLayer(
                                          polylines: [
                                            Polyline(
                                              points: routePoints,
                                              color: Colors.blue,
                                              strokeWidth: 4.0,
                                            ),
                                          ],
                                        ),

                                      // Stops markers
                                      MarkerLayer(
                                        markers: stopList.map((stop) {
                                          bool isNextStop = stop['name'] == nextStopName;
                                          return Marker(
                                            point: LatLng(stop['latitude'], stop['longitude']),
                                            width: 100,
                                            height: 60,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.location_on,
                                                  color: isNextStop ? Colors.orangeAccent : Colors.blue,
                                                  size: isNextStop ? 32 : 28,
                                                ),
                                                const SizedBox(width: 2), // Changed to width for horizontal spacing
                                                Expanded(
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withOpacity(0.8),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      stop['name'],
                                                      style: TextStyle(
                                                        fontSize: 9.sp,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.black,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),

                                      // Bus Marker
                                      MarkerLayer(
                                        markers: [
                                          if (busLat != 0.0 || busLng != 0.0)
                                            Marker(
                                              point: LatLng(busLat, busLng),
                                              width: 50,
                                              height: 50,
                                              child: const Icon(
                                                Icons.directions_bus_sharp,
                                                color: Colors.orange,
                                                size: 35,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),

                                  // Layer toggle buttons (same as before)
                                  Positioned(
                                    top: 5,
                                    right: 5,
                                    child: Column(
                                      children: [
                                        FloatingActionButton(
                                          mini: true,
                                          backgroundColor: Colors.white,
                                          onPressed: () {
                                            setState(() {
                                              isStreet = true;
                                            });
                                          },
                                          child: Icon(Icons.map, color: Colors.blue),
                                        ),
                                        SizedBox(height: 5),
                                        FloatingActionButton(
                                          mini: true,
                                          backgroundColor: Colors.white,
                                          onPressed: () {
                                            setState(() {
                                              isStreet = false;
                                            });
                                          },
                                          child: Icon(Icons.satellite, color: Colors.green),
                                        ),
                                      ],
                                    ),
                                  )
                                ],
                              )
                                  : Container(
                                color: Colors.grey.shade300,
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Display Map button (UI UNCHANGED)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: double.infinity,
                            height: 38.h,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF6BF3E),
                                shadowColor: Colors.black45,
                                elevation: 5.r,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10.r)),
                              ),
                              onPressed: () {
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            DriverMapScreen(routeName: routeName)));
                              },
                              child: Text(
                                "Display Map",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16.sp),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}