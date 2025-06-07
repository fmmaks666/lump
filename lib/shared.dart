import 'dart:io';

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
