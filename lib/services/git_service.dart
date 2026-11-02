import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:archive/archive_io.dart';

class GitService {
  /// Imports a GitHub repository using its branch archive.
  /// Note: This is a simplified clone for Phase B.
  static Future<void> cloneRepository({
    required String repoUrl,
    required String localPath,
    String? accessToken,
    String? branch,
    void Function(String)? onProgress,
  }) async {
    try {
      final uri = Uri.parse(repoUrl);
      if (uri.scheme != 'https' || uri.host != 'github.com') {
        throw Exception('Only github.com URLs are supported currently.');
      }

      final segments = uri.pathSegments;
      if (segments.length < 2) {
        throw Exception('Invalid GitHub URL format.');
      }

      final owner = segments[0];
      final repo = segments[1].replaceAll('.git', '');

      onProgress?.call('Fetching repository info...');

      // Get default branch
      final apiUri = Uri.parse('https://api.github.com/repos/$owner/$repo');
      final headers = <String, String>{
        'Accept': 'application/vnd.github+json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };
      final apiRes = await http
          .get(apiUri, headers: headers)
          .timeout(const Duration(seconds: 30));

      if (apiRes.statusCode != 200) {
        throw Exception(
          'Failed to fetch repository. Check your GitHub access.',
        );
      }

      final repoData = jsonDecode(apiRes.body);
      final defaultBranch =
          (branch != null && branch.isNotEmpty)
              ? branch
              : repoData['default_branch'] ?? 'main';

      onProgress?.call('Downloading $defaultBranch branch...');

      // Download zip archive
      final zipUrl =
          'https://api.github.com/repos/$owner/$repo/zipball/${Uri.encodeComponent(defaultBranch as String)}';
      final zipRes = await http
          .get(Uri.parse(zipUrl), headers: headers)
          .timeout(const Duration(minutes: 2));

      if (zipRes.statusCode != 200) {
        throw Exception('Failed to download repository archive.');
      }

      onProgress?.call('Extracting files...');

      final bytes = zipRes.bodyBytes;
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        // GitHub zip archives always wrap all files in a single root folder (e.g. 'repo-branch/').
        // Strip the first folder segment to extract directly into localPath:
        final slashIndex = filename.indexOf('/');
        final relativePath =
            slashIndex != -1 ? filename.substring(slashIndex + 1) : filename;

        if (relativePath.isEmpty) continue;

        final root = p.normalize(p.absolute(localPath));
        final outPath = p.normalize(p.join(root, relativePath));
        if (!p.isWithin(root, outPath) || file.isSymbolicLink) {
          throw Exception('Unsafe repository archive entry.');
        }

        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(outPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }

      onProgress?.call('Clone complete.');
    } catch (e) {
      throw Exception('Git Clone Error: $e');
    }
  }
}
