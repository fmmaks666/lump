import 'package:http/http.dart';
import 'dart:convert' show jsonDecode;

class Package {
  final String author;
  final String? _title;
  String get title => _title ?? name;
  final String name;

  final PackageType type;

  int releaseId;

  Package(this.name, this.author, this.releaseId, this.type, [this._title]);

  factory Package.fromJson(Map<String, dynamic> data) {
    if (data
        case {
          "author": String author,
          "name": String name,
          "release": int releaseId,
          "type": "mod" || "txp" || "game",
        }) {
      String? title;
      if (data case {"title": String()}) title = data["title"] as String;

      return Package(name, author, releaseId, pkgTypeFromStr(data["type"]), title);
    }
    throw ArgumentError("Invalid or malformed JSON");
  }

  @override
  String toString() {
    return "$author/$name ($releaseId)";
  }

  @override
  int get hashCode {
    int result = 13;
    result = 23 * result + author.hashCode;
    result = 23 * result + name.hashCode;
    result = 23 * result + title.hashCode;
    result = 23 * result + releaseId.hashCode;
    result = 23 * result + type.hashCode;
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (other is! Package) return false;
    if (other.author != author) return false;
    if (other.name != name) return false;
    if (other.title != title) return false;
    if (other.type != type) return false;
    if (other.releaseId != releaseId) return false;

    return true;
  }
}

enum PackageType {
  mod,
  texturePack,
  game,
}

PackageType pkgTypeFromStr(String type) {
  PackageType t = switch (type) {
    "mod" => PackageType.mod,
    "txp" => PackageType.texturePack,
    "game" => PackageType.game,
    _ => throw Exception("UNEXPECTED")
  };

  return t;
}

class ContentDbApi {
  final Client _client;

  ContentDbApi() : _client = Client();

  Future<Package> queryPackage(String name, String author) async {
    Response r = await _client.get(Uri.parse("https://content.luanti.org/api/packages/$author/$name")); // Make this look better
    String json = r.body;
    return Package.fromJson(jsonDecode(json));
  }
}
