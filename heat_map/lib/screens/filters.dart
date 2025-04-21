import 'package:flutter/material.dart';
import '../widgets/filter.dart';

class FiltersScreen extends StatefulWidget {
  const FiltersScreen({Key? key}) : super(key: key);

  @override
  _FiltersScreenState createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  String _selectedFilter = 'This Week';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterOption(
            label: 'Today',
            isSelected: _selectedFilter == 'Today',
            onTap: () {
              setState(() {
                _selectedFilter = 'Today';
              });
            },
          ),
          const SizedBox(height: 10),
          FilterOption(
            label: 'This Week',
            isSelected: _selectedFilter == 'This Week',
            onTap: () {
              setState(() {
                _selectedFilter = 'This Week';
              });
            },
          ),
          const SizedBox(height: 10),
          FilterOption(
            label: 'All Time',
            isSelected: _selectedFilter == 'All Time',
            onTap: () {
              setState(() {
                _selectedFilter = 'All Time';
              });
            },
          ),
        ],
      ),
    );
  }
}