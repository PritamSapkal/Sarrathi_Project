import 'dart:async';
import 'dart:convert';
import 'package:bus_connect/StudentMapScreen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class StudentDashBoard extends StatefulWidget {
  final String routeName; // route name received from SignInPage

  const StudentDashBoard({required this.routeName, Key? key}) : super(key: key);
  @override
  State<StudentDashBoard> createState() => _StudentDashBoardState();
}

class _StudentDashBoardState extends State<StudentDashBoard> {

  String? selectedStop;
  bool present = false;

  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final MapController mapController = MapController();
  bool isStreet = true;

  final FMTCStore mapStore = FMTCStore('mapCache');

  final LatLng _defaultCenter = const LatLng(19.0760, 72.8777);

  LatLng? studentLocation;
  StreamSubscription<DocumentSnapshot>? busStreamSubscription;
  LatLng? busLocation;

  late String routeName;
  List<LatLng> routePoints = [];
  List<Map<String, dynamic>> stops = [];

  final String orsApiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjQ4NWE5ZTllNzBkYjQxMWY4ODY4ZDJhNTB2NmE2IiwiaCI6Im11cm11cjY0In0=';

  bool _isConfirming = false;

  // STATE & KEYS FOR PERSISTENCE
  static const String _attendanceDateKey = 'lastAttendanceDate'; // Keeping this for historical context/debugging, but its primary function is gone
  static const String _lastStopKey = 'lastSelectedStopName';
  DateTime? _lastMarkedDate;
  String? _lastMarkedStopName; // Tracks the stop name the student last successfully confirmed

  @override
  void initState() {
    super.initState();
    routeName = widget.routeName;
    _initStudentLocation();
    _fetchRouteData();
    _listenToBusLocation();
    _loadAttendanceState(); // Load attendance state
  }

  Future<void> _loadAttendanceState() async {
    final prefs = await SharedPreferences.getInstance();
    final storedDateString = prefs.getString(_attendanceDateKey);

    // Load the last marked stop name
    _lastMarkedStopName = prefs.getString(_lastStopKey);

    if (storedDateString != null) {
      _lastMarkedDate = DateTime.tryParse(storedDateString);
    } else {
      _lastMarkedDate = null;
    }

    // Set selected stop to the last marked stop on load if none is selected
    if (_lastMarkedStopName != null && selectedStop == null) {
      setState(() {
        selectedStop = _lastMarkedStopName;
        // The 'present' flag should initially be false to allow the first mark/correction
        present = false;
      });
    }

    // Reset the 'present' flag on every app start since the time window is removed
    if(mounted) {
      setState(() {
        present = false;
      });
    }
  }

  // Helper to find index by current selectedStop value
  int _findSelectedStopIndex() {
    if (selectedStop == null) return -1;
    return stops.indexWhere((stop) => stop['name'] == selectedStop);
  }

  // Helper function to find a stop index by name (used for old stop)
  int _findStopIndexByName(String? stopName) {
    if (stopName == null) return -1;
    return stops.indexWhere((stop) => stop['name'] == stopName);
  }

  Future<void> _confirmPresence() async {
    if (_isConfirming) return;

    // Custom SnackBar setup (kept for UI consistency)
    const Color customSnackbarColor = Color(0xFFF6BF3E);
    const TextStyle customTextStyle = TextStyle(color: Colors.black, fontWeight: FontWeight.bold);

    void showCustomSnackBar(String message, {bool isError = false}) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: isError ? const TextStyle(color: Colors.white) : customTextStyle,
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Colors.red : customSnackbarColor,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 150,
            right: 20,
            left: 20,
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    if (selectedStop == null) {
      showCustomSnackBar('Please select your stop first!');
      return;
    }
    if (_lastMarkedStopName == selectedStop) {
      showCustomSnackBar('Presence is already confirmed for $selectedStop. No change made.', isError: false);
      // We set 'present' to true here just to disable the button temporarily for this specific stop.
      if (mounted) setState(() => present = true);
      return;
    }
    // If the student selects a DIFFERENT stop, the button must be active, so we proceed.

    if (mounted) {
      setState(() {
        _isConfirming = true;
        present = false; // Ensure button shows "Confirm Presence" during loading
      });
    }

    final newStopIndex = _findSelectedStopIndex();
    final oldStopIndex = _findStopIndexByName(_lastMarkedStopName);
    final routeDocRef = firestore.collection('routes').doc(routeName);

    if (newStopIndex == -1) {
      showCustomSnackBar('Error: Selected stop not found.', isError: true);
      if (mounted) setState(() => _isConfirming = false);
      return;
    }

    try {
      String actionMessage = 'Presence confirmed for $selectedStop! Student count incremented.';

      // 2. Run the Firebase Transaction
      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(routeDocRef);
        if (!snapshot.exists) {
          throw Exception("Route document does not exist!");
        }

        final data = snapshot.data()!;
        List<Map<String, dynamic>> currentStops =
        List<Map<String, dynamic>>.from(data['stops']);

        // ⭐️ SCENARIO 1: DECREMENT OLD STOP COUNT (Correction Logic)
        if (oldStopIndex != -1) {
          Map<String, dynamic> oldStop = currentStops[oldStopIndex];
          int oldCount = oldStop['student_count'] ?? 0;

          // Decrement the old stop's count
          if (oldCount > 0) {
            oldStop['student_count'] = oldCount - 1;
            currentStops[oldStopIndex] = oldStop;
            actionMessage = 'Correction successful: Changed stop from ${_lastMarkedStopName} to $selectedStop.';
          }
        }

        // ⭐️ SCENARIO 2: INCREMENT NEW STOP COUNT
        Map<String, dynamic> newStop = currentStops[newStopIndex];
        int newCount = newStop['student_count'] ?? 0;

        // Increment the new stop's count
        newStop['student_count'] = newCount + 1;
        currentStops[newStopIndex] = newStop;

        // 5. Commit the update back to Firestore
        transaction.update(routeDocRef, {'stops': currentStops});
      });

