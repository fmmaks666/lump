import 'package:lump/contentdb.dart';
import 'package:archive/archive.dart';

class Lump {
  final LumpConfig _config;
  final ContentDbApi _api;
  final LumpStorage _storage;

  Lump(this._config)
      : _api = ContentDbApi(),
        _storage = LumpStorage(_config);

  Future<void> installPackage(String name, String author) async {
    // Check whether the package is installed
    // If not installed, download the archive and extract it
    final pkg = await _api.queryPackage(name, author);
    if (_storage.isPackageInstalled(pkg)) {
      // Handle this
      return;
    }

    print(pkg);
    final release = await _api.getRelease(pkg);
    print(release);
    print(release.url);
    final stream =
        await _api.downloadRelease(release); // Here add a progress bar
    final bytes = await stream.stream.toBytes();
    _storage.installFromArchive(pkg, bytes);
  }
}

class LumpStorage {
  // Lazy load these
  List<Package> mods = [];
  List<Package> games = [];
  List<Package> texturePacks = [];

  LumpConfig _config;

  ZipDecoder _decoder;

  LumpStorage(this._config) : _decoder = ZipDecoder();

  bool isPackageInstalled(Package pkg) {
    return switch (pkg.type) {
          PackageType.mod => mods.indexWhere(pkg.sameAs),
          PackageType.game => games.indexWhere(pkg.sameAs),
          PackageType.texturePack => texturePacks.indexWhere(pkg.sameAs),
        } !=
        -1;
  }

  void installFromArchive(Package pkg, List<int> bytes) {
    // TODO: Chech whether all the directories exist
    final archive = _decoder.decodeBytes(bytes);

  }

  void _extractArchive(Archive a, String dest) {
    // Lump will replace files
  }
}

class LumpConfig {
  String luantiPath;

  LumpConfig(this.luantiPath);
}
