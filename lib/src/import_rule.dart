import 'package:glob/glob.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Represents an import directive in a Dart file.
@immutable
class Import {
  const Import({required this.uri});

  final String uri;

  @override
  String toString() {
    return uri;
  }
}

/// Represents a single target pattern that can match against file paths.
///
/// Supports both glob patterns and regular expressions with named capture groups.
/// If the pattern contains regex syntax (e.g., (?<name>...)), it will be treated as a regex.
@immutable
class TargetPattern {
  const TargetPattern({required this.pattern});

  final String pattern;

  /// Checks if the pattern is a regular expression (contains named capture groups).
  bool get isRegex => pattern.contains(RegExp(r'\(\?<\w+>'));

  /// Checks if the given file path matches this target pattern.
  bool matches(String file) {
    if (isRegex) {
      // Convert glob-style wildcards to regex before matching
      final regexPattern = _convertGlobWildcardsToRegex(pattern);
      final regex = RegExp(regexPattern);
      return regex.hasMatch(file);
    } else {
      final glob = Glob(pattern);
      return glob.matches(file);
    }
  }

  /// Converts glob-style wildcards (**, *) to regex equivalents.
  /// Preserves regex named capture groups.
  static String _convertGlobWildcardsToRegex(String pattern) {
    var result = pattern;

    // Replace ** with .* (match any characters including /)
    // But preserve (?<name>...) capture groups
    result = result.replaceAllMapped(
      RegExp(r'(?<!\(\?<\w+>)\*\*(?!\))'),
      (match) => '.*',
    );

    // Replace single * with [^/]* (match any characters except /)
    // But avoid replacing * inside capture groups or after we've already replaced **
    result = result.replaceAllMapped(
      RegExp(r'(?<!\(\?<\w+>)(?<!\.)(?<!\.\*)\*(?!\))(?!\*)'),
      (match) => r'[^/]*',
    );

    return result;
  }

  /// Extracts named capture groups from the file path if this is a regex pattern.
  /// Returns a map of group names to their captured values.
  Map<String, String> extractGroups(String file) {
    if (!isRegex) return {};

    final regexPattern = _convertGlobWildcardsToRegex(pattern);
    final regex = RegExp(regexPattern);
    final match = regex.firstMatch(file);

    if (match == null) return {};

    final groups = <String, String>{};
    for (final groupName in match.groupNames) {
      final value = match.namedGroup(groupName);
      if (value != null) {
        groups[groupName] = value;
      }
    }

    return groups;
  }

  @override
  String toString() => pattern;
}

/// Represents a single disallow pattern that can match against import URIs.
@immutable
class DisallowPattern {
  const DisallowPattern({required this.pattern, String? originalPattern})
    : originalPattern = originalPattern ?? pattern;

  /// The normalized pattern used for matching (e.g., "lib/main.dart").
  final String pattern;

  /// The original pattern from the configuration file (for debugging/logging).
  /// May be different from [pattern] if normalization was applied.
  /// For example: "package:my_pkg/main.dart" → normalized to "lib/main.dart"
  final String originalPattern;

  /// Checks if the given import URI matches this disallow pattern.
  ///
  /// The [dirValue] parameter is used to substitute $TARGET_DIR placeholders in the pattern.
  /// The [capturedGroups] parameter contains named capture groups from the target pattern.
  bool matches(
    String importUri,
    String dirValue, {
    Map<String, String>? capturedGroups,
  }) {
    var substitutedPattern = pattern.replaceAll(r'$TARGET_DIR', dirValue);

    // Replace captured group variables (e.g., $feature, $group_name)
    if (capturedGroups != null) {
      for (final entry in capturedGroups.entries) {
        substitutedPattern = substitutedPattern.replaceAll(
          '\$${entry.key}',
          entry.value,
        );
      }
    }

    final glob = Glob(substitutedPattern);
    return glob.matches(importUri);
  }

  @override
  String toString() => pattern;
}

/// Represents an import rule that controls which files can import which files.
class ImportRule {
  /// Required reason explaining why this rule exists.
  final String reason;

  /// Target patterns to which this rule applies.
  final List<TargetPattern> targetPatterns;

  /// Target patterns to exclude from targets.
  final List<TargetPattern> excludeTargetPatterns;

  /// Disallow patterns that files matching targets cannot import.
  final List<DisallowPattern> disallowPatterns;

  /// Disallow patterns to exclude from disallows (making them importable).
  final List<DisallowPattern> excludeDisallowPatterns;

  ImportRule({
    required this.reason,
    required this.targetPatterns,
    this.excludeTargetPatterns = const [],
    required this.disallowPatterns,
    this.excludeDisallowPatterns = const [],
  });

  /// Checks if a target file can import an importee file according to this rule.
  ///
  /// Returns `true` if the import is allowed, `false` if it's denied.
  ///
  /// The evaluation follows this logic:
  /// 1. If targetFile doesn't match any target pattern, the rule doesn't apply (return true)
  /// 2. If targetFile matches any excludeTarget pattern, the rule doesn't apply (return true)
  /// 3. Extract $TARGET_DIR from targetFile's parent directory and capture groups from regex patterns
  /// 4. If importeeFile doesn't match any disallow pattern, the import is allowed (return true)
  /// 5. If importeeFile matches any excludeDisallow pattern (with variables substituted), the import is allowed (return true)
  /// 6. Otherwise, the import is denied (return false)
  bool canImport(String targetFile, Import importee) {
    // Step 1: Check if targetFile matches any target pattern
    final matchingTarget = targetPatterns.firstWhere(
      (target) => target.matches(targetFile),
      orElse: () => const TargetPattern(pattern: ''),
    );

    if (matchingTarget.pattern.isEmpty) {
      return true; // Rule doesn't apply
    }

    // Step 2: Check if targetFile matches any excludeTarget pattern
    if (excludeTargetPatterns.any((target) => target.matches(targetFile))) {
      return true; // Rule doesn't apply
    }

    // Step 3: Extract variables
    final dir = _extractDir(targetFile);
    final capturedGroups = matchingTarget.extractGroups(targetFile);

    // Step 4: Check if importeeFile matches any disallow pattern
    if (!disallowPatterns.any(
      (disallow) =>
          disallow.matches(importee.uri, dir, capturedGroups: capturedGroups),
    )) {
      return true; // Import is allowed (not in disallow list)
    }

    // Step 5: Check if importeeFile matches any excludeDisallow pattern (with all variables substituted)
    if (excludeDisallowPatterns.any(
      (disallow) =>
          disallow.matches(importee.uri, dir, capturedGroups: capturedGroups),
    )) {
      return true; // Import is allowed (in exclude list)
    }

    // Step 6: Import is denied
    return false;
  }
}

/// Extracts the parent directory from a file path.
///
/// For example:
/// - "lib/features/auth/src/utils.dart" -> "lib/features/auth/src"
/// - "lib/main.dart" -> "lib"
/// - "package:flutter/material.dart" -> "package:flutter"
String _extractDir(String filePath) {
  // Handle package imports differently
  if (filePath.startsWith('package:')) {
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash == -1) {
      return filePath; // No directory component
    }
    return filePath.substring(0, lastSlash);
  }

  // For file paths, use the path package
  return p.dirname(filePath);
}

// Parser functions moved to parser.dart (part of this library).
