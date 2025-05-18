import 'package:lump/contentdb.dart';
import 'package:lump/luanti.dart';
import 'package:lump/shared.dart';
import 'package:archive/archive.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

class Lump {
  final LumpConfig _config;
  final ContentDbApi _api;
  final LumpStorage _storage;

  Lump(this._config)
      : _api = ContentDbApi(),
        _storage = LumpStorage(_config);

  Future<void> installPackage(PackageHeader pkgDef) async {
    // Check whether the package is installed
    // If not installed, download the archive and extract it
    try {
      final pkg = await _api.queryPackage(pkgDef);
      if (_storage.isPackageInstalled(pkg)) {
        // Handle this
        print("${pkgDef.author}/${pkgDef.name} is already installed");
        return;
      }

      await _install(pkg);
      // TEMPORARY
    } on MalformedJsonException {
      print("Couldn't install $pkgDef");
    }
  }

  Future<void> _install(Package pkg) async {
    final release = await _api.getRelease(pkg);
    final stream =
        await _api.downloadRelease(release); // Here add a progress bar

    int max = stream.contentLength ?? 1;
    int received = 0;
    BytesBuilder bytes = BytesBuilder(copy: false);
    // This is interesting...
    Completer completer = Completer();

    print("> ${pkg.asPackageHeader()}");

    stream.stream.listen((data) {
      received += data.length;
      stdout.write('\x1B[2K\r');
      int percent = ((received / max) * 100).round();
      final bars = "=" * (0.2 * percent).round();
      final empty = " " * (0.2 * (100 - percent)).round();
      String bar = "[$bars$empty]-[$percent%]";

      stdout.write(bar);
      bytes.add(data);
    }, onDone: () async {
      //final bytes = await stream.stream.toBytes();
      stdout.write("\x1B[2K\rUnpacking...");
      await _storage.installFromArchive(pkg, bytes.takeBytes());
      _storage.updatePackageRelease(pkg);
      print("\x1B[2K\rDone.");
      completer.complete();
    });

    await completer.future;
  }

  Future<void> updatePackage(PackageHeader pkgDef, [PackageType? type]) async {
    try {
      final pkg = _storage.getPackage(pkgDef.name, pkgDef.author);
      final newPkg = await _api.queryPackageBy(pkg);

      if (newPkg.isNewer(pkg)) {
        print("$pkg -> $newPkg");
        await _install(newPkg);
      } else {
        print("No updates for $pkgDef");
      }
    } on PackageNotFoundException {
      print("Package $pkgDef is not installed");
    }
  }

  Future<List<Package>> getUpdates() async {
    List<Package> updates = [];
    for (final pkg in _storage.mods) {
      final online = await _api.queryPackageBy(pkg);
      if (online.isNewer(pkg)) updates.add(online);
    }
    for (final pkg in _storage.games) {
      final online = await _api.queryPackageBy(pkg);
      if (online.isNewer(pkg)) updates.add(online);
    }
    for (final pkg in _storage.texturePacks) {
      final online = await _api.queryPackageBy(pkg);
      if (online.isNewer(pkg)) updates.add(online);
    }

    return updates;
  }

