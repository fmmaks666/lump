import 'package:lump/contentdb.dart';
import 'package:lump/luanti.dart';
import 'package:lump/shared.dart';
import 'package:archive/archive.dart';
import 'dart:io';

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
      print("$author/$name is already installed");
      return;
    }

    print(pkg);
    await _install(pkg);
  }

  Future<void> _install(Package pkg) async {
    final release = await _api.getRelease(pkg);
    print(release);
    print(release.url);
    final stream =
        await _api.downloadRelease(release); // Here add a progress bar
    final bytes = await stream.stream.toBytes();
    _storage.installFromArchive(pkg, bytes);
    _storage.updatePackageRelease(pkg);
  }

  Future<void> updatePackage(String name, String author,
      [PackageType? type]) async {

        final pkg = _storage.getPackage(name, author);
        print("Offline package: $pkg");
        final newPkg = await _api.queryPackageBy(pkg);
        print("Online package: $newPkg");

        if (newPkg.isNewer(pkg)) {
          print("The package is updatable");
          _install(newPkg);
        }
      }

  Future<void> updateAll([PackageType? specificType]) async {  }
}

// `modpack.txt` scares me

class LumpStorage {
  // Lazy load these
  List<Package> _mods = [];
  List<Package> _games = [];
  List<Package> _textures = [];

  List<Package> get mods {
    if (_mods.isNotEmpty) return _mods;
    _mods = _getPackagesByType(PackageType.mod);
    return _mods;
  }

  List<Package> get games {
    if (_games.isNotEmpty) return _games;
    _games = _getPackagesByType(PackageType.game);
    return _games;
  }

  List<Package> get texturePacks {
    if (_textures.isNotEmpty) return _textures;
    _textures = _getPackagesByType(PackageType.texturePack);
    return _textures;
  }

  final LumpConfig _config;

  final ZipDecoder _decoder;

  LumpStorage(this._config) : _decoder = ZipDecoder();

  bool isPackageInstalled(Package pkg) {
    return switch (pkg.type) {
          PackageType.mod => mods.indexWhere(pkg.sameAs),
          PackageType.game => games.indexWhere(pkg.sameAs),
          PackageType.texturePack => texturePacks.indexWhere(pkg.sameAs),
        } !=
        -1;
  }

  Package getPackage(String name, String author, [PackageType? type]) {
    // I will ingore a possible edge cases with type for now
    // The funniest code I have ever written ;D

    try {
      return mods.firstWhere((pkg) => pkg.sameAs(Package(name, author, -1, PackageType.mod)));
    } on StateError {
      /* Nothing */
    }
    try {
      return games.firstWhere((pkg) => pkg.sameAs(Package(name, author, -1, PackageType.game)));
    } on StateError {
      /* Nothing */
    }
    try {
      return texturePacks.firstWhere((pkg) => pkg.sameAs(Package(name, author, -1, PackageType.texturePack)));
    } on StateError {
      /* Nothing */
    }
    throw PackageNotFoundException("Could not find package $author/$name");
  }

  void installFromArchive(Package pkg, List<int> bytes) {
    // TODO: Chech whether all the directories exist
    final archive = _decoder.decodeBytes(bytes);
    String destFolder = packageDir(pkg.type);

    Uri dest = Uri.file("${_config.luantiPath}/$destFolder");
    _extractArchive(archive, dest);
  }

  void updatePackageRelease(Package pkg) {
    // Get the conf
    // Parse it
    // Rewrite it
    // Save it
    // I repeated myself D:
    String destFolder = packageDir(pkg.type);
    // Handle modpacks later
    String destConf = packageConf(pkg.type);

    String path = "${_config.luantiPath}/$destFolder/${pkg.name}/$destConf";
    File confFile = File(path);
    final conf = ConfParser().parseToMap(confFile.readAsStringSync());
    conf["release"] = pkg.releaseId;
    if (!conf.containsKey("author")) conf["author"] = pkg.author;
    final newConf = ConfParser().mapToConf(conf);
    confFile.writeAsStringSync(newConf, flush: true);
  }

  void _extractArchive(Archive a, Uri dest) {
    // Lump will replace files
    String file = "";

    for (var f in a) {
      file = f.name;
      if (f.isDirectory) {
        Directory("${dest.toFilePath()}/$file").createSync();
      } else if (f.isFile) {
        File("${dest.toFilePath()}/$file")
          ..createSync()
          ..writeAsBytesSync(
              f.readBytes()?.toList() ?? []); // Potentially slow?
      }
    }
  }

  List<Package> _getPackagesByType(PackageType type) {
    List<Package> pkgs = [];
    ConfParser parser = ConfParser();

    String dirPath = "${_config.luantiPath}/${packageDir(type)}";
    Directory dir = Directory(dirPath);
    for (final f in dir.listSync()) {
      if (f is! Directory) continue;
      final confFile = File("${f.path}/${packageConf(type)}");
      if (!confFile.existsSync() && type != PackageType.mod) continue;
      if (!confFile.existsSync()) {
        /* modpacks */ continue;
      }

      // Observation: games don't have a `name` property, so I will use the parent dir as the `name`
      final conf = parser.parseToMap(confFile.readAsStringSync());
      //print(conf);
      try {
        //print(confFile.parent);
        final pkg = Package.fromJson({
          ...conf,
          "type": contentDbPkgType(type),
          if (type == PackageType.game)
            "name": confFile.parent.path.substring(
                confFile.parent.path.lastIndexOf("/") +
                    1) // Hopefully it doesn't add a slash at the end
        });
        pkgs.add(pkg);
        //print(pkg);
      } on MalformedJsonException {
        print("Broken package at ${confFile.path}");
        continue;
      }
    }

    return pkgs;
  }

  String packageDir(PackageType type) {
    return switch (type) {
      PackageType.mod => "mods",
      PackageType.game => "games",
      PackageType.texturePack => "textures",
    };
  }

  /// Doesn't handle modpacks
  String packageConf(PackageType type) {
    return switch (type) {
      PackageType.mod => "mod.conf",
      PackageType.game => "game.conf",
      PackageType.texturePack => "texture_pack.conf",
    };
  }

  String contentDbPkgType(PackageType type) {
    return switch (type) {
      PackageType.mod => "mod",
      PackageType.game => "game",
      PackageType.texturePack => "txp",
    };
  }
}

class LumpConfig {
  String luantiPath;

  LumpConfig(this.luantiPath);
}
