import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await requestPermissions();
  runApp(MyApp());
}

Future<void> requestPermissions() async {
  await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
  ].request();
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HC-06 Bluetooth Reader',
      theme: ThemeData.dark(),
      home: BluetoothDataPage(),
    );
  }
}

class BluetoothDataPage extends StatefulWidget {
  @override
  _BluetoothDataPageState createState() => _BluetoothDataPageState();
}

class _BluetoothDataPageState extends State<BluetoothDataPage> {
  List<FlSpot> _spo2Data = [];
  List<FlSpot> _bpmData = [];
  int _xCounter = 0;

  BluetoothConnection? connection;
  String _connectionStatus = 'Disconnected';
  String _receivedData = '';
  String _latestRawData = '';
  int? latestSPO2;
  int? latestBPM;

  @override
  void initState() {
    super.initState();
    connectToDevice();
  }

  @override
  void dispose() {
    connection?.dispose();
    super.dispose();
  }

  void connectToDevice() async {
    try {
      setState(() => _connectionStatus = 'Connecting...');
      BluetoothConnection newConnection =
      await BluetoothConnection.toAddress("00:23:09:01:17:61");

      setState(() {
        connection = newConnection;
        _connectionStatus = 'Connected';
      });

      String buffer = '';

      connection!.input?.listen((Uint8List data) {
        final incoming = utf8.decode(data, allowMalformed: true);
        buffer += incoming;

        while (buffer.contains('\n')) {
          final endIndex = buffer.indexOf('\n');
          final line = buffer.substring(0, endIndex).trim();
          buffer = buffer.substring(endIndex + 1);

          _processLine(line);
        }
      }, onDone: () {
        setState(() {
          _connectionStatus = 'Disconnected';
          connection = null;
        });
      });
    } catch (e) {
      setState(() => _connectionStatus = 'Failed: $e');
    }
  }

  void _processLine(String line) {
    setState(() => _receivedData = line);

    final spo2Match = RegExp(r"SPO2:(\d+)").firstMatch(line);
    final bpmMatch = RegExp(r"BPM:(\d+)").firstMatch(line);

    final spo2 = spo2Match != null ? int.tryParse(spo2Match.group(1)!) : null;
    final bpm = bpmMatch != null ? int.tryParse(bpmMatch.group(1)!) : null;

    if (spo2 != null || bpm != null) {
      setState(() {
        if (spo2 != null) {
          latestSPO2 = spo2;
          _spo2Data.add(FlSpot(_xCounter.toDouble(), spo2.toDouble()));
          if (_spo2Data.length > 20) _spo2Data.removeAt(0);
        }
        if (bpm != null) {
          latestBPM = bpm;
          _bpmData.add(FlSpot(_xCounter.toDouble(), bpm.toDouble()));
          if (_bpmData.length > 20) _bpmData.removeAt(0);
        }
        _xCounter++;
      });
    }
  }

  void generateRandomValues() {
    final random = Random();
    final randomSpo2 = 95 + random.nextInt(6);  // 95–100
    final randomBpm = 60 + random.nextInt(41);  // 60–100

    setState(() {
      _spo2Data.add(FlSpot(_xCounter.toDouble(), randomSpo2.toDouble()));
      _bpmData.add(FlSpot(_xCounter.toDouble(), randomBpm.toDouble()));
      if (_spo2Data.length > 20) _spo2Data.removeAt(0);
      if (_bpmData.length > 20) _bpmData.removeAt(0);
      latestSPO2 = randomSpo2;
      latestBPM = randomBpm;
      _xCounter++;
    });
  }

  LineChartData getChartData() {
    return LineChartData(
      minY: 0,
      maxY: 150,
      backgroundColor: Colors.grey[900],
      titlesData: FlTitlesData(show: false),
      gridData: FlGridData(show: false),
      borderData:
      FlBorderData(show: true, border: Border.all(color: Colors.white24)),
      lineBarsData: [
        LineChartBarData(
          spots: _spo2Data,
          isCurved: true,
          barWidth: 2,
          color: Colors.redAccent,
          dotData: FlDotData(show: false),
        ),
        LineChartBarData(
          spots: _bpmData,
          isCurved: true,
          barWidth: 2,
          color: Colors.yellowAccent,
          dotData: FlDotData(show: false),
        ),
      ],
    );
  }

  void reconnect() {
    connection?.dispose();
    connection = null;
    connectToDevice();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('SPO2 & BPM Monitor'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(icon: Icon(Icons.refresh), onPressed: reconnect),
        ],
      ),
      body: Column(
        children: [
          // Status
          Container(
            margin: EdgeInsets.all(12),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _connectionStatus == 'Connected'
                  ? Colors.green[800]
                  : Colors.red[800],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Status: $_connectionStatus',
              style: TextStyle(color: Colors.white),
            ),
          ),
          // Latest values
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text('SPO2: ${latestSPO2 ?? "--"}',
                    style: TextStyle(color: Colors.redAccent, fontSize: 16)),
                SizedBox(width: 20),
                Text('BPM: ${latestBPM ?? "--"}',
                    style: TextStyle(color: Colors.yellowAccent, fontSize: 16)),
              ],
            ),
          ),
          // Chart
          Container(
            height: screenHeight * 0.4,
            margin: EdgeInsets.all(12),
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
            ),
            child: _spo2Data.isEmpty && _bpmData.isEmpty
                ? Center(
                child: Text('No data yet',
                    style: TextStyle(color: Colors.white70)))
                : LineChart(getChartData()),
          ),
          Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: reconnect,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent),
                child: Text("Reconnect"),
              ),
              ElevatedButton(
                onPressed: generateRandomValues,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purpleAccent),
                child: Text("Test Random"),
              ),
            ],
          ),
          SizedBox(height: 30),
        ],
      ),
    );
  }
}
