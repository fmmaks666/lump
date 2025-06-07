import 'dart:io';

class Progress {
  int width = 20;

  // What if it is empty :D?
  List<String> animation = ["-", "\\", "|", "/"];
  int _frameIndex = 0;
  int _pulseCounter = 0;
  bool enablePulseSlowdown = true;

  double get normalizedWidth => width / 100;

  String _bar = "Uninitialized.";
  String get bar => _bar;

  ProgressEvent _current = CustomProgressEvent("Uninitialized.");

  void consumeEvent(ProgressEvent ev) {
    _current = ev;

    int pulseInc = 1;
    if (enablePulseSlowdown) {
      pulseInc = ((_pulseCounter++ % animation.length * 3) == 0) ? 1 : 0;
    }
    _frameIndex = (_frameIndex + pulseInc + animation.length) % animation.length;

    _bar = switch (_current) {
      ProgressUpdateEvent(value: final value, max: final max) =>
        _generateBar(value, max),
      PulseProgressEvent(message: var msg) => "${animation[_frameIndex]} $msg",
      CompleteProgressEvent() => "Done.",
      FailedProgressEvent() => "Failed.",
      CustomProgressEvent(message: final msg) => msg,
    };
  }

  void render() {
    stdout.write('\x1B[2K\r');
    stdout.write(_bar);

    if (_current is CompleteProgressEvent || _current is FailedProgressEvent) {
      stdout.writeln();
    }
  }

  void update(ProgressEvent ev) {
    consumeEvent(ev);
    render();
  }

  String _generateBar(int value, int max) {
    int percent = ((value / max) * 100).round();
    final bars = "=" * (normalizedWidth * percent).round();
    final empty = " " * (normalizedWidth * (100 - percent)).round();
    String bar = "[$bars$empty]-[$percent%]";

    return bar;
  }
}

sealed class ProgressEvent {
  const ProgressEvent();
}

class ProgressUpdateEvent extends ProgressEvent {
  final int max;
  final int value;

  const ProgressUpdateEvent(this.value, this.max);
}

class FailedProgressEvent extends ProgressEvent {
  const FailedProgressEvent();
}

class CustomProgressEvent extends ProgressEvent {
  final String message;

  const CustomProgressEvent(this.message);
}

class PulseProgressEvent extends CustomProgressEvent {
  const PulseProgressEvent([super.message = ""]);
}

class CompleteProgressEvent extends ProgressEvent {
  const CompleteProgressEvent();
}
