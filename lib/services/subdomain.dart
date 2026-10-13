import 'dart:io';
import 'dart:math';

final baseDomain = (Platform.environment['BASE_DOMAIN'] ?? 'buildiify.tech').trim().toLowerCase();
final reservedSubdomains = {
  'www',
  'api',
  'app',
  'admin',
  'dashboard',
  'mail',
  'ftp',
  'ns1',
  'ns2',
  ...?Platform.environment['RESERVED_SUBDOMAINS']?.split(',').map((s) => s.trim().toLowerCase()),
};

String? validateSubdomain(String name) {
  if (!RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(name)) {
    return 'Use 1–63 lowercase letters, numbers or hyphens; start and end with a letter or number.';
  }
  if (reservedSubdomains.contains(name)) return 'This subdomain is reserved.';
  return null;
}

String projectSubdomain(String name) {
  var stem = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
  stem = stem.replaceAll(RegExp(r'^-+|-+$'), '');
  if (stem.isEmpty) stem = 'project';
  if (stem.length > 54) stem = stem.substring(0, 54);
  stem = stem.replaceAll(RegExp(r'-+$'), '');
  return '$stem-${Random.secure().nextInt(0x1000000).toRadixString(16).padLeft(6, '0')}';
}

String projectNameSubdomain(String name) {
  var slug = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
  slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) slug = 'project';
  if (slug.length > 63) slug = slug.substring(0, 63);
  return slug.replaceAll(RegExp(r'-+$'), '');
}
