import 'dart:async';
import 'dart:isolate';
import 'dart:math';
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

      var backgroundStatus = await Permission.locationAlways.status;
      if (!backgroundStatus.isGranted) {
        backgroundStatus = await Permission.locationAlways.request();
        print('DataService: Background location permission status: $backgroundStatus');
        if (backgroundStatus.isDenied || backgroundStatus.isPermanentlyDenied) {
          print('DataService: Background location permission denied');
        }
      }

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

      await _location.changeSettings(
        interval: 1000,
        distanceFilter: 5,
        accuracy: LocationAccuracy.high,
      );

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

  Stream<Map<String, dynamic>> getStats(String deviceId) {
    return _firestore
        .collection('locations')
        .where('deviceId', isEqualTo: deviceId)
        .snapshots()
        .asyncMap((snapshot) async {
      try {
        if (!_isFirebaseInitialized) {
          print('DataService: Firebase not initialized, returning empty stats');
          return {};
        }

        final locations = snapshot.docs
            .map((doc) => {
                  'latitude': doc['latitude'] as double?,
                  'longitude': doc['longitude'] as double?,
                  'timestamp': (doc['timestamp'] as Timestamp?)?.toDate(),
                })
            .toList();

        if (locations.isEmpty) {
          return {
            'timeSpent': '0 min',
            'distance': '0.0 km',
            'mostVisited': 'N/A',
            'heatScore': '0',
          };
        }

        // Time Spent

        double totalMinutes = 0;
        for (int i = 1; i < locations.length; i++) {
          final prevTime = locations[i - 1]['timestamp'] as DateTime?;
          final currTime = locations[i]['timestamp'] as DateTime?;
          if (prevTime != null && currTime != null) {
            final diff = currTime.difference(prevTime).inMinutes;
            if (diff <= 60) {
              totalMinutes += diff;
            }
          }
        }
        final hours = (totalMinutes / 60).floor();
        final minutes = (totalMinutes % 60).round();
        final timeSpent = hours > 0 ? '$hours h $minutes min' : '$minutes min';

        // Distance Traveled
        double totalDistance = 0;
        const distance = latlng.Distance();
        for (int i = 1; i < locations.length; i++) {
          final prevLat = locations[i - 1]['latitude'] as double?;
          final prevLng = locations[i - 1]['longitude'] as double?;
          final currLat = locations[i]['latitude'] as double?;
          final currLng = locations[i]['longitude'] as double?;
          if (prevLat != null && prevLng != null && currLat != null && currLng != null) {
            totalDistance += distance(
              latlng.LatLng(prevLat, prevLng),
              latlng.LatLng(currLat, currLng),
            );
          }
        }
        final distanceKm = (totalDistance / 1000).toStringAsFixed(1);

        // Most Visited
        Map<String, int> grid = {};
        for (var loc in locations) {
          final lat = (loc['latitude'] as double?)?.toStringAsFixed(4);
          final lng = (loc['longitude'] as double?)?.toStringAsFixed(4);
          if (lat != null && lng != null) {
            final key = '$lat,$lng';
            grid[key] = (grid[key] ?? 0) + 1;
          }
        }
        final mostVisitedEntry = grid.entries.isNotEmpty
            ? grid.entries.reduce((a, b) => a.value > b.value ? a : b)
            : null;
        final mostVisited = mostVisitedEntry != null
            ? mostVisitedEntry.key 
            : 'N/A';

        // Heat Score
        final heatmapPoints = await _computeHeatmap(deviceId);
        final avgIntensity = heatmapPoints.isNotEmpty
            ? heatmapPoints.map((p) => p['intensity'] as double).reduce((a, b) => a + b) /
                heatmapPoints.length
            : 0.0;
        final heatScore = (avgIntensity * 100).round().toString();

        return {
          'timeSpent': timeSpent,
          'distance': '$distanceKm km',
          'mostVisited': mostVisited,
          'heatScore': heatScore,
        };
      } catch (e) {
        print('DataService: Error computing stats: $e');
        return {};
      }
    });
  }

  void dispose() {
    _locationController.close();
    print('DataService: Disposed');
  }
}