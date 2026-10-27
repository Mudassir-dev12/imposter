import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';

class CountdownTimerWidget extends StatefulWidget {
  final int? deadlineEpochMs;
  final String label;

  const CountdownTimerWidget({
    super.key,
    required this.deadlineEpochMs,
    this.label = 'Time Remaining',
  });

  @override
  State<CountdownTimerWidget> createState() => _CountdownTimerWidgetState();
}

class _CountdownTimerWidgetState extends State<CountdownTimerWidget> {
  Timer? _timer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _updateRemaining(),
    );
  }

  @override
  void didUpdateWidget(covariant CountdownTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadlineEpochMs != widget.deadlineEpochMs) {
      _updateRemaining();
    }
  }

  void _updateRemaining() {
    if (widget.deadlineEpochMs == null) {
      if (_remainingSeconds != 0 && mounted) {
        setState(() => _remainingSeconds = 0);
      }
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = widget.deadlineEpochMs! - now;
    final sec = diff > 0 ? (diff / 1000).ceil() : 0;

    if (sec != _remainingSeconds && mounted) {
      setState(() => _remainingSeconds = sec);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deadlineEpochMs == null) return const SizedBox.shrink();

    final isUrgent = _remainingSeconds <= 10;
    final color = isUrgent ? AppTheme.impostorColor : AppTheme.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(120), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            '${widget.label}: ${_remainingSeconds}s',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
