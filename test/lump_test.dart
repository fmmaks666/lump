import 'package:lump/contentdb.dart';
import 'package:test/test.dart';
import 'dart:convert' show jsonDecode;

void main() {
  test('package', () {
    Package expected =
        Package("mineclonia", "ryvnf", 30913, PackageType.game, "Mineclonia");
    final json = """
    {
      "author": "ryvnf",
      "name": "mineclonia",
      "title": "Mineclonia",
      "release": 30913,
      "type": "game"
    }
    """;
    Package actual = Package.fromJson(jsonDecode(json));
    expect(actual, expected);
  });
  test("helpers - pkgTypeFromStr", () {
    expect(pkgTypeFromStr("mod"), PackageType.mod);
    expect(pkgTypeFromStr("game"), PackageType.game);
    expect(pkgTypeFromStr("txp"), PackageType.texturePack);
    expect(() => pkgTypeFromStr("texp"), throwsA(isA<Exception>()));
  });
}
