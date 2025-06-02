import 'package:lump/luanti.dart';
import 'package:lump/contentdb.dart';
import 'package:lump/shared.dart';
import 'package:lump/lump.dart';
import 'package:archive/archive.dart';
import 'dart:io';

class LumpStorage {
  // Lazy load these
  List<Package> _mods = [];
  List<Package> _games = [];
  List<Package> _textures = [];

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

  void _fixBrokenFolderName(Package pkg, String folderName) {
    Directory("${_config.luantiPath}/${packageDir(pkg.type)}/$folderName")
        .renameSync(pathTo(pkg));
  }

  // Make this async..
  Future<List<Package>> _getPackagesByType(PackageType type) async {
    List<Package> pkgs = [];
    ConfParser parser = ConfParser();

    String dirPath = "${_config.luantiPath}/${packageDir(type)}";
    Directory dir = Directory(dirPath);
    await for (final f in dir.list()) {
      if (f is! Directory) continue;
      var confFile = File("${f.path}/${packageConf(type)}");
      if (!await confFile.exists() && type != PackageType.mod) continue;
      if (!await confFile.exists()) {
        confFile = File("${f.path}/modpack.conf");
        if (!await confFile.exists()) continue;
      }

      // Observation: games don't have a `name` property, so I will use the parent dir as the `name`
      final conf = parser.parseToMap(await confFile.readAsString());
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
