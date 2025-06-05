import 'package:lump/contentdb.dart';
import 'package:lump/lump.dart';
import 'package:args/command_runner.dart';
import 'dart:io';

class NeededPackages {
  final List<PackageHeader> packages;
  final List<PackageHeader> dependencies;

  NeededPackages(this.packages, this.dependencies);

  static Future<NeededPackages> fromHandles(
      Lump l, Iterable<PackageHandle> packages) async {
    // Man, I will need to do something about re-fetching
    List<PackageHeader> requested = [];
    List<PackageHeader> dependencies = [];
    for (final p in packages) {
      PackageHeader pkg;
      if (p is PackageName) {
        // 1. Get the package
        final chosenPkg = await l.choosePackage(p);
        if (chosenPkg == null) {
          print("Skipping, invalid package $p");
          continue;
        }
        pkg = chosenPkg.asPackageHeader();
      } else {
        pkg = p as PackageHeader;
      }
      requested.add(pkg);

      if (!l.config.resolveDependencies) {
        return NeededPackages(requested, dependencies);
      }

      // 2. Dependencies
      final deps = await l.getDependencies(pkg);
      Set<PackageName> needed = await l.resolveDependencies(deps.required);

      if (needed.isNotEmpty) {
        final depsMsg =
            needed.singleOrNull != null ? "dependency" : "dependencies";
        print("Need ${needed.length} $depsMsg: ${needed.join(" ")}");
      }
      for (final dep in needed) {
        final candidates = deps.candidates[dep.name] ?? [];
        final candidatePkgs = <Package>[];

        if (l.config.useContentDbCandidates) {
          for (final c in candidates) {
            if (c is PackageHeader) {
              candidatePkgs.add(await l.getPackage(c));
            }
            // TODO: Handle errors!
          }
        }

        final chosen = await l.choosePackage(dep, candidatePkgs);
        if (chosen != null) dependencies.add(chosen.asPackageHeader());
      }
    }

    return NeededPackages(requested, dependencies);
  }
}

class LumpRunner extends CommandRunner {
  @override
  String? usageFooter = "Don't forget to eat cookies :)";

  LumpRunner() : super("lump", "Simple package manager for Luanti");
}

CommandRunner initializeCmd(Lump l) {
  final runner = LumpRunner()
    ..addCommand(InstallCommand(l))
    ..addCommand(UpdateCommand(l))
    ..addCommand(RemoveCommand(l))
    ..addCommand(RefreshCommand(l))
    ..addCommand(SearchCommand(l))
    ..addCommand(BackupCommand(l))
    ..addCommand(RestoreCommand(l));

  return runner;
}

class InstallCommand extends Command {
  @override
  final name = "install";
  @override
  String description = "Installs a package";
  @override
  String usage =
      "install (packages) Installs packages specified in Author/Package format";

  final Lump _lump;

  InstallCommand(this._lump) {
    /* Nothing */
  }

  @override
  void run() async {
    if (argResults == null) throw Error();
    if (argResults!.rest.isEmpty) {
      print("Error: No packages to install");
      return;
    }
    final packages = argResults!.rest.map(PackageHandle.fromString);

    List<PackageHeader> allPackages = [];

    final pkgs = await NeededPackages.fromHandles(_lump, packages);

    allPackages.addAll(pkgs.packages);
    allPackages.addAll(pkgs.dependencies);

    String pkgMsg = allPackages.singleOrNull != null ? "package" : "packages";
    print("Installing ${allPackages.length} $pkgMsg");
    print(allPackages.join(" "));

    for (final package in allPackages) {
      await _lump.installPackage(package);
    }
  }
}

class UpdateCommand extends Command {
  @override
  final name = "update";
  @override
  String description = "Updates a package";
  @override
  String usage =
      "update [-a] (packages) Updates packages specified in Author/Package format";

  final Lump _lump;

  UpdateCommand(this._lump) {
    argParser.addFlag("all", abbr: 'a', defaultsTo: false);
  }

