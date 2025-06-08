import 'package:lump/src/luanti.dart';
import 'package:lump/src/contentdb.dart';
import 'package:lump/src/shared.dart';
import 'package:lump/src/lump.dart';
import 'package:archive/archive.dart';
import 'package:logging/logging.dart';
import 'dart:io';
import 'dart:convert';

// I hope that Luanti doesn't support recursive modpacks
// This should be 2 distinct classes

class LumpStorage {
  // Lazy load these
  List<Package> _mods = [];
  List<Package> _games = [];
  List<Package> _textures = [];

  // Used for dependencies
  final Set<PackageName> modNames = {};

  final Set<String> _brokenMods = {};

  Future<Set<PackageName>> get allModnames async {
    await loadModnames();
    return modNames;
  }

  // String represents a path here
  final Set<String> _modpacks = {}; // Just for convenience

  String get modsPath => "${_config.luantiPath}/mods";
  String get gamesPath => "${_config.luantiPath}/games";
  String get texturesPath => "${_config.luantiPath}/textures";

  Future<List<Package>> get mods async {
    if (_mods.isNotEmpty) return _mods;
    _mods = await _getPackagesByType(PackageType.mod);
    return _mods;
  }

  Future<List<Package>> get games async {
    if (_games.isNotEmpty) return _games;
    _games = await _getPackagesByType(PackageType.game);
    return _games;
  }

  Future<List<Package>> get texturePacks async {
    if (_textures.isNotEmpty) return _textures;
    _textures = await _getPackagesByType(PackageType.texturePack);
    return _textures;
  }

  final LumpConfig _config;

  final ZipDecoder _decoder;

  final Logger _logger = Logger("LumpStorage");

  LumpStorage(this._config) : _decoder = ZipDecoder();

  Future<bool> isPackageInstalled(Package pkg) async {
    return switch (pkg.type) {
          PackageType.mod => (await mods).indexWhere(pkg.sameAs),
          PackageType.game => (await games).indexWhere(pkg.sameAs),
          PackageType.texturePack =>
            (await texturePacks).indexWhere(pkg.sameAs),
        } !=
        -1;
  }

  Future<Package> getPackage(String name, String author,
      [PackageType? type]) async {
    // I will ingore a possible edge cases with type for now
    // The funniest code I have ever written ;D

    try {
      return (await mods).firstWhere(
          (pkg) => pkg.sameAs(Package(name, author, -1, PackageType.mod)));
    } on StateError {
      /* Nothing */
    }
    try {
      return (await games).firstWhere(
          (pkg) => pkg.sameAs(Package(name, author, -1, PackageType.game)));
    } on StateError {
      /* Nothing */
    }
    try {
      return (await texturePacks).firstWhere((pkg) =>
          pkg.sameAs(Package(name, author, -1, PackageType.texturePack)));
    } on StateError {
      /* Nothing */
    }
    throw PackageNotFoundException("Could not find package $author/$name");
  }

  Future<List<Package>> findAllPackages(String name) async {
    List<Package> pkgs = [];

    // These don't throw StateError
    pkgs.addAll((await mods).where((pkg) => pkg.name == name));

    pkgs.addAll((await games).where((pkg) => pkg.name == name));

    pkgs.addAll((await texturePacks).where((pkg) => pkg.name == name));

    if (pkgs.isEmpty) throw PackageNotFoundException("Package wasn't found");
    return pkgs;
  }

  void addModname(Package pkg) => modNames.add(PackageName(pkg.name));

  Future<void> loadModnames() async {
    await mods; // Load all mods, it will add them to modnames + will populate modpacks

    for (final game in await games) {
      final path = pathTo(game);
      final dir = Directory("$path/mods");

      await loadPackagesInDir(dir, PackageType.mod, (pkg, path, isModpack) {
        modNames.add(PackageName(pkg.name));
        if (isModpack) _modpacks.add(path);
      }, (name, path, isModpack) {
        _logger.finest("Added kinda broken mod(pack): $path");
        if (isModpack) {
          _modpacks.add(path);
        } else {
          _brokenMods.add(path);
          modNames.add(PackageName(name));
        }
      });
    }

    // Deal with modpacks, now that we have every modpack
    final numModpacks = _modpacks.length;

    for (final path in _modpacks) {
      final dir = Directory(path);
      await loadModNamesInDir(dir);
    }
    assert(numModpacks == _modpacks.length);
  }

