import 'dart:convert';
import '../models/song.dart';

class TrackNormalizer {
  /// Unescapes common HTML entities, Unicode escape sequences, percent-encoded
  /// characters, and double-encoded Mojibake from raw strings returned by APIs.
  static String unescapeHtml(String input) {
    if (input.isEmpty) return input;

    var text = input;

    // 1. Fix double-encoded UTF-8 / Mojibake (e.g. Malayalam / Tamil UTF-8 decoded as Latin-1)
    try {
      if (text.contains(RegExp(r'[\u00C0-\u00DF][\u0080-\u00BF]|[\u00E0-\u00EF][\u0080-\u00BF]{2}'))) {
        final bytes = latin1.encode(text);
        final decoded = utf8.decode(bytes, allowMalformed: true);
        if (decoded.isNotEmpty && !decoded.contains('\uFFFD')) {
          text = decoded;
        }
      }
    } catch (_) {}

    // 2. Decode percent-encoded UTF-8 characters (e.g. %E0%B4%95)
    if (text.contains('%')) {
      try {
        text = Uri.decodeComponent(text);
      } catch (_) {}
    }

    // 3. Decode literal slash-u Unicode escapes (e.g. \u0d24 or \u0D15 or \u{0D15})
    if (text.contains(r'\u')) {
      text = text.replaceAllMapped(RegExp(r'\\u\{([0-9a-fA-F]+)\}'), (m) {
        final code = int.tryParse(m[1] ?? '', radix: 16);
        return code != null ? String.fromCharCode(code) : m[0]!;
      });
      text = text.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (m) {
        final code = int.tryParse(m[1] ?? '', radix: 16);
        return code != null ? String.fromCharCode(code) : m[0]!;
      });
    }

    // 4. Decode HTML decimal & hex entities (e.g. &#3374; or &#x0D2E;)
    text = text
        .replaceAllMapped(RegExp(r'&#(\d+);?'), (m) {
          final code = int.tryParse(m[1] ?? '');
          return code != null ? String.fromCharCode(code) : m[0]!;
        })
        .replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);?'), (m) {
          final code = int.tryParse(m[1] ?? '', radix: 16);
          return code != null ? String.fromCharCode(code) : m[0]!;
        });

    // 5. Decode standard named HTML entities
    text = text
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&copy;', '©')
        .replaceAll('&reg;', '®')
        .replaceAll('&trade;', '™')
        .trim();

    return text;
  }

  /// Normalizes a song title to its canonical base representation by stripping
  /// movie tags ("From ..."), version/remix tags, media descriptions, and punctuation.
  static String normalizeTitle(String rawTitle) {
    var title = unescapeHtml(rawTitle).toLowerCase().trim();

    // Remove tags inside parentheses or brackets:
    // e.g. (From "Movie"), [From Movie], (Original Soundtrack), (Remix), (Lyrical), (Official Video)
    const tagKeywords = r'(?:from|ost|soundtrack|feat\.?|featuring|with|remix|remaster(?:ed)?|version|edit|mix|reprise|acoustic|unplugged|live|instrumental|cover|slowed|sped\s*up|lo[- ]?fi|club|extended|radio|lyrical|video|audio|full\s*song|theme|title\s*track|original|film)';

    title = title
        .replaceAll(RegExp('\\([^)0-9a-zA-Z]*$tagKeywords.*?\\)', caseSensitive: false), ' ')
        .replaceAll(RegExp('\\[[^\\]0-9a-zA-Z]*$tagKeywords.*?\\]', caseSensitive: false), ' ')
        .replaceAll(RegExp('\\((?:[^)]*\\b$tagKeywords\\b[^)]*)\\)', caseSensitive: false), ' ')
        .replaceAll(RegExp('\\[(?:[^\\]]*\\b$tagKeywords\\b[^\\]]*)\\]', caseSensitive: false), ' ');

    // Strip trailing parenthetical expressions if the leading core title is already substantial
    final strippedTrailing = title
        .replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '')
        .replaceAll(RegExp(r'\s*\[[^\]]*\]\s*$'), '')
        .trim();
    if (strippedTrailing.length >= 3) {
      title = strippedTrailing;
    }

    // Strip trailing subtitles like " - From Sarvam Maya", " - Soundtrack", " - Lyrical"
    title = title.replaceAll(
      RegExp(r'\s*[-–—|:]\s*(?:from|ost|soundtrack|remix|remaster|version|edit|mix|acoustic|live|instrumental|lyrical|official|video|audio).*$', caseSensitive: false),
      ' ',
    );

    // Remove standalone noise words
    title = title.replaceAll(
      RegExp(r'\b(?:official\s+)?(?:video|audio|lyrical|remix|remastered|remaster|reprise|acoustic|unplugged|instrumental|slowed|sped\s*up|lo[- ]?fi|club\s+mix|extended|radio\s+edit|live\s+version|edit)\b', caseSensitive: false),
      ' ',
    );

    // Remove all punctuation and symbols, normalize whitespace
    title = title.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return title;
  }

  /// Extracts individual normalized artist tokens from a raw artist string.
  static List<String> extractArtistTokens(String rawArtist) {
    final cleaned = unescapeHtml(rawArtist).toLowerCase();
    final parts = cleaned.split(RegExp(r'[,&|/+]|\bfeat\.?\b|\bfeaturing\b|\bwith\b|\band\b', caseSensitive: false));
    final tokens = <String>[];
    for (var part in parts) {
      part = part.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (part.isNotEmpty && part != 'unknown artist' && part != 'unknown') {
        tokens.add(part);
      }
    }
    return tokens;
  }

  /// Extracts primary artist name.
  static String primaryArtist(String rawArtist) {
    final tokens = extractArtistTokens(rawArtist);
    return tokens.isNotEmpty ? tokens.first : '';
  }

  /// Generates a canonical family key used for hash sets and duplicate identification.
  static String trackFamilyKey(Song song) {
    final normTitle = normalizeTitle(song.title);
    final artists = extractArtistTokens(song.artist)..sort();
    final artistKey = artists.isNotEmpty ? artists.join(',') : normalizeTitle(song.artist);
    return '$normTitle|$artistKey';
  }

  /// Determines if two songs represent the same track or alternate releases of the same song.
  static bool isDuplicate(Song a, Song b) {
    if (a.id.isNotEmpty && a.id == b.id) return true;
    final titleA = normalizeTitle(a.title);
    final titleB = normalizeTitle(b.title);
    if (titleA.isEmpty || titleB.isEmpty) return false;
    if (titleA != titleB) return false;

    // Both songs have the exact same normalized core title.
    final artistsA = extractArtistTokens(a.artist);
    final artistsB = extractArtistTokens(b.artist);

    // If either artist list is empty, same title indicates a duplicate
    if (artistsA.isEmpty || artistsB.isEmpty) return true;

    // Check for shared primary or featured artist
    for (final artA in artistsA) {
      for (final artB in artistsB) {
        if (artA == artB || artA.contains(artB) || artB.contains(artA)) {
          return true;
        }
      }
    }

    // If the title is distinctive (longer than 4 characters), treat as same song
    if (titleA.length >= 5) {
      return true;
    }

    return false;
  }
}
