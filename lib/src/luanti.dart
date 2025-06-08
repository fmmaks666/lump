// Hacks for Luanti live here

// Non-necessary but nice to have. A parser for *.conf files in my Luanti packages
// In the context of conf for packages, Luanti only acccess Strings and Ints
// The syntax:
// name = VALUE
// value is anything or an int
// Also there's might be a multiline statements, but that's for later
class ConfParser {
  ConfParser();

  // Map<String, String/int>
  Map<String, Object> parseToMap(String conf) {
    Map<String, Object> results = {};
    final lines = conf.split("\n");
    for (var line in lines) {
      final idx = line.indexOf("=");
      if (idx != -1) {
        final name = line.substring(0, idx).trim();
        Object value = line.substring(idx + 1).trim();
        if ((value as String).isInt()) value = int.parse(value);
        results[name] = value;
      }
    }

    return results;
  }

  String mapToConf(Map<String, Object> data) {
    String buffer = "";
    for (final key in data.entries) {
      buffer += "${key.key} = ${key.value}\n";
    }
    return buffer.trim();
  }
}

extension IsInt on String {
  bool isInt() {
    return int.tryParse(this) != null;
  }
}
