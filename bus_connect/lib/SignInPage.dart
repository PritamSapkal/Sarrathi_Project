import 'package:bus_connect/DriverDashBoard.dart';
import 'package:bus_connect/SignUpPage.dart';
import 'package:bus_connect/StudentDashBoard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';


class SignInPage extends StatefulWidget{

  const SignInPage();
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {

  var emailController= TextEditingController();
  var passController= TextEditingController();
  bool isLoading = false;
  bool isStudent = true;

  String statusMessage = '';
  Color messageColor = Colors.black;

  Future<void> loginUserWithEmailAndPasswordasStudent() async {
    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passController.text.trim(),

      );
      //print(userCredential.user?.email); // works safely
    } on FirebaseAuthException catch (e) {
      throw e; // let the button's onPressed handle the UI update
    }
  }
// data cross check function.

  @override
  Widget build(BuildContext context) {
    final isKeyboard=MediaQuery.of(context).viewInsets.bottom != 0;
    return Scaffold(
      body:
      Wrap(
                children:[
                  Container(
                  width: double.infinity,
                  height:1000.h,
                  padding:  EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.yellow.shade600,width:8.w),
                    borderRadius: BorderRadius.circular(40.r),
                  ),

                  child:
                  Column(
                    children: [

                      SizedBox(height:70.h,),

                      isKeyboard == false ? Container(
                                            width: 150.w,
                                            height: 150.h,
                                           child: Center(
                                                  child: Text("Saarathi",style: TextStyle(color: Colors.white, fontSize: 30.sp, fontWeight: FontWeight.bold,),),
                                             ),
                                          decoration: BoxDecoration(
                          color: Colors.orangeAccent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            width: 5.w,
                            color: Colors.yellow.shade600,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black45,
                              blurRadius: 10.r,
                              spreadRadius: 2.r,
                            )
                          ],
                        ),) : SizedBox(),// logo code

                      SizedBox(height:10.h,),

                      Text("Welcome Back!",style: TextStyle(color: Colors.black, fontSize:45.sp, fontWeight: FontWeight.bold),),// logo Code

                      SizedBox(height: 10.h,),

                      Text("Sign In Here",style: TextStyle(color: Colors.grey,fontWeight: FontWeight.w500,fontSize:23.sp),),

                      SizedBox(height: 10.h,),

                      Container(
                        width:300.w,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [Text("Email Address",style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w800,fontSize:20.sp),)],
                        ),
                      ),// EmalAdrees text

                      SizedBox(height: 5.h,),

                      Container(
                        width: 320.w,
                        child: TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: "Email Address",
                            prefixIcon: Icon(Icons.email_sharp, color: Colors.black,),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20.r),
                                borderSide: BorderSide(
                                    color: const Color(0xFFFCB900),
                                    width:3.w
                                )
                            ),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20.r),
                                borderSide: BorderSide(
                                    color: Colors.black,
                                    width:3.w
                                )
                            ),

                          ),
                        ),
                      ),// Email text box,

                      SizedBox(height: 10.h,),

                      Container(
                        width:300.w,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [Text("Password",style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w800,fontSize:20.sp),)],
                        ),
                      ),// Password Text

                      SizedBox(height: 5.h,),

                      Container(
                        width: 320.w,
                        child: TextField(
                          controller: passController,
                          keyboardType: TextInputType.text,
                          obscureText: false,
                          // obscuringCharacter: "*",
                          decoration: InputDecoration(
                              hintText: "Password",
                              prefixIcon: Icon(Icons.password, color: Colors.black,),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20.r),
                                  borderSide: BorderSide(
                                      color: const Color(0xFFFCB900),
                                      width:3.w,
                                  )
                              ),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20.r),
                                  borderSide: BorderSide(
                                      color: Colors.black,
                                      width:3.w
                                  )
                              )
                          ),
                        ),
                      ), // Password text box

                      SizedBox(height: 10.h,),


                      InkWell(
                        child:Container(width:300.w,
                            child:
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text("Forgot password?",style: TextStyle(fontWeight: FontWeight.bold,fontSize: 14.sp, color: const Color(0xFFD9A441)),)
                              ],
                            )),
                        onTap: (){
                          print("No link Added , First add the link and then click !!");
                        },), // forgot password

                      SizedBox(height:10.h),

                      Container(
                        width: 320.w,
                        height: 45.h,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFCB900), // your orange color
                            shadowColor: Colors.black54,
                            elevation: 6.r,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20.r),
                            ),
                          ),
                          onPressed: () async {
                            setState(() {
                              isLoading = true;
                              statusMessage = "Wait for a moment!";
                              messageColor = Colors.black;
                            });

                            try {
                              await loginUserWithEmailAndPasswordasStudent(); // login

                              final uid = FirebaseAuth.instance.currentUser!.uid;

                              // Check if user exists in 'drivers' collection
                              final driverDoc = await FirebaseFirestore.instance.collection('drivers').doc(uid).get();

                              if (driverDoc.exists) {
                                // ✅ Fetch routeName for Driver
                                String routeName = driverDoc.data()?['routeName'] ?? "Unknown Route";

                                // Navigate to Driver Dashboard with routeName
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (_) => DriverDashBoard(routeName: routeName)),
                                );
                              } else {
                                // Check if user exists in 'users' collection
                                final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

                                if (userDoc.exists) {
                                  // ✅ Fetch routeName for Student
                                  String routeName = userDoc.data()?['routeName'] ?? "Unknown Route";

                                  // Navigate to Student Dashboard with routeName
                                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => StudentDashBoard(routeName: routeName)),
                                  );
                                } else {
                                  // ❌ User not found in Firestore
                                  setState(() {
                                    isLoading = false;
                                    statusMessage = "* Invalid Email or Password";
                                    messageColor = Colors.red;
                                  });
                                  FirebaseAuth.instance.signOut();
                                }
                              }
                            } on FirebaseAuthException catch (e) {
                              setState(() {
                                isLoading = false;
                                statusMessage = "*The entered password is incorrect or user \n does not exist";
                                messageColor = Colors.red;
                              });
                            } catch (e) {
                              setState(() {
                                isLoading = false;
                                statusMessage = "*An error occurred. Please try again later";
                                messageColor = Colors.red;
                              });
                            }
                          },


                          child: isLoading
                              ?  SizedBox(
                            width:24.w,
                            height:24.h,
                            child: SpinKitFadingCircle(color: Colors.white, size:24,),
                          ) : Text("Sign In", style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.bold,),),
                          ),
                        ),
                      // sign in button code

                      SizedBox(height: 20.h,),

                      Container(
                          width:320.w,
                          child:Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Don't have an account?",style: TextStyle(color:Colors.grey, fontSize: 18.sp,fontWeight:FontWeight.w700),),
                              SizedBox(width: 3.w,),
                              InkWell(
                                child: Text("Sign Up here",style: TextStyle(color: const Color(0xFFD9A441), fontSize: 18.sp,fontWeight:FontWeight.w700),),
                                onTap: (){
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => SignUpPage()));
                                },
                              )
                            ],
                          )
                      ),// Sign up here textbutton. link to the signup page

                      SizedBox(height: 10.h,),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(statusMessage,style: TextStyle(color:messageColor, fontSize:15.sp,fontWeight:FontWeight.w700),),
                        ],
                      )// Message text after clicking sign in button


                    ],
                  ),// all the element of the page.
                ),
                ]),


    );
  }
}