  void removePackage(PackageHeader pkgDef) {
    try {
      final pkg = _storage.getPackage(pkgDef.name, pkgDef.author);
      print("> $pkgDef");
      print("Removing...");
      _storage.removePackage(pkg);
    } on PackageNotFoundException {
      print("Package $pkgDef is not installed");
    }
  }
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
      return mods.firstWhere(
          (pkg) => pkg.sameAs(Package(name, author, -1, PackageType.mod)));
    } on StateError {
      /* Nothing */
    }
    try {
      return games.firstWhere(
          (pkg) => pkg.sameAs(Package(name, author, -1, PackageType.game)));
    } on StateError {
      /* Nothing */
    }
    try {
      return texturePacks.firstWhere((pkg) =>
          pkg.sameAs(Package(name, author, -1, PackageType.texturePack)));
    } on StateError {
      /* Nothing */
    }
    throw PackageNotFoundException("Could not find package $author/$name");
  }

  Future<void> installFromArchive(Package pkg, List<int> bytes) async {
    // TODO: Chech whether all the directories exist
    final archive = _decoder.decodeBytes(bytes);

    String destFolder = packageDir(pkg.type);

    Uri dest = Uri.file("${_config.luantiPath}/$destFolder");
    String? prefix = await _extractArchive(pkg, archive, dest);
    // The first element "should be" the parent folder
    String folderName;
    final parent = archive.first;
    if (!parent.isDirectory && prefix == null) {
      folderName = Uri.parse(parent.name).pathSegments[0];
    } else if (prefix != null) {
      folderName = prefix;
    } else {
      folderName = parent.name.substring(0, parent.name.length - 1);
    }
    if (pkg.name != folderName) {
      _fixBrokenFolderName(pkg, folderName); // Because there's a /
    }
  }

  void removePackage(Package pkg) {
    // In the future I might create `LocalPackage` that will have the path to the package
    String path = pathTo(pkg);
    Directory(path).deleteSync(recursive: true);
  }

  void updatePackageRelease(Package pkg) {
    // Get the conf
    // Parse it
    // Rewrite it
    // Save it

    // TODO: Errors!
    String destConf = packageConf(pkg.type);

    String path = "${pathTo(pkg)}/$destConf";
    File confFile = File(path);
    if (!confFile.existsSync() && pkg.type == PackageType.mod) {
      confFile = File("${pathTo(pkg)}/modpack.conf");
    }

    // Maybe, we should create the modconf?
    // Yep, that's what Luanti does
    if (!confFile.existsSync()) {
      // Directory(path).deleteSync(recursive: true);
      // throw BrokenPackageException("Package is very broken or not installed!");
      confFile.createSync();
    }

    final conf = ConfParser().parseToMap(confFile.readAsStringSync());
    conf["release"] = pkg.releaseId;
    // if (!conf.containsKey("author")) conf["author"] = pkg.author;
    // Clemstriangular/realism_512 has a terrifying texture_pack.conf
    // Such cases will probably make lump work not 100% as luanti
    conf["author"] = pkg.author;
    conf["name"] = pkg.name;
    final newConf = ConfParser().mapToConf(conf);
    confFile.writeAsStringSync(newConf, flush: true);
  }

  // Returns a String if a prefix was needed
  Future<String?> _extractArchive(Package pkg, Archive a, Uri dest) async {
    // Lump will replace files
    // WHY IN THE WORLD WOULD YOU CALL THE FOLDER IN ARCHIVE DIFFERENTLY
    // Edge-case: the package doesn't have a root folder
    String file = "";
    // Because of weird problems this will need to check whether the files have a common directory
    // If not, a prefix will be prepended
    var prefix = "";
    var dirPrefix = Uri.parse(a.first.name).pathSegments[0];
    if (!a.files.every((f) => f.name.startsWith(dirPrefix))) {
      prefix = pkg.name;
    }

    // This worked flawlessly yesterday
    for (final f in a) {
      file = f.name;
      if (f.isDirectory) {
        Directory("${dest.toFilePath()}/$file").createSync();
      } else if (f.isFile) {
        final unpacked = File("${dest.toFilePath()}/$prefix/$file");
        await unpacked.create(recursive: true);
        await unpacked
            .writeAsBytes(f.readBytes()?.toList() ?? []); // Potentially slow?
      }
    }
    return prefix.isNotEmpty ? prefix : null;
  }

  void _fixBrokenFolderName(Package pkg, String folderName) {
    Directory("${_config.luantiPath}/${packageDir(pkg.type)}/$folderName")
        .renameSync(pathTo(pkg));
  }

  List<Package> _getPackagesByType(PackageType type) {
    List<Package> pkgs = [];
    ConfParser parser = ConfParser();

    String dirPath = "${_config.luantiPath}/${packageDir(type)}";
    Directory dir = Directory(dirPath);
    for (final f in dir.listSync()) {
      if (f is! Directory) continue;
      var confFile = File("${f.path}/${packageConf(type)}");
      if (!confFile.existsSync() && type != PackageType.mod) continue;
      if (!confFile.existsSync()) {
        confFile = File("${f.path}/modpack.conf");
        if (!confFile.existsSync()) continue;
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

  String pathTo(Package pkg) {
    return "${_config.luantiPath}/${packageDir(pkg.type)}/${pkg.name}";
  }
}

class LumpConfig {
  String luantiPath;

  LumpConfig(this.luantiPath);
}
