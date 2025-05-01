import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:permission_handler/permission_handler.dart';
import '../services/data.dart';

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({Key? key}) : super(key: key);

  @override
  _HeatmapScreenState createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final DataService _dataService = DataService();
  latlng.LatLng? _currentPosition;
  StreamSubscription<latlng.LatLng>? _locationSubscription;
  final MapController _mapController = MapController();
  DateTime? _lastUpdate;
  bool _isUpdating = false;
  bool _showHeatmap = true;
  bool _isTracking = false;
  bool _locationFailed = false;
  List<Map<String, dynamic>> _heatmapPoints = [];

  final String deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
  static const _defaultPosition = latlng.LatLng(9.03, 38.74); 

  @override
  void initState() {
    super.initState();
    print('HeatmapScreen: Starting initialization');
    _initLocation();
    _generateHeatmap();
  }

  Future<void> _initLocation() async {
    print('HeatmapScreen: initLocation called');
    final initialPosition = await _dataService.initLocation(
      onPermissionDenied: _showPermissionDeniedDialog,
      onServiceDisabled: _showServiceDisabledDialog,
    );

    if (!mounted) return;

    if (initialPosition == null) {
      _showUsingFallbackSnackbar();
      setState(() {
        _locationFailed = true;
      });
    } else {
      setState(() {
        _locationFailed = false;
        _isTracking = true;
      });
    }

    setState(() {
      _currentPosition = initialPosition ?? _defaultPosition;
      _lastUpdate = DateTime.now();
    });

    if (initialPosition != null) {
      await _dataService.updateLocation(deviceId, initialPosition);
    }

    _locationSubscription = _dataService.onLocationChanged.listen((position) {
      if (!mounted) return;
      print('HeatmapScreen: Received position: $position');
      setState(() {
        _isUpdating = true;
        _currentPosition = position;
        _lastUpdate = DateTime.now();
        _locationFailed = false;
      });
      _mapController.move(position, _mapController.camera.zoom);
      if (_isTracking) {
        _dataService.updateLocation(deviceId, position);
      }
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _isUpdating = false);
      });
    }, onError: (e) {
      print('HeatmapScreen: Location stream error: $e');
    });
  }

  Future<void> _generateHeatmap() async {
    final points = await _dataService.generateHeatmap(deviceId);
    if (!mounted) return;
    setState(() {
      _heatmapPoints = points;
    });
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Denied'),
        content: const Text('Location permission is required. Please enable in settings.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Settings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showServiceDisabledDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Service Disabled'),
        content: const Text('Please enable location services.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showUsingFallbackSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Using default location due to timeout.')),
    );
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _dataService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _currentPosition == null
              ? const Center(child: CircularProgressIndicator())
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition!,
                    initialZoom: 15.0,
                    minZoom: 3.0,
                    maxZoom: 18.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.heat_map',
                    ),
                    if (_showHeatmap)
                      CircleLayer(
                        circles: _heatmapPoints.map((point) {
                          final intensity = point['intensity'] as double;
                          return CircleMarker(
                            point: latlng.LatLng(point['latitude'], point['longitude']),
                            radius: 20 + intensity * 30,
                            color: Color.lerp(Colors.blue, Colors.red, intensity)!
                                .withOpacity(0.3),
                            borderStrokeWidth: 0,
                          );
                        }).toList(),
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentPosition!,
                          child: const Icon(
                            Icons.location_pin,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          if (_locationFailed)
            Center(
              child: ElevatedButton(
                onPressed: _initLocation,
                child: const Text('Retry Location'),
              ),
            ),
          Positioned(
            bottom: 20,
            left: 20,
            child: ToggleSwitch(
              isActive: _showHeatmap,
              onToggle: (value) {
                setState(() {
                  _showHeatmap = value;
                });
              },
              activeColor: Colors.cyan,
              inactiveColor: Colors.grey,
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              onPressed: () {
                setState(() {
                  _isTracking = !_isTracking;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_isTracking ? 'Tracking started' : 'Tracking stopped'),
                  ),
                );
              },
              backgroundColor: _isTracking ? Colors.grey : Colors.red, // Per April 11, 2025
              child: const Icon(Icons.sos),
            ),
          ),
        ],
      ),
    );
  }
}

class ToggleSwitch extends StatelessWidget {
  final bool isActive;
  final ValueChanged<bool> onToggle;
  final Color activeColor;
  final Color inactiveColor;

  const ToggleSwitch({

    required this.isActive,
    required this.onToggle,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: isActive,
      onChanged: onToggle,
      activeColor: activeColor,
      inactiveTrackColor: inactiveColor,
    );
  }
}