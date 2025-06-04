import 'package:lump/lump.dart';
import 'package:lump/cmd.dart';
import 'package:lump/shared.dart';
import 'package:logging/logging.dart';

void main(List<String> arguments) async {
  try {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((ev) {
      print("${ev.level} ${ev.time}@${ev.loggerName} :: ${ev.message}");
    });

    LumpConfig conf = LumpConfig();
    Lump l = Lump(conf);
    final cmd = initializeCmd(l);
    await cmd.run(arguments);

    l.close();
  } on NoConfigPathException {
    print("FATAL: Can't find Config path");
  } on ConfigNotFoundException {
    print(
        "FATAL: Config not found. Blank config was created at ${LumpConfig.getConfigPath()}");
  }

  //l.installPackage("rpg16", "Hugues Ross");
  //await l.updatePackage("mineclonia", "ryvnf");
}
