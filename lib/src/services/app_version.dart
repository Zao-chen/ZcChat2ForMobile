bool isVersionNewer(String candidate, String current) {
  final _ParsedVersion? candidateVersion = _ParsedVersion.tryParse(candidate);
  final _ParsedVersion? currentVersion = _ParsedVersion.tryParse(current);
  if (candidateVersion == null || currentVersion == null) {
    return false;
  }
  return candidateVersion.compareTo(currentVersion) > 0;
}

class _ParsedVersion implements Comparable<_ParsedVersion> {
  const _ParsedVersion(this.core, this.preRelease);

  final List<int> core;
  final List<String> preRelease;

  static _ParsedVersion? tryParse(String value) {
    String normalized = value.trim().toLowerCase();
    if (normalized.startsWith('v')) {
      normalized = normalized.substring(1);
    }
    normalized = normalized.split('+').first;
    if (normalized.isEmpty) {
      return null;
    }

    final int preReleaseSeparator = normalized.indexOf('-');
    final String coreText = preReleaseSeparator < 0
        ? normalized
        : normalized.substring(0, preReleaseSeparator);
    final String preReleaseText = preReleaseSeparator < 0
        ? ''
        : normalized.substring(preReleaseSeparator + 1);
    final List<String> coreParts = coreText.split('.');
    if (coreParts.isEmpty ||
        coreParts.any((String part) => !RegExp(r'^\d+$').hasMatch(part))) {
      return null;
    }

    final List<String> preRelease = preReleaseText.isEmpty
        ? const <String>[]
        : preReleaseText.split('.');
    if (preRelease.any((String part) => part.isEmpty)) {
      return null;
    }
    return _ParsedVersion(
      coreParts.map(int.parse).toList(growable: false),
      preRelease,
    );
  }

  @override
  int compareTo(_ParsedVersion other) {
    final int coreLength = core.length > other.core.length
        ? core.length
        : other.core.length;
    for (int index = 0; index < coreLength; index += 1) {
      final int left = index < core.length ? core[index] : 0;
      final int right = index < other.core.length ? other.core[index] : 0;
      final int comparison = left.compareTo(right);
      if (comparison != 0) {
        return comparison;
      }
    }

    if (preRelease.isEmpty || other.preRelease.isEmpty) {
      if (preRelease.isEmpty && other.preRelease.isEmpty) {
        return 0;
      }
      return preRelease.isEmpty ? 1 : -1;
    }

    final int preReleaseLength = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (int index = 0; index < preReleaseLength; index += 1) {
      final String left = preRelease[index];
      final String right = other.preRelease[index];
      final int? leftNumber = int.tryParse(left);
      final int? rightNumber = int.tryParse(right);
      final int comparison;
      if (leftNumber != null && rightNumber != null) {
        comparison = leftNumber.compareTo(rightNumber);
      } else if (leftNumber != null) {
        comparison = -1;
      } else if (rightNumber != null) {
        comparison = 1;
      } else {
        comparison = left.compareTo(right);
      }
      if (comparison != 0) {
        return comparison;
      }
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }
}
