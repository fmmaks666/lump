import 'package:http/http.dart';
import 'package:lump/shared.dart';
import 'dart:typed_data';
import 'dart:convert' show jsonDecode;

class Package {
  final String author;
  final String? _title;
  String get title => _title ?? name;
  final String name;

  // Man, my code is a mess...
  final String? shortDescription;

  final PackageType type;

  int releaseId;

  Set<PackageName> provides;

  Package(this.name, this.author, this.releaseId, this.type,
      [this.shortDescription, this._title])
      : provides = {};

  factory Package.fromJson(Map<String, dynamic> data) {
    final Set<PackageName> provides = {};
    if (data
        case {
          "author": String author,
          "name": String name,
          // "release": int releaseId,
          "type": "mod" || "txp" || "game",
        }) {
      String? title;
      String? shortDesc;
      if (data case {"title": String t}) title = t;
      if (data case {"short_description": String d}) shortDesc = d;
      if (data case {"provides": List provided}) {
        for (final entry in provided) {
          if (entry is String) provides.add(PackageName(entry));
        }
      }

      // This may have some funny issues
      int releaseId = -1;
      if (data case {"release": int release}) releaseId = release;
      return Package(name, author, releaseId, pkgTypeFromStr(data["type"]),
          shortDesc, title)
        ..provides = provides; // Keep eyes on this :D
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

sealed class PackageHandle {
  final String name;

  const PackageHandle(this.name);

  factory PackageHandle.fromString(String str) {
    // If it has a `/` it is a PackageHeader
    if (str.endsWith("/")) str = str.substring(0, str.length - 1);

    if (str.contains("/")) {
      return PackageHeader.fromString(str);
    }
    return PackageName(str);
  }

  @override
  int get hashCode {
    int result = 13;
    result = 23 * result + name.hashCode;
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (other is! PackageHandle) return false;
    if (other.name != name) return false;

    return true;
  }
}

class PackageName extends PackageHandle {
  const PackageName(super.name);

  @override
  String toString() {
    return "?/$name";
  }
}

class PackageHeader extends PackageHandle {
  final String author;

  const PackageHeader(super.name, this.author);
  factory PackageHeader.fromString(String str) {
    if (str.endsWith("/")) str = str.substring(0, str.length - 1);

    final parts = str.split("/");
    if (parts.length > 2) throw Exception("Invalid package");

    final [author, name] = parts;
    return PackageHeader(name, author);
  }

  @override
  int get hashCode {
    int result = super.hashCode;
    result = 23 * result + name.hashCode;
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (super != other) return false;
    if (other is! PackageHeader) return false;
    if (other.author != author) return false;

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

class Dependencies {
  final Set<PackageName> required;
  final Set<PackageName> optional;

  final Map<String, List<PackageHandle>> candidates;

  Dependencies(this.required, this.optional, this.candidates);

  factory Dependencies.fromJson(List<dynamic> data) {
    Set<PackageName> req = {};
    Set<PackageName> opt = {};
    Map<String, List<PackageHandle>> candidates = {};

    //[ { is_optinal: false, name: mod }, ... ]

    for (final entry in data) {
      if (entry
          case {
            "is_optional": bool isOptional,
            "name": String name,
            "packages": List packages
          }) {
        final pkg = PackageName(name);
        if (isOptional) {
          opt.add(pkg);
        } else {
          req.add(pkg);
        }

        List<PackageHandle> deps = [];
        for (final entry in packages) {
          if (entry is! String) continue;
          deps.add(PackageHandle.fromString(entry));
        }
        candidates[name] = deps;
        // TODO: Handle errors
      }
    }
    return Dependencies(req, opt, candidates);
  }
}

enum PackageType {
  mod,
  texturePack,
  game,
}

String pkgTypeToStr(PackageType type) => switch (type) {
      PackageType.mod => "Mod",
      PackageType.game => "Game",
      PackageType.texturePack => "Texture Pack"
    };

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
  final String _url;

  ContentDbApi(this._url) : _client = Client();

  void close() {
    _client.close();
  }

  Future<Package> queryPackage(PackageHeader pkg) async {
    // Handle error
    Response r = await _client.get(Uri.parse(
        "$_url/packages/${pkg.author}/${pkg.name}")); // Make this look better
    String json = r.body;
    return Package.fromJson(jsonDecode(json));
  }

  Future<Package> queryPackageBy(Package pkg) async {
    return await queryPackage(pkg.asPackageHeader());
  }

  Future<List<Package>> searchPackages(PackageHandle pkg) async {
    final name = pkg.name;

    Response r = await _client.get(Uri.parse("$_url/packages/?q=$name"));

    String json = r.body;
    final results = jsonDecode(json);
    List<Package> pkgs = [];
    if (results is! List) return [];
    for (final result in results) {
      pkgs.add(Package.fromJson(result));
      // Handle errors
    }
    return pkgs;
  }

  Future<Dependencies> getDependencies(PackageHeader pkg) async {
    Response r = await _client.get(
        Uri.parse("$_url/packages/${pkg.author}/${pkg.name}/dependencies"));
    String json = r.body;
    return Dependencies.fromJson(jsonDecode(json)["${pkg.author}/${pkg.name}"]);
  }

  Future<Release> getRelease(Package pkg) async {
    Response r = await _client.get(Uri.parse(
        "$_url/packages/${pkg.author}/${pkg.name}/releases/${pkg.releaseId}"));
    String json = r.body;
    return Release.fromJson(jsonDecode(json));
  }

  Future<StreamedResponse> downloadRelease(Release release) async {
    StreamedResponse r =
        await _client.send(Request("GET", Uri.parse(release.url)));
    return r;
  }
}
