class Progress {
  int width = 16;

}

class ProgressUpdate {
  final num max;
  final num value;

  const ProgressUpdate(this.value, this.max);
}
