import 'package:lump/contentdb.dart';

void main(List<String> arguments) async {
  print('Hello isekai!');

  Package mineclonia;
  ContentDbApi api = ContentDbApi();
  mineclonia = await api.queryPackage("mineclonia", "ryvnf");

  print(mineclonia);
}
