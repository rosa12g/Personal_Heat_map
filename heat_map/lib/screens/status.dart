import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/data.dart';
import '../widgets/stat_card.dart';

class StatsScreen extends StatelessWidget {
  final DataService _dataService = DataService();

StatsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Match deviceId format from HeatmapScreen
    final deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';

    return StreamBuilder<Map<String, dynamic>>(
      stream: _dataService.getStats(deviceId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.cyan));
        }
        if (snapshot.hasError) {
          print('StatsScreen: Error fetching stats: ${snapshot.error}');
          return const Center(
            child: Text('Error loading stats', style: TextStyle(color: Colors.white)),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text('No data available', style: TextStyle(color: Colors.white)),
          );
        }

        final stats = snapshot.data!;
        final timeSpent = stats['timeSpent'] as String;
        final distance = stats['distance'] as String;
        final mostVisited = stats['mostVisited'] as String;
        final heatScore = stats['heatScore'] as String;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatCard(
                  icon: Icons.timer,
                  title: 'Time Spent',
                  value: timeSpent,
                  iconColor: Colors.cyan,
                ),
                const SizedBox(height: 10),
                StatCard(
                  icon: Icons.directions_walk,
                  title: 'Distance Traveled',
                  value: distance,
                  iconColor: Colors.purple,
                ),
                const SizedBox(height: 10),
                StatCard(
                  icon: Icons.home,
                  title: 'Most Visited',
                  value: mostVisited,
                  iconColor: Colors.blue,
                ),
                const SizedBox(height: 10),
                StatCard(
                  icon: Icons.local_fire_department,
                  title: 'Heat Score',
                  value: heatScore,
                  iconColor: Colors.orange,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}