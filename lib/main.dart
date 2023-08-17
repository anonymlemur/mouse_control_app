import 'dart:math';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

void main() => runApp(MyApp());

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
  bool _showJoystick  = false;
  IOWebSocketChannel? socketChannel;
  String _currentMessage = '';

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    RawKeyboard.instance.addListener(_handleKey);
  }

  @override
  void dispose() {
    _disconnectFromServer();
    RawKeyboard.instance.removeListener(_handleKey);
    super.dispose();
  }

  // --- Server and Websocket Methods ---

  void _loadSavedData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      ipController.text = prefs.getString('ip') ?? '192.168.1.23';
      portController.text = prefs.getString('port') ?? '12345';
    });
  }

  void _saveData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('ip', ipController.text);
    prefs.setString('port', portController.text);
  }

  void _connectToServer() {
    final String serverAddress = ipController.text;
    final int serverPort = int.tryParse(portController.text) ?? 12345;

    socketChannel =
        IOWebSocketChannel.connect('ws://$serverAddress:$serverPort');
    socketChannel!.stream.listen(
          (event) => print('Received: $event'),
      onError: (error) => print('WebSocket Error: $error'),
      onDone: () => print('WebSocket connection closed'),
    );

    _saveData();
    Navigator.of(context).pop();  // Close the drawer after connecting
  }

  void _disconnectFromServer() {
    socketChannel?.sink.close();
  }

  void _sendCommand(String command, [Map<String, dynamic>? params]) {
    String data = '$command';
    if (params != null) {
      data += ':${params.values.join(",")}';
    }
    socketChannel?.sink.add(data);
    _currentMessage = data;
    print('Sent: $_currentMessage');
  }

  // --- Event Handling ---

  void _handleKey(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      final String key = event.logicalKey.keyLabel;
      _sendCommand('KEYBOARD', {'key': key});
    }
  }

  void _toggleKeyboardVisibility() {
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom != 0;
    SystemChannels.textInput
        .invokeMethod(isKeyboardVisible ? 'TextInput.hide' : 'TextInput.show');
  }

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text('Mouse Control'),
        leading: IconButton(
          icon: Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState!.openDrawer(),
        ),
      ),
      drawer: _buildDrawer(),
      body: _buildBody(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: ipController, decoration: InputDecoration(labelText: 'Server IP')),
            SizedBox(height: 10),
            TextField(controller: portController, decoration: InputDecoration(labelText: 'Server Port')),
            SizedBox(height: 20),
            ElevatedButton(onPressed: _connectToServer, child: Text('Connect')),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_showTouchpad) TouchPad(this),
              if (_showJoystick) JoystickWidget(this),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _buildControlButtons(),
        ),
      ],
    );
  }

  Widget _buildControlButtons() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.1,
      color: Colors.grey[200],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: _toggleKeyboardVisibility,
            child: Icon(Icons.keyboard, size: 64),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _showTouchpad = true;
              _showJoystick  = false;
            }),
            child: Icon(Icons.touch_app, size: 64),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _showTouchpad = false;
              _showJoystick  = true;
            }),
            child: Icon(Icons.play_circle_fill, size: 64),
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
    final touchPadSize = MediaQuery.of(context).size;
    return Container(
      width: touchPadSize.width,
      height: touchPadSize.height * 0.9,
      color: Colors.grey[300],
      child: GestureDetector(
        onPanStart: (_) => parentState._sendCommand('MOVE', {'delta_x': 0, 'delta_y': 0}),
        onPanUpdate: (details) {
          parentState._sendCommand('MOVE', {
            'delta_x': details.delta.dx.toInt(),
            'delta_y': details.delta.dy.toInt()
          });
        },
        onPanEnd: (_) => parentState._sendCommand('STOP_MOVE'),
        onTap: () => parentState._sendCommand('LEFT_CLICK'),
        onLongPress: () => parentState._sendCommand('RIGHT_CLICK'),
      ),
    );
  }
}
class JoystickWidget extends StatefulWidget {
  final _MouseControlScreenState parentState;

  JoystickWidget(this.parentState);

  @override
  _JoystickWidgetState createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  double _x = 0.0;
  double _y = 0.0;

  // Define the radius of the grey circle
  final double _outerCircleRadius = 75.0;

  void _onPanUpdate(DragUpdateDetails details) {
    double x = details.localPosition.dx - _outerCircleRadius;
    double y = details.localPosition.dy - _outerCircleRadius;
    double distance = sqrt(x * x + y * y);

    // Restrict the movement of the blue circle within the bounds of the grey circle
    if (distance > _outerCircleRadius) {
      double angle = atan2(y, x);
      x = _outerCircleRadius * cos(angle);
      y = _outerCircleRadius * sin(angle);
    }

    setState(() {
      _x = x;
      _y = y;
    });

    // Normalize the deltas to be between -5 and 5
    int normalizedDeltaX = ((5 * x) / _outerCircleRadius).toInt();
    int normalizedDeltaY = ((5 * y) / _outerCircleRadius).toInt();

    widget.parentState._sendCommand('MOVE', {
      'delta_x': normalizedDeltaX,
      'delta_y': normalizedDeltaY
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _x = 0.0;
      _y = 0.0;
    });

    widget.parentState._sendCommand('STOP_MOVE');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Container(
        width: 2 * _outerCircleRadius,
        height: 2 * _outerCircleRadius,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Transform.translate(
            offset: Offset(_x, _y),
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}