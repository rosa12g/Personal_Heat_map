import 'dart:async';
import 'dart:isolate';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart';

class DataService {
  final Location _location = Location();
  StreamController<latlng.LatLng> _locationController = StreamController<latlng.LatLng>.broadcast();
  late FirebaseFirestore _firestore;
  bool _isFirebaseInitialized = false;

  DataService() {
    _initializeFirestore();
  }

  Future<void> _initializeFirestore() async {
    try {
      await Firebase.initializeApp();
      _firestore = FirebaseFirestore.instance;
      _isFirebaseInitialized = true;
      print('DataService: Firestore initialized successfully');
    } catch (e) {
      print('DataService: Error initializing Firestore: $e');
      _isFirebaseInitialized = false;
    }
  }

  Stream<latlng.LatLng> get onLocationChanged => _locationController.stream;

  Future<latlng.LatLng?> initLocation({
    required Function onPermissionDenied,
    required Function onServiceDisabled,
  }) async {
    print('DataService: Starting location initialization');
    try {
      // Check and request fine location permission
      var fineStatus = await Permission.locationWhenInUse.status;
      if (!fineStatus.isGranted) {
        fineStatus = await Permission.locationWhenInUse.request();
        print('DataService: Fine location permission status: $fineStatus');
        if (fineStatus.isDenied || fineStatus.isPermanentlyDenied) {
          print('DataService: Fine location permission denied');
          onPermissionDenied();
          return null;
        }
      }

      // Check and request background location
      var backgroundStatus = await Permission.locationAlways.status;
      if (!backgroundStatus.isGranted) {
        backgroundStatus = await Permission.locationAlways.request();
        print('DataService: Background location permission status: $backgroundStatus');
        if (backgroundStatus.isDenied || backgroundStatus.isPermanentlyDenied) {
          print('DataService: Background location permission denied');
          // Continue without background permission (worked before)
        }
      }

      // Check location service
      final serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        final enabled = await _location.requestService();
        print('DataService: Location service enabled: $enabled');
        if (!enabled) {
          print('DataService: Location service disabled');
          onServiceDisabled();
          return null;
        }
      }

      // Configure location settings
      await _location.changeSettings(
        interval: 1000,
        distanceFilter: 5,
        accuracy: LocationAccuracy.high,
      );

      // Get initial location
      print('DataService: Attempting to get location');
      final initialLoc = await _location.getLocation().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('DataService: Location request timed out');
          throw TimeoutException('Location request timed out');
        },
      );

      if (initialLoc.latitude != null && initialLoc.longitude != null) {
        final position = latlng.LatLng(initialLoc.latitude!, initialLoc.longitude!);
        print('DataService: Initial position: $position');
        _startLocationUpdates();
        return position;
      } else {
        print('DataService: Initial location is null: lat=${initialLoc.latitude}, lon=${initialLoc.longitude}');
        return null;
      }
    } catch (e) {
      print('DataService: Error getting initial location: $e');
      return null;
    }
  }

  void _startLocationUpdates() {
    _location.onLocationChanged.listen((loc) {
      print('DataService: Received location update - lat: ${loc.latitude}, lon: ${loc.longitude}, accuracy: ${loc.accuracy}, time: ${loc.time}');
      if (loc.latitude != null && loc.longitude != null) {
        final position = latlng.LatLng(loc.latitude!, loc.longitude!);
        _locationController.add(position);
        print('DataService: Streamed position: $position');
      } else {
        print('DataService: Invalid location update: lat=${loc.latitude}, lon=${loc.longitude}');
      }
    }, onError: (e) {
      print('DataService: Location update error: $e');
    }, onDone: () {
      print('DataService: Location stream closed');
    });
  }

  Future<void> updateLocation(String deviceId, latlng.LatLng position) async {
    if (!_isFirebaseInitialized) {
      print('DataService: Firebase not initialized, attempting to initialize');
      await _initializeFirestore();
      if (!_isFirebaseInitialized) {
        print('DataService: Firebase initialization failed, skipping location update');
        return;
      }
    }
    try {
      await _firestore.collection('locations').add({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'deviceId': deviceId,
      });
      print('DataService: Location updated successfully for deviceId: $deviceId');
    } catch (e) {
      print('DataService: Error updating location: $e');
    }
  }

  Future<List<Map<String, dynamic>>> generateHeatmap(String deviceId) async {
    if (!_isFirebaseInitialized) {
      print('DataService: Firebase not initialized, returning empty heatmap');
      return [];
    }
    try {
      return await _computeHeatmap(deviceId);
    } catch (e) {
      print('DataService: Error generating heatmap: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _computeHeatmap(String deviceId) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(_heatmapIsolate, [receivePort.sendPort, deviceId, _firestore]);
    final result = await receivePort.first as List<Map<String, dynamic>>;
    receivePort.close();
    return result;
  }

  static void _heatmapIsolate(List<dynamic> args) async {
    final SendPort sendPort = args[0];
    final String deviceId = args[1];
    final FirebaseFirestore firestore = args[2];

    try {
      final snapshot = await firestore
          .collection('locations')
          .where('deviceId', isEqualTo: deviceId)
          .get();
      print('DataService: Fetched ${snapshot.docs.length} location records for deviceId: $deviceId');

      Map<String, int> grid = {};
      for (var doc in snapshot.docs) {
        final lat = (doc['latitude'] as double?)?.toStringAsFixed(4);
        final lng = (doc['longitude'] as double?)?.toStringAsFixed(4);
        if (lat != null && lng != null) {
          final key = '$lat,$lng';
          grid[key] = (grid[key] ?? 0) + 1;
        }
      }

      final maxVisits = grid.values.isNotEmpty ? grid.values.reduce((a, b) => a > b ? a : b) : 1;
      final heatmapPoints = grid.entries.map((entry) {
        final parts = entry.key.split(',');
        return {
          'latitude': double.parse(parts[0]),
          'longitude': double.parse(parts[1]),
          'intensity': entry.value / maxVisits,
        };
      }).toList();
      print('DataService: Generated heatmap with ${heatmapPoints.length} points');

      sendPort.send(heatmapPoints);
    } catch (e) {
      print('DataService: Error in heatmap isolate: $e');
      sendPort.send([]);
    }
  }

  void dispose() {
    _locationController.close();
    print('DataService: Disposed');
  }
}