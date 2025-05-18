class MalformedJsonException implements Exception {
  MalformedJsonException(String message);
}

class PackageNotFoundException implements Exception {
  PackageNotFoundException(String message);
}

class InvalidPackageException implements Exception {
  InvalidPackageException(String message);
}
