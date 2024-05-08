import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_room_screen.dart';
import 'home_page.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({Key? key}) : super(key: key);

  @override
  _LoadingScreenState createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  bool _shouldStoreUserId = true;
  int _currentPage = 0;
  final List<Map<String, String>> _messages = [
    {
      'title': 'Talking to Strangers',
      'subtitle': 'Remember to be cautious while talking to strangers online.'
    },
    {
      'title': 'Stay Safe',
      'subtitle':
          'Avoid sharing personal information with people you don\'t know well.'
    },
    {
      'title': 'Enjoy the Conversation',
      'subtitle':
          'Have fun while meeting new people, but always prioritize your safety.'
    },
  ];
  late StreamController<int> _pageControllerStream;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _pageControllerStream = StreamController<int>();
    _startTimer();
    printCurrentUserUID(); // Print current user's UID
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageControllerStream.close();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 3), (Timer timer) {
      _pageControllerStream.add(_currentPage + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/background.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: PopScope(
          canPop: true,
          onPopInvoked: (bool didPop) async {
            if (didPop) {
              _shouldStoreUserId = false;
              await deleteUserFromFirestore();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(20), // Adjust the padding as needed
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StreamBuilder<int>(
                    stream: _pageControllerStream.stream,
                    initialData: 0,
                    builder:
                        (BuildContext context, AsyncSnapshot<int> snapshot) {
                      _currentPage = snapshot.data ?? 0;
                      return Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(
                                  0.5), // Gray transparent background
                              borderRadius: BorderRadius.circular(
                                  10), // Optional: border radius
                            ),
                            padding: EdgeInsets.all(
                                10), // Optional: padding for texts
                            child: ListTile(
                              title: Text(
                                _messages[_currentPage % _messages.length]
                                    ['title']!,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize:
                                      20, // Increase the font size for title
                                ),
                              ),
                              subtitle: Text(
                                _messages[_currentPage % _messages.length]
                                    ['subtitle']!,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize:
                                      16, // Increase the font size for content
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      );
                    },
                  ),
                  LinearProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    backgroundColor: Colors.grey[350],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      // Get current user
                      User? user = FirebaseAuth.instance.currentUser;
                      _shouldStoreUserId = false;
                      if (user != null) {
                        // User is signed in
                        String userId = user.uid;
                        // Delete user from "users" collection
                        try {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(userId)
                              .delete();
                          print(
                              'User $userId deleted from "users" collection.');
                        } catch (error) {
                          print(
                              'Failed to delete user $userId from "users" collection: $error');
                        }
                      }
                      // Navigate back to the home page
                      Navigator.pop(
                        context,
                      );
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void printCurrentUserUID() async {
    // Get current user
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // User is signed in
      print('Current User UID: ${user.uid}');

      // Store current user's ID to Firestore
      await storeUserIDToFirestore(user.uid);

      // Fetch all user IDs from Firestore
      FirebaseFirestore.instance
          .collection('users')
          .get()
          .then((querySnapshot) async {
        List<String> allUserIds = [];
        querySnapshot.docs.forEach((doc) {
          allUserIds.add(doc.id);
        });

        // Pair up the users
        List<List<String>> pairs = [];
        for (int i = 0; i < allUserIds.length; i += 2) {
          if (i + 1 < allUserIds.length) {
            pairs.add([allUserIds[i], allUserIds[i + 1]]);
          } else {
            // If there's an odd number of users, handle the last one separately
            pairs.add([allUserIds[i]]);
          }
        }

        // Store pairs in Firestore with unique room IDs if both users have been paired
        for (int i = 0; i < pairs.length; i++) {
          List<String> pair = pairs[i];
          if (pair.length == 2) {
            String roomId = generateRoomId();
            await FirebaseFirestore.instance
                .collection('rooms')
                .doc(roomId)
                .set({
              'roomID': roomId,
              'occupant1': pair[0],
              'occupant2': pair[1],
            });
            print('Pair $pair stored with Room ID $roomId in Firestore.');

            // Delete users from "users" collection
            for (String userId in pair) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .delete();
              print('User $userId deleted from "users" collection.');
            }
          }
        }

        // Check if the current user is in any room
        await checkUserInRoom(user.uid);
      }).catchError((error) {
        print('Failed to fetch user IDs: $error');
      });
    } else {
      // No user is signed in
      print('No user signed in.');
    }
  }

  Future<void> checkUserInRoom(String userId) async {
    QuerySnapshot roomSnapshot =
        await FirebaseFirestore.instance.collection('rooms').get();
    for (QueryDocumentSnapshot roomDoc in roomSnapshot.docs) {
      List<String> occupants = [roomDoc['occupant1'], roomDoc['occupant2']];
      if (occupants.contains(userId)) {
        // User is in a room, print room details and navigate to chat room
        String roomId = roomDoc['roomID'];
        print(
            'User $userId is in a room with Room ID: $roomId and Occupants: $occupants.');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatRoomScreen(
              roomId: roomId,
              occupants: occupants,
              currentUserId: userId, // Pass the current user's ID
            ),
          ),
        );
        return; // Exit the function after finding the user in a room
      }
    }

    await checkUserInRoom(userId); // Check again recursively
  }

  Future<void> storeUserIDToFirestore(String userId) async {
    try {
      // Add a delay of 5 seconds before storing the user ID
      await Future.delayed(const Duration(seconds: 5));

      if (!_shouldStoreUserId) {
        // If the operation should not proceed, return without storing the user ID
        return;
      }
      // Check if the "users" collection exists
      final usersCollection = FirebaseFirestore.instance.collection('users');
      final usersSnapshot = await usersCollection.get();

      if (usersSnapshot.size == 2) {
        print(
            'The users collection already contains two documents. Retrying to store the user ID.');

        final random = Random();
        final waitTime = random.nextInt(3) + 1;
        await Future.delayed(Duration(seconds: waitTime));

        await storeUserIDToFirestore(userId);
        return; // Exit function after retry
      }

      // Store the user ID since either the collection doesn't exist or it has less than two documents
      await usersCollection.doc(userId).set({});
      print('User ID $userId stored to Firestore successfully.');
    } catch (error) {
      print('Failed to store user ID to Firestore: $error');
    }
  }

  Future<void> deleteUserFromFirestore() async {
    // Get current user
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // User is signed in
      String userId = user.uid;
      // Delete user from "users" collection
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .delete();
        print('User $userId deleted from "users" collection.');
      } catch (error) {
        print('Failed to delete user $userId from "users" collection: $error');
      }
    }
  }

  String generateRoomId() {
    // Generate a unique room ID
    String roomId = '';
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    for (int i = 0; i < 6; i++) {
      roomId += chars[random.nextInt(chars.length)];
    }
    return roomId;
  }
}
