import 'package:lump/src/contentdb.dart';
// import 'package:lump/shared.dart';
// import 'package:lump/lump.dart';
// import 'package:lump/storage.dart';

abstract interface class DependencyResolver {
  // What dependencies do we need to install?
  Set<PackageName> resolve(
      Set<PackageName> dependencies, Set<PackageName> installed);
}

class DummyResolver implements DependencyResolver {
  @override
  Set<PackageName> resolve(
      Set<PackageName> dependencies, Set<PackageName> installed) {
    return <PackageName>{};
  }
}

class Resolver implements DependencyResolver {
  @override
  Set<PackageName> resolve(
      Set<PackageName> dependencies, Set<PackageName> installed) {
    return dependencies.difference(installed);
  }
}
