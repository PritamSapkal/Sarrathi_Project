import 'dart:async';
import 'package:bus_connect/SignInPage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  // Controllers
  var nameController = TextEditingController();
  var emailController = TextEditingController();
  var passController = TextEditingController();
  var confirmpasswordcontroller = TextEditingController();
  var phonenumbercontroller = TextEditingController();

  bool isSignUp = false; // Used for button loading state (Sign Up button)
  bool _isLoading = true; // State for loading routes/stops data

  String _statusMessage = '';
  Color _messageColor = Colors.black;

  // Dropdown data
  String? selectedRoute;
  String? selectedStop;

  List<String> routeNames = [];
  final Map<String, List<String>> routesWithStops = {};
  List<String> stopsForSelectedRoute = [];

  @override
  void initState() {
    super.initState();
    _fetchRoutes();
  }

  // ----------------------------------------------------------------------
  // Function to Fetch ONLY Route Names from Firestore
  // ----------------------------------------------------------------------
  Future<void> _fetchRoutes() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('routes').get();

      final fetchedRoutes = snapshot.docs.map((doc) => doc.id).toList();

      if (mounted) {
        setState(() {
          routeNames = fetchedRoutes;
          _isLoading = false; // Data is loaded
        });
      }
    } catch (e) {
      print("Error fetching routes: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = "Failed to load routes data.";
          _messageColor = Colors.red;
        });
      }
    }
  }


  Future<void> createUserWithEmailAndPassword() async {
    try {
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passController.text.trim(),
      );
      User? user = userCredential.user;

      if (user != null) {
        await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
          'name': nameController.text.trim(),
          'email': emailController.text.trim(),
          'phone_number': phonenumbercontroller.value.text.trim(),
          'routeName': selectedRoute.toString(),
          'createdAt': DateTime.now(),
        }).then((_) {
          print("Firestore: User data added ✅");
        }).catchError((e) {
          print("Firestore Error: $e");
        });
      }
    } on FirebaseAuthException catch (e) {
      _statusMessage = "*${e.message}";
      _messageColor = Colors.red;
      rethrow;
    }
  }

  // ----------------------------------------------------------------------
  // UI BUILD METHOD (SingleChildScrollView REMOVED)
  // ----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isKeyboard = MediaQuery.of(context).viewInsets.bottom != 0;

    return Scaffold(
      // ⭐️ SingleChildScrollView REMOVED here, relying on Wrap for scrolling behavior
      body: Wrap(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.yellow.shade600, width: 7.w),
              borderRadius: BorderRadius.circular(40.r),
            ),
            child: Column(
              children: [
                SizedBox(height: 5.h),
                if (!isKeyboard)
                 Column( children: [ Container(
                    width: 110.w,
                    height: 110.h,
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent,
                      shape: BoxShape.circle,
                      border: Border.all(width: 5.w, color: Colors.yellow.shade600),
                      boxShadow: [
                        BoxShadow(color: Colors.black45, blurRadius: 10.r, spreadRadius: 2.r)
                      ],
                    ),
                    child: Center(
                      child: Text(
                        "Saarathi",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20.sp,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                Text(
                  "Join Saarathi",
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 39.sp,
                      fontWeight: FontWeight.bold),
                ),

                Column(children: [
                  Text(
                    "Create your account to get started",
                    style: TextStyle(
                        color: Colors.grey,
                        fontSize: 17.sp,
                        fontWeight: FontWeight.w700),
                  ),
                  Text(
                    "with your bus trips",
                    style: TextStyle(
                        color: Colors.grey,
                        fontSize: 17.sp,
                        fontWeight: FontWeight.w700),
                  ),
                ]),
                ]),
                SizedBox(height: 7.h),

                // Full Name
                inputLabel("Full Name"),
                SizedBox(height: 2.5.h),
                inputField(nameController, "Name", Icons.perm_identity, TextInputType.text),
                SizedBox(height: 7.5.h),

                // Email
                inputLabel("Email Address"),
                SizedBox(height: 2.5.h),
                inputField(emailController, "Email address", Icons.email_sharp, TextInputType.emailAddress),
                SizedBox(height: 7.5.h),

                // Phone Number
                inputLabel("Phone Number"),
                SizedBox(height: 2.5.h),
                inputField(phonenumbercontroller, "Phone Number", Icons.phone, TextInputType.number),
                SizedBox(height: 7.5.h),

                // Password
                inputLabel("Password"),
                SizedBox(height: 2.5.h),
                inputField(passController, "Password", Icons.password, TextInputType.text, obscure: true),
                SizedBox(height: 7.5.h),

                // Confirm Password
                inputLabel("Confirm Password"),
                SizedBox(height: 2.5.h),
                inputField(confirmpasswordcontroller, "Confirm Password", Icons.password, TextInputType.text, obscure: true),
                SizedBox(height: 7.5.h),

                // select Route
                inputLabel("Select Route"),
                SizedBox(height: 2.5.h),

                // Route Dropdown or Loading Text
                _isLoading
                    ? Container(
                  width: 325.w,
                  padding: EdgeInsets.symmetric(vertical: 10.h),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black, width: 2.w),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Center(
                    // ⭐️ IMPLEMENTED: Loading text instead of CircularProgressIndicator
                    child: Text(
                      "Loading Routes...",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
                    : Container(
                  width: 325.w,
                  child: DropdownButtonFormField<String>(
                    value: selectedRoute,
                    decoration: InputDecoration(
                      icon: Icon(Icons.directions_bus_sharp, color: Colors.black),
                      labelText: "Select Route",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                    ),
                    items: routeNames.map((route) {
                      return DropdownMenuItem<String>(
                        value: route,
                        child: Text(route),
                      );
                    }).toList(),
                    onChanged: (String? value) {
                      setState(() {
                        selectedRoute = value;
                        selectedStop = null;
                        stopsForSelectedRoute = routesWithStops[value] ?? [];
                      });
                    },
                  ),
                ), // dropdown list for Routes

                SizedBox(height: 13.h),
                Container(
                  width: 320.w,
                  height: 40.h,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFCB900),
                      shadowColor: Colors.black54,
                      elevation: 6.r,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                    ),
                    onPressed: () async {
                      if (_isLoading || isSignUp) return;

                      setState(() {
                        isSignUp = true;
                        _statusMessage = '';
                        _messageColor = Colors.black;
                      });

                      var pass = passController.text.trim();
                      var confirmpass = confirmpasswordcontroller.text.trim();

                      if (pass == confirmpass) {
                        try {
                          await createUserWithEmailAndPassword();

                          setState(() {
                            isSignUp = false;
                            _statusMessage = "You registered successfully!";
                            _messageColor = Colors.green;
                          });

                          await Future.delayed(const Duration(seconds: 1));
                          if (mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => const SignInPage()),
                            );
                          }
                        } on FirebaseAuthException {
                          setState(() {
                            isSignUp = false;
                          });
                        } catch (e) {
                          setState(() {
                            isSignUp = false;
                            _statusMessage = "An unexpected error occurred.";
                            _messageColor = Colors.red;
                          });
                        }
                      } else {
                        setState(() {
                          isSignUp = false;
                          _statusMessage = "*Password and Confirm Password are not same";
                          _messageColor = Colors.red;
                        });
                      }
                    },
                    child: isSignUp
                        ? SizedBox(
                      width: 25.w,
                      height: 25.h,
                      // CircularProgressIndicator for the button
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                        : Text(
                      "Sign Up",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ), // sign up button

                SizedBox(height: 7.5.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Already have an account ?",
                      style: TextStyle(
                          color: Colors.grey,
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w700),
                    ),
                    SizedBox(width: 3.w),
                    InkWell(
                      child: Text(
                        "Sign in here",
                        style: TextStyle(
                            color: const Color(0xFFD9A441),
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w700),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ), // already have an account with sign in text button

                SizedBox(height: 5.h),
                Text(
                  _statusMessage,
                  style: TextStyle(
                      color: _messageColor,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20.h),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper method for input label
  Widget inputLabel(String text) {
    return Container(
      width: 320.w,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
                color: Colors.black45,
                fontWeight: FontWeight.w800,
                fontSize: 15.sp),
          ),
        ],
      ),
    );
  }

  Widget inputField(TextEditingController controller, String hint, IconData icon,
      TextInputType type, {bool obscure = false}) {
    return Container(
      width: 320.w,
      height: 43.5.h,
      child: TextField(
        controller: controller,
        keyboardType: type,
        obscureText: obscure,
        obscuringCharacter: "*",
        decoration: InputDecoration(
          hintText: hint,
          contentPadding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 10.w),
          prefixIcon: Icon(icon, color: Colors.black),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20.r),
              borderSide: BorderSide(color: Color(0xFFFCB900), width: 3.w)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20.r),
              borderSide: BorderSide(color: Colors.black, width: 2.w)),
        ),
      ),
    );
  }
}