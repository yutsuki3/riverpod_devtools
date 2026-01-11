import '../static_dependencies.dart';

/// Source location information for code elements
class SourceLocation {
  /// File path (relative to package root)
  final String file;

  /// Line number (1-based)
  final int line;

  /// Column number (1-based)
  final int column;

  const SourceLocation({
    required this.file,
    required this.line,
    required this.column,
  });

  Map<String, dynamic> toJson() => {
        'file': file,
        'line': line,
        'column': column,
      };

  factory SourceLocation.fromJson(Map<String, dynamic> json) =>
      SourceLocation(
        file: json['file'] as String,
        line: json['line'] as int,
        column: json['column'] as int,
      );

  @override
  String toString() => '$file:$line:$column';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceLocation &&
          runtimeType == other.runtimeType &&
          file == other.file &&
          line == other.line &&
          column == other.column;

  @override
  int get hashCode => file.hashCode ^ line.hashCode ^ column.hashCode;
}

/// Information about a dependency extracted during AST analysis
class DependencyInfo {
  /// Name of the provider being depended upon
  final String providerName;

  /// Type of dependency (watch/read/listen)
  final DependencyType type;

  /// Source location where the dependency is declared
  final SourceLocation location;

  const DependencyInfo({
    required this.providerName,
    required this.type,
    required this.location,
  });

  Map<String, dynamic> toJson() => {
        'providerName': providerName,
        'type': type.name,
        'location': location.toJson(),
      };

  factory DependencyInfo.fromJson(Map<String, dynamic> json) => DependencyInfo(
        providerName: json['providerName'] as String,
        type: DependencyType.values.firstWhere(
          (e) => e.name == json['type'],
        ),
        location: SourceLocation.fromJson(
          json['location'] as Map<String, dynamic>,
        ),
      );

  /// Convert to StaticDependency for registration
  StaticDependency toStaticDependency() {
    return StaticDependency(
      providerName: providerName,
      type: type,
      file: location.file,
      line: location.line,
      column: location.column,
    );
  }

  @override
  String toString() =>
      'DependencyInfo($providerName, ${type.name}, ${location.toString()})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DependencyInfo &&
          runtimeType == other.runtimeType &&
          providerName == other.providerName &&
          type == other.type &&
          location == other.location;

  @override
  int get hashCode => providerName.hashCode ^ type.hashCode ^ location.hashCode;
}

/// Metadata about a provider extracted during AST analysis
class ProviderMetadata {
  /// Name of the provider
  final String name;

  /// Type of provider (e.g., "Provider", "StateProvider", "NotifierProvider")
  final String providerType;

  /// List of dependencies this provider has
  final List<DependencyInfo> dependencies;

  /// Source location where the provider is declared
  final SourceLocation location;

  const ProviderMetadata({
    required this.name,
    required this.providerType,
    required this.dependencies,
    required this.location,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'providerType': providerType,
        'dependencies': dependencies.map((d) => d.toJson()).toList(),
        'location': location.toJson(),
      };

  factory ProviderMetadata.fromJson(Map<String, dynamic> json) =>
      ProviderMetadata(
        name: json['name'] as String,
        providerType: json['providerType'] as String,
        dependencies: (json['dependencies'] as List<dynamic>)
            .map((d) => DependencyInfo.fromJson(d as Map<String, dynamic>))
            .toList(),
        location: SourceLocation.fromJson(
          json['location'] as Map<String, dynamic>,
        ),
      );

  /// Convert to StaticProviderMetadata for registration
  StaticProviderMetadata toStaticProviderMetadata() {
    return StaticProviderMetadata(
      name: name,
      dependencies: dependencies.map((d) => d.toStaticDependency()).toList(),
    );
  }

  @override
  String toString() =>
      'ProviderMetadata($name, $providerType, ${dependencies.length} dependencies, $location)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderMetadata &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          providerType == other.providerType &&
          _listEquals(dependencies, other.dependencies) &&
          location == other.location;

  @override
  int get hashCode =>
      name.hashCode ^
      providerType.hashCode ^
      dependencies.hashCode ^
      location.hashCode;

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
