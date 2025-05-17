import 'package:lump/contentdb.dart';
import 'package:lump/lump.dart';


void main(List<String> arguments) async {
  print('Hello isekai!');

  //mineclonia = await api.queryPackage("mineclonia", "ryvnf");
  LumpConfig conf = LumpConfig("/home/fmmaks/.minetest"); // Just a test
  Lump l = Lump(conf);

  //l.installPackage("rpg16", "Hugues Ross");
  await l.updatePackage("mineclonia", "ryvnf");
}
