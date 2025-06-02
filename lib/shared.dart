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
