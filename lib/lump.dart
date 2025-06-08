import 'package:lump/contentdb.dart';
import 'package:lump/shared.dart';
import 'package:lump/storage.dart';
import 'package:lump/dependency_resolver.dart';
import 'package:lump/progress.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:toml/toml.dart';
import 'package:logging/logging.dart';

class Lump {
  final LumpConfig config;
  final ContentDbApi _api;
  final LumpStorage _storage;
  final Logger logger;

  final DependencyResolver resolver;

  Lump(this.config)
      : _api = ContentDbApi(config.contentDbUrl),
        _storage = LumpStorage(config),
        resolver = config.resolveDependencies ? Resolver() : DummyResolver(),
        logger = Logger("LumpApp");

  void close() {
    _api.close();
  }

  Future<Package?> choosePackage(PackageName pkg,
      [List<Package>? sourcePkgs,
      bool showTypes = false,
      bool mustIncludeGames = false]) async {
    List<Package> pkgs = [];
    if (sourcePkgs == null || sourcePkgs.isEmpty) {
      try {
        pkgs = await _api.searchPackages(pkg);
      } on MalformedJsonException {
        logger.finer("Failed to look up packages");
      } on FormatException catch (e, s) {
        logger.finer("Failed to look up packages: $e\n$s");
      }
    } else {
      pkgs = sourcePkgs;
    }

    // Handle errors
    if (pkgs.isEmpty) return null;
    // I guess this won't work with "mod in modpack" dependencies
    // Added special parameter ;D
    // We should filter by NAME IS SAME and PROVIDES THAT NAME
    // If we don't want to see games

    pkgs = pkgs
        .where((p) =>
            !((!config.showGamesAsCandidates && p.type == PackageType.game) &&
                (sourcePkgs != null && !mustIncludeGames)))
        .toList();
    pkgs = pkgs
        .where((p) =>
            p.name.toLowerCase() == pkg.name.toLowerCase() ||
            p.provides.contains(PackageName(pkg.name)))
        .toList();

    if (pkgs.isEmpty) return null;
    if (pkgs.singleOrNull != null) return pkgs.single;

    for (final i in pkgs.indexed) {
      final (index, pkg) = i;
      final type = showTypes ? pkgTypeToStr(pkg.type) : "";
      print("[${index + 1}] $pkg $type");
      print("${pkg.type}");
    }
    stdout.write("[1-${pkgs.length}] ");

    String choice = stdin.readLineSync()!; // I hope it doesn't fail
    if (int.tryParse(choice) == null) return null; // Should repeat the choice

    return pkgs[int.parse(choice) - 1];
  }

  Future<Set<PackageName>> resolveDependencies(Set<PackageName> needed) async {
    return resolver.resolve(needed, await _storage.allModnames);
  }

  Future<Package> getPackage(PackageHeader pkg) async {
    return await _api.queryPackage(pkg);
  }

  Future<List<Package>> searchPackages(String query) async {
    return await _api.searchPackages(PackageName(query));
  }

  Future<int> createBackup(String path) async {
    return await _storage.writeBackup(path);
  }

  Future<List<PackageHeader>> readBackup(String path) async {
    return await _storage.readBackup(path);
  }

  // TODO: Add package to modnames after installation
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

  Future<Dependencies> getDependencies(PackageHeader pkg) async {
    return await _api.getDependencies(pkg);
  }

  // This can throw some errors. But which??
  Future<void> _install(Package pkg) async {
    final release = await _api.getRelease(pkg); // this may throw
    final stream = await _api.downloadRelease(release); // this

    int max = stream.contentLength ?? 1;
    int received = 0;
    BytesBuilder bytes = BytesBuilder(copy: false);

    Progress bar = Progress()..enablePulseSlowdown = false;

    // This is interesting...
    Completer completer = Completer();

    print("> ${pkg.asPackageHeader()} (${bytesToReadable(max)})");

    // Stream might throw too
    stream.stream.listen(
      (data) {
        received += data.length;
        bytes.add(data);

        // bar.update(CustomProgressEvent(bytesToReadable(max)));
        bar.update(ProgressUpdateEvent(received, max));
      },
      onDone: () async {
        //final bytes = await stream.stream.toBytes();
        //bar.update(CustomProgressEvent("Unpacking..."));

        // It doesn't block, right?? ;D
        final t = Timer.periodic(Duration(milliseconds: 500),
            (_) => bar.update(PulseProgressEvent("Unpacking...")));

        await _storage.installFromArchive(pkg, bytes.takeBytes());
        t.cancel();

        _storage.updatePackageRelease(pkg);
        // print("\x1B[2K\rDone.");
        bar.update(CompleteProgressEvent());

        completer.complete();
      },
      onError: (e) {
        completer.complete();
        bar.update(FailedProgressEvent());
        logger.severe("Download failed: $e");
      },
      cancelOnError: true,
    );

    await completer.future;
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
    List<Future> tasks = [];
    int i = 0;

    for (final pkg in pkgs) {
      ++i;
      if (i % 2 == 0) {
        await Future.wait(tasks);
        tasks.clear();
      }

      tasks.add(() async {
        final online = await _api.queryPackageBy(pkg);
        if (online.isNewer(pkg)) updates.add(online);
      }());
    }
    await Future.wait(tasks);
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

  Future<List<Package>> findInstalledPackages(String name) async {
    return await _storage.findAllPackages(name);
  }
}

// `modpack.txt` scares me

// WOULD BE MUCH BETER IF I USED PATH.JOIN OR WHATEVER
class LumpConfig {
  late String luantiPath;
  late String contentDbUrl;
  late bool resolveDependencies;
  late bool showGamesAsCandidates;
  late bool useContentDbCandidates;

  static const Map<String, dynamic> sampleConfig = {
    "luanti": {
      "path": "YOUR_PATH_HERE",
      "contentdb": "https://content.luanti.org/api",
    },
    "lump": {
      "resolve_dependencies": true,
      "show_games_as_candidates": false,
      "use_contentdb_candidates": true,
    },
  };

  LumpConfig() {
    readConfig();
  }

  static String getConfigPath() {
    if (!Platform.isLinux) {
      print("Error: unsupported platform (for now?)");
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
    // TODO: Handle broken configs
    luantiPath = conf["luanti"]["path"];
    contentDbUrl = conf["luanti"]["contentdb"];
    resolveDependencies = conf["lump"]["resolve_dependencies"];
    showGamesAsCandidates = conf["lump"]["show_games_as_candidates"];
    useContentDbCandidates = conf["lump"]["use_contentdb_candidates"];
    // Check whether the path is valid

    // final dir = Directory(luantiPath);
  }
}
