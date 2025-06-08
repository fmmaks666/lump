import 'package:lump/src/contentdb.dart';
import 'package:lump/src/luanti.dart';
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
  test("release", () {});
  test("helpers - pkgTypeFromStr", () {
    expect(pkgTypeFromStr("mod"), PackageType.mod);
    expect(pkgTypeFromStr("game"), PackageType.game);
    expect(pkgTypeFromStr("txp"), PackageType.texturePack);
    expect(() => pkgTypeFromStr("texp"), throwsA(isA<Exception>()));
  });
  test("helpers - ConfParser to map", () {
    final conf = """
      title = Name
      name = mod
      release = 53
    """;
    final expected = <String, Object>{
      "title": "Name",
      "name": "mod",
      "release": 53
    };

    final actual = ConfParser().parseToMap(conf);
    expect(actual, expected);
  });
  test("helpers - ConfParser from map", () {
    final expected = """
title = Name
name = mod
release = 53
    """
        .trim();
    final data = <String, Object>{
      "title": "Name",
      "name": "mod",
      "release": 53
    };

    final actual = ConfParser().mapToConf(data);
    expect(actual, expected);
  });
}
