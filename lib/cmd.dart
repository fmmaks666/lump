import 'package:lump/contentdb.dart';
import 'package:lump/lump.dart';
import 'package:args/command_runner.dart';

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
    ..addCommand(RefreshCommand(l));

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

    String pkgMsg = packages.length == 1 ? "package" : "packages";
    print("Installing ${packages.length} $pkgMsg");
    print(packages.join(" "));

    for (final package in packages) {
      if (package is PackageHeader) {
        await _lump.installPackage(package);
      } else {
        final chosenPkg = await _lump.choosePackage(package as PackageName);
        if (chosenPkg == null) {
          print("Skipping, invalid package $package");
          continue;
        }
        await _lump.installPackage(chosenPkg.asPackageHeader());
      }
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

    String pkgMsg = packages.length == 1 ? "package" : "packages";
    print("Updating ${packages.length} $pkgMsg");
    print(packages.join(" "));

    for (final package in packages) {
      if (package is PackageHeader) {
        await _lump.updatePackage(package);
      } else {
        final chosenPkg = await _lump.choosePackage(package as PackageName);
        if (chosenPkg == null) {
          print("Skipping, invalid package $package");
          continue;
        }
        await _lump.updatePackage(chosenPkg.asPackageHeader());
      }
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

    String pkgMsg = packages.length == 1 ? "package" : "packages";
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

    String pkgMsg = pkgs.length == 1 ? "package" : "packages";
    print("${pkgs.length} updatable $pkgMsg");

    for (final pkg in pkgs) {
      print("- $pkg");
    }
  }
}