  Future<void> installFromArchive(Package pkg, List<int> bytes) async {
    // I hope this works :D
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

    String destConf = packageConf(pkg.type);

    String path = "${pathTo(pkg)}/$destConf";
    File confFile = File(path);
    if (!confFile.existsSync() && pkg.type != PackageType.mod) {
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
    if (pkg.shortDescription != null) {
      conf["description"] = pkg.shortDescription!;
    }
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

  // FIXED?: lump install caverealms (Shara/caverealms when the other one is installed)
  void _fixBrokenFolderName(Package pkg, String folderName) {
    final newPath = pathTo(pkg);
    final dir = Directory(newPath);
    // A VERY DESTRUCTIVE ACTION!!!!!!!!!!!
    if (dir.existsSync()) {
      _logger.warning("$newPath exists. It will be deleted");
      dir.deleteSync(recursive: true);
    }

    Directory("${_config.luantiPath}/${packageDir(pkg.type)}/$folderName")
        .renameSync(pathTo(pkg));
  }

  Future<List<Package>> _getPackagesByType(PackageType type) async {
    final dirPath = switch (type) {
      PackageType.mod => modsPath,
      PackageType.game => gamesPath,
      PackageType.texturePack => texturesPath,
    };

    Directory dir = Directory(dirPath);
    final pkgs = await loadPackagesInDir(
        dir,
        type,
        (type == PackageType.mod)
            ? (pkg, path, isModpack) {
                modNames.add(PackageName(pkg.name));
                if (isModpack) _modpacks.add(path);
              }
            : null, (name, path, isModpack) {
      _logger.finest(
          "Added kinda broken mod(pack): $path (when loading packages)");
      if (isModpack) {
        _modpacks.add(path);
      } else {
        _brokenMods.add(path);
        modNames.add(PackageName(name));
      }
    });

    if (type == PackageType.mod) {
      _logger.finest("ModNames: $modNames");
      _logger.finest("ModPacks: $_modpacks");
    }

    return pkgs;
  }

  // Mods, or Modpacks
  // Is this really needed?
  Future<List<Package>> loadPackagesInDir(Directory dir, PackageType type,
      [void Function(Package pkg, String path, bool isModpack)? onLoaded,
      void Function(String name, String path, bool isModpack)? onError]) async {
    if (!await dir.exists()) return [];
    List<Package> pkgs = [];

    await _walkDir(dir, (f) async {
      final pkg = await loadSinglePackage(f, type, onLoaded, onError);
      if (pkg != null) {
        pkgs.add(pkg);
      }
    });
    return pkgs;
  }

  Future<void> loadModNamesInDir(Directory dir) async {
    if (!await dir.exists()) return;

    await _walkDir(dir, (f) async {
      final c = File("${f.path}/mod.conf");
      if (!await c.exists()) return;
      final parser = ConfParser();
      final conf = parser.parseToMap(await c.readAsString());

      if (conf case {"name": String name}) {
        modNames.add(PackageName(name));
      }
    });
  }

  Future<void> _walkDir(
      Directory dir, Future<void> Function(Directory f) onEnter) async {
    if (!await dir.exists()) return;
    List<Future> tasks = [];

    try {
      await for (final f in dir.list()) {
        if (f is! Directory) continue;
        final task = onEnter(f);
        tasks.add(task);
      }
      // JUST IN CASE
    } on FileSystemException catch (e) {
      _logger.warning("Error when walking through a dir: $e");
      return;
    }

    await Future.wait(tasks);
  }

  Future<Package?> loadSinglePackage(Directory f, PackageType type,
      [void Function(Package pkg, String path, bool isModpack)? onLoaded,
      void Function(String name, String path, bool isModpack)? onError]) async {
    ConfParser parser = ConfParser();
    bool isModpack = false;

    var confFile =
        File("${f.path}/${packageConf(type)}"); // Try to get the conf file

    if (!await confFile.exists() && type != PackageType.mod) {
      return null; // Skip if it is not a mod and doesn't have a conf file
    }
    if (!await confFile.exists()) {
      // `Mods` may be modpacks, check for that here
      confFile = File("${f.path}/modpack.conf");
      isModpack = true;
      if (!await confFile.exists()) return null;
    }

    // Observation: games don't have a `name` property, so I will use the parent dir as the `name`
    final conf = parser.parseToMap(await confFile.readAsString());

    String name = confFile.parent.path
        .substring(confFile.parent.path.lastIndexOf("/") + 1);
    //print(conf);
    try {
      //print(confFile.parent);

      final pkg = Package.fromJson({
        ...conf,
        "type": contentDbPkgType(type),
        if (type == PackageType.game)
          "name": name // Hopefully it doesn't add a slash at the end
      });

      if (onLoaded != null) onLoaded(pkg, f.path, isModpack);

      return pkg;
    } on MalformedJsonException {
      if (onError != null) onError(name, f.path, isModpack);
      _logger.finest("Broken package at ${confFile.path}");
    }
    return null;
  }

  Future<List<PackageHeader>> readBackup(String path) async {
    final f = File(path);
    final reader = f.openRead();
    final lines = reader.transform(Utf8Decoder()).transform(LineSplitter());

    List<PackageHeader> pkgs = [];
    await for (final line in lines) {
      try {
        pkgs.add(PackageHeader.fromString(line));
      } on FormatException {
        continue;
      }
    }

    return pkgs;
  }

  Future<int> writeBackup(String path) async {
    int i = 0;

    final [m, g, t] = await Future.wait([mods, games, texturePacks]);

    final f = File(path);
    final sink = f.openWrite(mode: FileMode.append);

    //await mods; // Yep, it crashes

    // sink.done.catchError((e) => print(e));

    // These fellas don't throw erros :D
    // I guess I have found an edge case in Dart?
    // If I use I/O (which happens in mods)
    // It makes sink throw the error silently
    // But it actually crashes the app
    // A workaround is to do the I/O before opening the Sink
    // I will explore this error later
    for (final p in m) {
      // Never `await mods` here -- it breaks Dart?
      sink.writeln("${p.author}/${p.name}");
      ++i;
    }
    for (final p in g) {
      sink.writeln("${p.author}/${p.name}");
      ++i;
    }
    for (final p in t) {
      sink.writeln("${p.author}/${p.name}");
      ++i;
    }

    // IT MUST BE CLOSED
    try {
      await sink.flush();
      await sink.close();
    } on FileSystemException catch (e) {
      _logger.finer("Failed to close the sink: $e");
      rethrow;
    }
    return i;
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
