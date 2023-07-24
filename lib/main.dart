import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mouse Control App',
      home: MouseControlScreen(),
    );
  }
}

class MouseControlScreen extends StatefulWidget {
  @override
  _MouseControlScreenState createState() => _MouseControlScreenState();
}

class _MouseControlScreenState extends State<MouseControlScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController ipController = TextEditingController();
  final TextEditingController portController = TextEditingController();
  bool _showTouchpad = false;
  bool _showMediaControl = false;

  IOWebSocketChannel? socketChannel;

  // Variable to store the current WebSocket message
  String _currentMessage = '';

  @override
  void dispose() {
    disconnectFromServer();
    RawKeyboard.instance.removeListener(_handleKey);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    loadSavedData(); // Load the saved IP and PORT when the widget is initialized
    RawKeyboard.instance.addListener(_handleKey);
  }

  void loadSavedData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      ipController.text = prefs.getString('ip') ??
          '192.168.1.23'; // Load the saved IP, or an empty string if not saved yet
      portController.text = prefs.getString('port') ??
          '12345'; // Load the saved PORT, or an empty string if not saved yet
    });
  }

  void saveData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('ip', ipController.text); // Save the IP
    prefs.setString('port', portController.text); // Save the PORT
  }

  void connectToServer() {
    final String serverAddress = ipController.text;
    final int serverPort = int.tryParse(portController.text) ?? 12345;

    socketChannel =
        IOWebSocketChannel.connect('ws://$serverAddress:$serverPort');

    // Optional: Add listeners for connection events
    socketChannel!.stream.listen(
      (event) {
        print('Received: $event');
      },
      onError: (error) {
        print('WebSocket Error: $error');
      },
      onDone: () {
        print('WebSocket connection closed');
      },
    );
    saveData();
    // Close the drawer after connecting
    Navigator.of(context).pop();
  }

  void disconnectFromServer() {
    socketChannel?.sink.close();
  }

  void sendCommand(String command, [Map<String, dynamic>? params]) {
    String data = '$command';
    if (params != null) {
      data += ':';
      params.forEach((key, value) {
        data += '$value,';
      });
      data = data.substring(0, data.length - 1); // Remove the trailing comma
    }

    socketChannel?.sink.add(data);
    _currentMessage = data;
    print('Sent: $_currentMessage');
  }

  void _handleKey(RawKeyEvent event) {
    if (event.runtimeType == RawKeyDownEvent) {
      final String key = event.logicalKey.keyLabel;
      sendCommand('KEYBOARD', {'key': key});
    }
  }

  void toggleKeyboard() {
    // If the keyboard is visible, hide it; otherwise, show it.
    if (MediaQuery.of(context).viewInsets.bottom == 0) {
      // Show the keyboard
      SystemChannels.textInput.invokeMethod('TextInput.show');
    } else {
      // Hide the keyboard
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text('Mouse Control'),
        leading: IconButton(
          icon: Icon(Icons.menu),
          onPressed: () {
            _scaffoldKey.currentState!.openDrawer();
          },
        ),
      ),
      drawer: Drawer(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: ipController,
                decoration: InputDecoration(labelText: 'Server IP'),
              ),
              SizedBox(height: 10),
              TextField(
                controller: portController,
//                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Server Port'),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  // Connect to the server
                  connectToServer();
                },
                child: Text('Connect'),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_showTouchpad) TouchPad(this),
                //if (_showMediaControl)
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: MediaQuery.of(context).size.height *
                  0.1, // 10% of screen height
              color: Colors.grey[200], // Adjust the color as needed
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GestureDetector(
                    onTap: () {
                      toggleKeyboard();
                    },
                    child: Icon(
                      Icons.keyboard,
                      size: 64,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showTouchpad = true;
                        _showMediaControl = false;
                      });
                    },
                    child: Icon(
                      Icons.touch_app,
                      size: 64,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showTouchpad = false;
                        _showMediaControl = true;
                      });
                    },
                    child: Icon(
                      Icons.play_circle_fill,
                      size: 64,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TouchPad extends StatelessWidget {
  final _MouseControlScreenState parentState;

  TouchPad(this.parentState);

  @override
  Widget build(BuildContext context) {
    final touchPadWidth = MediaQuery.of(context).size.width;
    final touchPadHeight = MediaQuery.of(context).size.height * 0.9;

    return Container(
      width: touchPadWidth,
      height: touchPadHeight,
      color: Colors.grey[300],
      child: GestureDetector(
        onPanStart: (_) {
          parentState.sendCommand('MOVE', {'delta_x': 0, 'delta_y': 0});
        },
        onPanUpdate: (details) {
          int delta_x = details.delta.dx.toInt();
          int delta_y = details.delta.dy.toInt();
          parentState
              .sendCommand('MOVE', {'delta_x': delta_x, 'delta_y': delta_y});
        },
        onPanEnd: (_) {
          parentState.sendCommand('STOP_MOVE');
        },
        onTap: () {
          parentState.sendCommand('LEFT_CLICK');
        },
        onLongPress: () {
          parentState.sendCommand('RIGHT_CLICK');
        },
      ),
    );
  }
}
