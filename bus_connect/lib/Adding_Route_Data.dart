import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MaterialApp(home: UploadBusRoutesData()));
}

class UploadBusRoutesData extends StatefulWidget {
  const UploadBusRoutesData({super.key});

  @override
  State<UploadBusRoutesData> createState() => _UploadBusRoutesDataState();
}

class _UploadBusRoutesDataState extends State<UploadBusRoutesData> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<void> uploadRoutes() async {
    // --- SANGALI-SIT ---
    final sangliStops = [
      {"name": "Bus Stand", "latitude": 16.8524, "longitude": 74.5815, "student_count": 0},
      {"name": "Ankali", "latitude": 16.8560, "longitude": 74.5975, "student_count": 0},
      {"name": "Udgaon", "latitude": 16.8612, "longitude": 74.6132, "student_count": 0},
      {"name": "Jaysingpur", "latitude": 16.7785, "longitude": 74.5654, "student_count": 0},
      {"name": "Chipari Phata", "latitude": 16.7768, "longitude": 74.5503, "student_count": 0},
      {"name": "Kolhapur Phata", "latitude": 16.7701, "longitude": 74.5341, "student_count": 0},
      {"name": "Sangamnagar", "latitude": 16.7602, "longitude": 74.5208, "student_count": 0},
      {"name": "Khotwadi", "latitude": 16.7523, "longitude": 74.5050, "student_count": 0},
      {"name": "Yadrav Phata", "latitude": 16.7460, "longitude": 74.4900, "student_count": 0},
      {"name": "SIT", "latitude": 16.7410, "longitude": 74.4755, "student_count": 0},
    ];

    await firestore.collection("routes").doc("Sangli-SIT").set({
      "bus_location": {"latitude": 16.8524, "longitude": 74.5815},
      "stops": sangliStops,
      "route_points": sangliStops
          .map((s) => {"latitude": s["latitude"], "longitude": s["longitude"]})
          .toList(),
    });

    // --- KOLHAPUR-SIT ---
    final kolhapurStops = [
      {"name": "Vashi Naka", "latitude": 16.7040, "longitude": 74.2430, "student_count": 0},
      {"name": "Saneguruji Vasahat", "latitude": 16.7002, "longitude": 74.2501, "student_count": 0},
      {"name": "Devkar Panand", "latitude": 16.7050, "longitude": 74.2602, "student_count": 0},
      {"name": "Sambhajinagar", "latitude": 16.7105, "longitude": 74.2708, "student_count": 0},
      {"name": "Hockey Stadium", "latitude": 16.7152, "longitude": 74.2800, "student_count": 0},
      {"name": "Gokhale College", "latitude": 16.7203, "longitude": 74.2902, "student_count": 0},
      {"name": "Rajaram Puri", "latitude": 16.7254, "longitude": 74.3005, "student_count": 0},
      {"name": "Ujlagaon", "latitude": 16.7301, "longitude": 74.3108, "student_count": 0},
      {"name": "Mudshingi", "latitude": 16.7352, "longitude": 74.3250, "student_count": 0},
      {"name": "Vasagade", "latitude": 16.7402, "longitude": 74.3355, "student_count": 0},
      {"name": "Pattankodoli", "latitude": 16.7455, "longitude": 74.3452, "student_count": 0},
      {"name": "Ingali", "latitude": 16.7508, "longitude": 74.3550, "student_count": 0},
      {"name": "Rui", "latitude": 16.7555, "longitude": 74.3655, "student_count": 0},
      {"name": "Kabnur", "latitude": 16.7605, "longitude": 74.3750, "student_count": 0},
      {"name": "Sakhar Karkhana", "latitude": 16.7658, "longitude": 74.3855, "student_count": 0},
      {"name": "SIT", "latitude": 16.7410, "longitude": 74.4755, "student_count": 0},
    ];

    await firestore.collection("routes").doc("Kolhapur-SIT").set({
      "bus_location": {"latitude": 16.7040, "longitude": 74.2430},
      "stops": kolhapurStops,
      "route_points": kolhapurStops
          .map((s) => {"latitude": s["latitude"], "longitude": s["longitude"]})
          .toList(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Routes uploaded successfully!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Upload Routes to Firestore")),
      body: Center(
        child: ElevatedButton(
          onPressed: uploadRoutes,
          child: const Text("Upload Routes"),
        ),
      ),
    );
  }
}
