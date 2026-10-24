import 'package:flutter/material.dart';

class BuildifyLogo extends StatelessWidget {
  const BuildifyLogo({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/icon.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
