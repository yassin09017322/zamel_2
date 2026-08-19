import 'package:flutter/material.dart';

class PendingIndicator extends StatefulWidget {
  final double size;
  final Color? color;

  const PendingIndicator({Key? key, this.size = 14.0, this.color}) : super(key: key);

  @override
  State<PendingIndicator> createState() => _PendingIndicatorState();
}

class _PendingIndicatorState extends State<PendingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.color ?? (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54);
    return SizedBox(
      width: widget.size + 4,
      height: widget.size + 4,
      child: Center(
        child: RotationTransition(
          turns: _controller,
          child: Icon(
            Icons.access_time,
            size: widget.size,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}
