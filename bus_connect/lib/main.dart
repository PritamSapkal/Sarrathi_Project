import 'package:bus_connect/WelcomePage.dart';
import 'package:bus_connect/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart' as FMTC;



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  Object? initErr;
  try {
    await FMTC.FMTCObjectBoxBackend().initialise();
  } catch (err) {
    initErr = err;
    debugPrint('FMTC initialization error: $err');
  }

  runApp(MyApp(initialisationError: initErr));
}



class MyApp extends StatelessWidget {
  final Object? initialisationError;
  const MyApp({super.key, this.initialisationError});

  @override
  Widget build(BuildContext context) {
    if (initialisationError != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'FMTC Initialization Error: $initialisationError',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: "Saarthi",
          theme: ThemeData(
            primarySwatch: Colors.yellow,
          ),
          home: child,
        );
      },
      child: const WelcomePage(),
    );
  }
}
