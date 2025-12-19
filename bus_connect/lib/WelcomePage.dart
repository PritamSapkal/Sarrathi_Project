import 'dart:async';
import 'package:bus_connect/SignInPage.dart';
import 'package:bus_connect/StudentDashBoard.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';


class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  @override
  void initState() {
    super.initState();
    Timer(Duration(seconds: 3), () {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => FirebaseAuth.instance.currentUser != null ? const SignInPage(): const SignInPage(),),);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.yellow.shade600,
          border: Border.all(width: 10.w, color: Colors.white),
          borderRadius: BorderRadius.circular(50),
        ),
        child:
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 170.w,
              height: 170.h,
              decoration: BoxDecoration(
                color: Colors.orangeAccent,
                shape: BoxShape.circle,
                border: Border.all(width: 10.w, color: Colors.white),
                boxShadow:  [
                  BoxShadow(
                      color: Colors.black45, blurRadius:10.r, spreadRadius: 5.r)
                ],
              ),
              child:  Center(
                child: Text(
                  "Saarathi",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize:30.sp,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),// logo code
            SizedBox(height: 10.h),
            Text(
              "Saarathi",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 60.sp,
                  fontWeight: FontWeight.bold),
            ), // bus connect text
            SizedBox(height: 5.h),
            Text(
              "Your ride to campus, sorted.",
              style: TextStyle(
                  color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),// text under bus connect.
            SizedBox(height: 10.h,),
            SizedBox(
              height:200.h,
              width: 200.w,
              child: SpinKitWanderingCubes(
              color: Colors.white,
              size: 80.sp,

            )
            ),
          ],
        ),
      ),
    );
  }
}


