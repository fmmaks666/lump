import 'package:lump/lump.dart';
import 'package:lump/cmd.dart';
import 'package:lump/shared.dart';
import 'package:logging/logging.dart';
import 'package:args/command_runner.dart';

void main(List<String> arguments) async {
  Logger.root.level = Level.FINE;
  Logger.root.onRecord.listen((ev) {
    print("${ev.level} ${ev.time}@${ev.loggerName} :: ${ev.message}");
  });
  final logger = Logger("LumpMain");

  try {
    LumpConfig conf = LumpConfig();
    Lump l = Lump(conf);

    final cmd = initializeCmd(l);

    final verbose = cmd.argParser.parse(arguments).flag("verbose");
    if (verbose) {
      Logger.root.level = Level.ALL;
    }

    await cmd.run(arguments).catchError((e) {
      l.logger.severe("Error: $e");
      if (e is! UsageException) return;
      print("An error occured: ${e.message}");
    });

    l.close();
  } on NoConfigPathException {
    print("FATAL: Can't find Config path");
  } on ConfigNotFoundException {
    print(
        "FATAL: Config not found. Blank config was created at ${LumpConfig.getConfigPath()}");
  } on FormatException catch (e) {
    print("Error: Invalid usage: ${e.message}");
  } catch (e, s) {
    print("An internal error occured");
    logger.shout("$e at\n$s");
  }

  //l.installPackage("rpg16", "Hugues Ross");
  //await l.updatePackage("mineclonia", "ryvnf");
}
