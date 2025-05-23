import 'package:http/http.dart';
import 'package:lump/shared.dart';
import 'dart:typed_data';
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
          // "release": int releaseId,
          "type": "mod" || "txp" || "game",
        }) {
      String? title;
      if (data case {"title": String t}) title = t;

      // This may have some funny issues
      int releaseId = -1;
      if (data case {"release": int release}) releaseId = release;
      return Package(
          name, author, releaseId, pkgTypeFromStr(data["type"]), title);
    }
    throw MalformedJsonException("Invalid or malformed JSON");
  }

  bool sameAs(Package other) {
    if (other.author != author) return false;
    if (other.name != name) return false;
    if (other.type != type) return false;
    return true;
  }

  bool isNewer(Package other) {
    return releaseId > other.releaseId;
  }

  PackageHeader asPackageHeader() => PackageHeader(name, author);

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

class PackageHeader {
  final String name;
  final String author;

  const PackageHeader(this.name, this.author);
  factory PackageHeader.fromString(String str) {
    if (str.endsWith("/")) str = str.substring(0, str.length - 1);

    final parts = str.split("/");
    if (parts.length > 2) throw Exception("Invalid package");

    final [author, name] = parts;
    return PackageHeader(name, author);
  }

  @override
  int get hashCode {
    int result = 13;
    result = 23 * result + author.hashCode;
    result = 23 * result + name.hashCode;
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (other is! PackageHeader) return false;
    if (other.author != author) return false;
    if (other.name != name) return false;

    return true;
  }

  @override
  String toString() {
    return '$author/$name';
  }
}

class Release {
  final String name;
  final String? _title;
  String get title => _title ?? name;
  final String url;
  // final int size;

  int releaseId;

  Release(this.url, this.name, this.releaseId, [this._title]);

  factory Release.fromJson(Map<String, dynamic> data) {
    if (data
        case {
          "url": String url,
          "name": String name,
          "id": int releaseId,
        }) {
      String? title;
      if (data case {"title": String()}) title = data["title"] as String;

      // [url] already has a /
      return Release("https://content.luanti.org$url", name, releaseId, title);
    }
    throw MalformedJsonException("Invalid or malformed JSON");
  }
  @override
  String toString() {
    return "$name ($releaseId)";
  }

  @override
  int get hashCode {
    int result = 13;
    result = 23 * result + name.hashCode;
    result = 23 * result + title.hashCode;
    result = 23 * result + releaseId.hashCode;
    result = 23 * result + url.hashCode;
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (other is! Release) return false;
    if (other.name != name) return false;
    if (other.title != title) return false;
    if (other.url != url) return false;
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
  // TODO: Close the client
  final Client _client;

  ContentDbApi() : _client = Client();

  Future<Package> queryPackage(PackageHeader pkg) async {
    // Handle error
    Response r = await _client.get(Uri.parse(
        "https://content.luanti.org/api/packages/${pkg.author}/${pkg.name}")); // Make this look better
    String json = r.body;
    return Package.fromJson(jsonDecode(json));
  }

  Future<Package> queryPackageBy(Package pkg) async {
    return await queryPackage(pkg.asPackageHeader());
  }

  Future<Release> getRelease(Package pkg) async {
    Response r = await _client.get(Uri.parse(
        "https://content.luanti.org/api/packages/${pkg.author}/${pkg.name}/releases/${pkg.releaseId}"));
    String json = r.body;
    return Release.fromJson(jsonDecode(json));
  }

  Future<StreamedResponse> downloadRelease(Release release) async {
    StreamedResponse r =
        await _client.send(Request("GET", Uri.parse(release.url)));
    return r;
  }
}
