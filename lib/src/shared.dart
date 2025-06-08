import 'dart:io';
import 'dart:math' show pow;

class MalformedJsonException implements Exception {
  MalformedJsonException(String message);
}

class PackageNotFoundException implements Exception {
  PackageNotFoundException(String message);
}

class InvalidPackageException implements Exception {
  InvalidPackageException(String message);
}

class ConfigNotFoundException implements Exception {
  ConfigNotFoundException(String message);
}

class NoConfigPathException implements Exception {
  NoConfigPathException(String message);
}

class InvalidConfigException implements Exception {
  final String message;

  InvalidConfigException(this.message);
}

class InvalidDirectoryException implements Exception {
  InvalidDirectoryException(String message);
}

class ContentDbError implements Exception {
  ContentDbError(String message);
}

bool requestApproval(String message) {
  stdout.write("$message [Y/n] ");
  final answer = stdin.readLineSync();

  if (answer == null) return false;
  if (answer.isEmpty) return true;
  if (answer.toLowerCase() == "yes" || answer.toLowerCase() == "y") return true;
  return false;
}

String bytesToReadable(int bytes) {
  final amount = 1024;

  if (bytes < amount) return "${bytes}B";
  if (bytes < pow(amount, 2)) return "${(bytes / pow(amount, 1)).round()}KB";
  if (bytes < pow(amount, 3)) return "${(bytes / pow(amount, 2)).round()}MB";
  if (bytes > pow(amount, 3)) return "${(bytes / pow(amount, 2)).round()}MB";

  return "0B";
}
