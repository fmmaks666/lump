import 'package:lump/contentdb.dart';
import 'package:lump/shared.dart';
import 'package:lump/storage.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:toml/toml.dart';

class Lump {
  final LumpConfig _config;
  final ContentDbApi _api;
  final LumpStorage _storage;

  Lump(this._config)
      : _api = ContentDbApi(_config.contentDbUrl),
        _storage = LumpStorage(_config);

  void close() {
    _api.close();
  }

  Future<Package?> choosePackage(PackageName pkg) async {
    final pkgs = await _api.searchPackages(pkg);
    // Handle errors
    if (pkgs.isEmpty) return null;
    if (pkgs.singleOrNull != null) return pkgs.single;

    for (final i in pkgs.indexed) {
      final (index, pkg) = i;
      print("[${index + 1}] $pkg");
      print("${pkg.type}");
    }
    stdout.write("[1-${pkgs.length}] ");

    String choice = stdin.readLineSync()!; // I hope it doesn't fail
    if (int.tryParse(choice) == null) return null; // Should repeat the choice

    return pkgs[int.parse(choice) - 1];
  }

  Future<void> installPackage(PackageHeader pkgDef) async {
    // Check whether the package is installed
    // If not installed, download the archive and extract it
    try {
      final pkg = await _api.queryPackage(pkgDef);
      if (await _storage.isPackageInstalled(pkg)) {
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
      final pkg = await _storage.getPackage(pkgDef.name, pkgDef.author);
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

  // 8s before rewrite
  // 7s after a small improvement
  // 7s after the rewrite ;D, but it is async now!
  // Probably because of I/O D:
  Future<List<Package>> getUpdates() async {
    List<Package> updates = [];

    final [mods, games, textures] = await Future.wait(
        [_storage.mods, _storage.games, _storage.texturePacks]);

    final results = await Future.wait([
      _getUpdatesFor(mods),
      _getUpdatesFor(games),
      _getUpdatesFor(textures)
    ]);

    // I bet there's a better way to do this
    updates.addAll(results.removeLast());
    updates.addAll(results.removeLast());
    updates.addAll(results.removeLast());
    return updates;
  }

  Future<List<Package>> _getUpdatesFor(List<Package> pkgs) async {
    List<Package> updates = [];
    for (final pkg in pkgs) {
      final online = await _api.queryPackageBy(pkg);
      if (online.isNewer(pkg)) updates.add(online);
    }
    return updates;
  }

  Future<void> removePackage(PackageHeader pkgDef) async {
    try {
      final pkg = await _storage.getPackage(pkgDef.name, pkgDef.author);
      print("> $pkgDef");
      print("Removing...");
      _storage.removePackage(pkg);
    } on PackageNotFoundException {
      print("Package $pkgDef is not installed");
    }
  }
}

// `modpack.txt` scares me

// WOULD BE MUCH BETER IF I USED PATH.JOIN OR WHATEVER
class LumpConfig {
  late String luantiPath;
  late String contentDbUrl;

  static const Map<String, dynamic> sampleConfig = {
    "luanti": {
      "path": "YOUR_PATH_HERE",
      "contentdb": "https://content.luanti.org/api",
    }
  };

  LumpConfig() {
    readConfig();
  }

  static String getConfigPath() {
    if (!Platform.isLinux) {
      print("TODO: Support this Platform?");
      exit(1);
    }
    // String? path = Platform.environment["XDG_CONFIG_DIRS"];
    String? path = Platform.environment["HOME"]; // I am sorry.
    if (path == null) throw NoConfigPathException("Failed to find the path");
    return "$path/.lump.toml";
  }

  void readConfig() {
    final path = LumpConfig.getConfigPath();
    final f = File(path);
    if (!f.existsSync()) {
      f.createSync();
      final conf = TomlDocument.fromMap(sampleConfig).toString();
      f.writeAsStringSync(conf);
      throw ConfigNotFoundException("Config doesn't exists");
    }
    final conf = TomlDocument.parse(f.readAsStringSync()).toMap();
    luantiPath = conf["luanti"]["path"];
    contentDbUrl = conf["luanti"]["contentdb"];
    // Check whether the path is valid

    // final dir = Directory(luantiPath);
  }
}