  @override
  void run() async {
    if (argResults == null) throw Error();
    if (argResults!.rest.isEmpty && !argResults!.flag("all")) {
      print("Error: No packages to update");
      return;
    }
    Iterable<PackageHandle> packages;
    if (!argResults!.flag("all")) {
      packages = argResults!.rest.map(PackageHandle.fromString);
    } else {
      packages = (await _lump.getUpdates()).map((p) => p.asPackageHeader());
    }

    final pkgs = await NeededPackages.fromHandles(_lump, packages);

    String pkgMsg = pkgs.packages.singleOrNull != null ? "package" : "packages";
    print("Updating ${packages.length} $pkgMsg");
    print(packages.join(" "));

    for (final package in pkgs.packages) {
      await _lump.updatePackage(package);
    }
    for (final dep in pkgs.dependencies) {
      await _lump.installPackage(dep);
    }
  }
}

class RemoveCommand extends Command {
  @override
  final name = "remove";
  @override
  String description = "Uninstalls a package";
  @override
  String usage =
      "remove (packages) Uninstalls packages specified in Author/Package format";

  final Lump _lump;

  RemoveCommand(this._lump) {
    /* Nothing */
  }

  @override
  void run() async {
    if (argResults == null) throw Error();
    if (argResults!.rest.isEmpty) {
      print("Error: No packages to remove");
      return;
    }
    final packages = argResults!.rest.map(PackageHeader.fromString);

    String pkgMsg = packages.singleOrNull != null ? "package" : "packages";
    print("Removing ${packages.length} $pkgMsg");
    // TODO: Request approval
    print(packages.join(" "));

    for (final package in packages) {
      await _lump.removePackage(package);
    }
  }
}

class RefreshCommand extends Command {
  @override
  final name = "refresh";
  @override
  String description = "Lists updates";
  @override
  String usage = "refresh Lists packages which can be updated";

  final Lump _lump;

  RefreshCommand(this._lump) {
    /* Nothing */
  }

  @override
  void run() async {
    print("Refreshing...");

    final pkgs = await _lump.getUpdates();

    String pkgMsg = pkgs.singleOrNull != null ? "package" : "packages";
    print("${pkgs.length} updatable $pkgMsg");

    for (final pkg in pkgs) {
      print("- $pkg");
    }
  }
}

class BackupCommand extends Command {
  @override
  final name = "backup";
  @override
  String description =
      "Save a list of currently installed packages into a text file";
  @override
  String usage =
      "backup [filename] Optional file name, packages.txt by default";

  final Lump _lump;

  BackupCommand(this._lump) {
    /* Nothing */
  }

  @override
  void run() async {
    String path = "packages.txt";
    if (argResults != null && argResults!.rest.isNotEmpty) {
      path = argResults!.rest.first;
    }

    print("Writing to $path...");
    // It would be better to move this into LumpStorage?
    final wrote = await _lump.createBackup(path);
    print("Wrote $wrote lines to $path");
  }
}

class RestoreCommand extends Command {
  @override
  final name = "restore";
  @override
  String description = "Install packages listed in a text file";
  @override
  String usage =
      "restore [filename] Optional file name, packages.txt by default";

  final Lump _lump;

  RestoreCommand(this._lump) {
    /* Nothing */
  }

  @override
  void run() async {
    String path = "packages.txt";
    if (argResults != null && argResults!.rest.isNotEmpty) {
      path = argResults!.rest.first;
    }

    print("Reading $path...");
    // It would be better to move this into LumpStorage?
    final pkgs = await _lump.readBackup(path);
    String pkgMsg = pkgs.length == 1 ? "package" : "packages";
    print("Loaded ${pkgs.length} $pkgMsg from $path");
    print(pkgs.join(" "));

    for (final pkg in pkgs) {
      await _lump.installPackage(pkg);
    }
  }
}

class SearchCommand extends Command {
  @override
  final name = "search";
  @override
  String description = "Find packages";
  @override
  String usage = "restore (query) Searches for packages on ContentDB";

  final Lump _lump;

  SearchCommand(this._lump) {
    /* Nothing */
  }

  @override
  void run() async {
    if (argResults == null) throw Error();
    if (argResults!.rest.isEmpty) {
      print("Error: No query specified");
      return;
    }

    final query = argResults!.rest.join(" ");

    final results = await _lump.searchPackages(query);

    for (final pkg in results) {
      String type = pkgTypeToStr(pkg.type);
      print("${pkg.author}/${pkg.name} $type\n\t${pkg.shortDescription}");
    }
  }
}
