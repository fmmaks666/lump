import 'package:lump/lump.dart';
import 'package:lump/cmd.dart';


void main(List<String> arguments) async {
  LumpConfig conf = LumpConfig("/home/fmmaks/.minetest"); // Just a test
  Lump l = Lump(conf);

  final cmd = initializeCmd(l);
  cmd.run(arguments);
  //l.installPackage("rpg16", "Hugues Ross");
  //await l.updatePackage("mineclonia", "ryvnf");
}
