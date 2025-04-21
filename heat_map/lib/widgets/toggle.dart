import 'package:flutter/material.dart';

class ToggleSwitch extends StatelessWidget {
  final bool isActive;
  final Function(bool) onToggle;
  final Color activeColor;
  final Color inactiveColor;

  const ToggleSwitch({
    Key? key,
    required this.isActive,
    required this.onToggle,
    required this.activeColor,
    required this.inactiveColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'heatmap',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => onToggle(!isActive),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 50,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: isActive ? activeColor : inactiveColor,
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  left: isActive ? 20 : 0,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}