      // --- POST TRANSACTION SUCCESS ---

      showCustomSnackBar(actionMessage);

      // Save the attendance date AND the new stop name
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_attendanceDateKey, now.toIso8601String()); // Retained, just saves time of last action
      await prefs.setString(_lastStopKey, selectedStop!);

      // Update local state flags
      if (mounted) {
        setState(() {
          // 'present' is now only used to lock the button immediately after a successful action 
          // for the currently selected stop. It gets reset when the stop selection changes.
          present = true;
          _lastMarkedDate = now;
          _lastMarkedStopName = selectedStop; // Update the last marked stop
        });
      }

    } catch (e) {
      print("Failed to confirm presence (Transaction error): $e");
      showCustomSnackBar('Failed to confirm presence. Please try again.', isError: true);
    }
    finally {
      if (mounted) {
        setState(() {
          _isConfirming = false;
        });
      }
    }
  }

  // Get student current location
  Future<void> _initStudentLocation() async {
    // ... (Your existing logic) ...
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) await Geolocator.openLocationSettings();

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return;

    Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    if (mounted) {
      setState(() {
        studentLocation = LatLng(pos.latitude, pos.longitude);
        _fitMapBounds();
      });
    }
  }

  // Listen to bus live location from Firestore
  void _listenToBusLocation() {
    busStreamSubscription = firestore.collection('routes').doc(routeName).snapshots().listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data()!;
        final busLoc = data['bus_location'];
        if (mounted) {
          setState(() {
            busLocation = LatLng(busLoc['latitude'], busLoc['longitude']);
            _fitMapBounds();
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

  // Helper to fit map to all points (student, bus, route)
  void _fitMapBounds() {
    if (studentLocation == null && busLocation == null && routePoints.isEmpty) return;

    List<LatLng> pointsToInclude = [...routePoints];

    if (studentLocation != null) {
      pointsToInclude.add(studentLocation!);
    }
    if (busLocation != null) {
      pointsToInclude.add(busLocation!);
    }

    if (pointsToInclude.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(pointsToInclude);

      // Use fitCamera instead of fitBounds
      mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.all(30.w),
          maxZoom: 15.0,
        ),
      );
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
  void dispose() {
    busStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        child: Wrap(
          children: [
            // main Containerr
            Container(
              width:double.infinity,
              height: 1000.h,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.yellow.shade600, width: 7.w),
                borderRadius: BorderRadius.circular(20.r),
              ),
              child:
              Column(
                children: [

                  // First container.
                  Container(width: double.infinity,
                    height: 120.h,
                    decoration: BoxDecoration(
                        color:Colors.white,
                        borderRadius: BorderRadius.only(topRight:Radius.circular(20.r),topLeft: Radius.circular(20.r)),
                        boxShadow: [BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8.r,
                            spreadRadius: 3.r
                        )]
                    ),
                    child:Column(
                      children: [
                        SizedBox(height: 11.h,),
                        // logo and student dashbord text
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              CircleAvatar(
                                radius: 35.r,
                                child: Image.asset("assets/images/Saarathi_logo.png"),
                                backgroundColor: Colors.white,
                              ),
                              // student dashboard text
                              Text(
                                "Student Dashboard",
                                style: TextStyle(color: Colors.black, fontSize: 25.sp, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(width: 8.w,),
                              Container(
                                height: 45.h,
                                width: 45.w,
                                decoration: BoxDecoration(shape: BoxShape.circle),
                                child: CircleAvatar(
                                  backgroundColor: Colors.white,
                                  child: Icon(Icons.account_circle_rounded, color: Colors.grey, size: 48.sp),
                                ),
                              ),

                            ]
                        ),
                        // your real time bua information text.
                        Text(
                          "Your real-time bus information",
                          style: TextStyle(color: Colors.grey, fontSize: 17.sp, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 8.h),

                  SizedBox(height: 5.h),

                  // second container
                  Container(
                    width: 340.w,
                    height: 150.h,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 3.r,
                          spreadRadius: 0.1.r,
                        )
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(9.w),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [

                          Text(
                            "Select Your Stop",
                            style: TextStyle(
                                color: const Color(0xff2f2f2f), fontSize: 19.sp, fontWeight: FontWeight.bold),
                          ),


                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedStop,
                              decoration: InputDecoration(
                                labelText: "Select Stop",
                                hintText: "Choose Your Stop...",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.r),
                                ),
                              ),
                              items: stops.map((stopMap) {
                                final stopName = stopMap['name'] as String;
                                return DropdownMenuItem<String>(
                                  value: stopName,
                                  child: Text(stopName),
                                );
                              }).toList(),
                              onChanged: (String? value) {
                                setState(() {
                                  selectedStop = value;
                                  if (selectedStop != _lastMarkedStopName) {
                                    present = false;
                                  } else {
                                    present = true;
                                  }
                                });
                              },
                            ),
                          ),
// ...

                          Container(
                            width: 340.w,
                            height: 30.h,
                            child:
                            ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF6BF3E),
                                shadowColor: Colors.black45,
                                elevation: 5.r,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10.r),
                                ),
                              ),
                                 onPressed: (_isConfirming || present) ? null : _confirmPresence,

                              child: _isConfirming
                                  ? SizedBox(
                                height: 20.h,
                                width: 20.w,
                                child: const CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                                  : Text(
                                // ⭐️ UPDATED TEXT
                                present ? "Marked for this Stop" : "Confirm Presence",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16.sp,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 18.h),

                  // third container with driver calling function
                  Container(
                    width: 340.w,
                    height: 140.h,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 3.r,
                          spreadRadius: 0.1.r,
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(7.w),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Driver Contact",
                                style: TextStyle(
                                    color: const Color(0xff2f2f2f), fontSize: 20.sp, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 8.h),
                              Text(
                                "Contact your driver for \n any issues",
                                style: TextStyle(
                                    color: const Color(0xff2f2f2f), fontSize: 16.sp, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 8.h),
                              Text(
                                "Driver's Contact: +123456789",
                                style: TextStyle(
                                    color: Colors.black45, fontSize: 14.sp, fontWeight: FontWeight.bold),
                              )
                            ],
                          ),
                        ),

                        SizedBox(width: 20.w),

                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 100.w,
                              height: 55.h,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF6BF3E),
                                  shadowColor: Colors.black45,
                                  elevation: 5.r,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15.r),
                                  ),
                                  padding: EdgeInsets.all(8.w),
                                ),
                                onPressed: () {
                                  print("calling function not added Yet !!");
                                },
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Icon(Icons.call, color: Colors.white, size: 20.sp),
                                      SizedBox(width: 6.w),
                                      Text(
                                        "Driver",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16.5.sp,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),

                  SizedBox(height: 20.h),

                  // forth container with student map section...
                  Container(
                    width: 340.w,
                    height: 325.h,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 3.r,
                          spreadRadius: 0.1.r,
                        )
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(8.w),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // bus Location text
                          Text(
                            "Bus Location",
                            style: TextStyle(color: Colors.black, fontSize: 20.sp, fontWeight: FontWeight.bold),
                          ),

                          // map section
                          Container(
                            width: 330.w,
                            height: 230.h,
                            decoration: BoxDecoration(
                              color: const Color(0xFFCECECE),
                              borderRadius: BorderRadius.circular(10.r),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10.r),
                              child: (stops.isNotEmpty || busLocation != null)
                                  ?
                              Stack(children: [

                                FlutterMap(
                                  mapController: mapController,
                                  options: MapOptions(
                                    initialCenter: studentLocation ?? _defaultCenter,
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
                                ),
                              ]
                              )

                                  : const Center(
                                child: CircularProgressIndicator(color: Color(0xFFF6BF3E)),
                              ),
                            ),
                          ),


                          SizedBox(height: 8.h),

                          // Display map Button.
                          Container(
                            width: 330.w,
                            height: 40.h,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF6BF3E),
                                shadowColor: Colors.black45,
                                elevation: 5.r,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10.r),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(context, MaterialPageRoute(builder: (context)=> Studentmapscreen(routeName: routeName)));
                              },
                              // FIX: Added child text to fix the error
                              child: Text(
                                "Display Bus Map",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16.sp,
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
      ),
    );
  }
}