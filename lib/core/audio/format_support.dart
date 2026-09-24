/// File extensions media_kit (libmpv/FFmpeg) plays natively on both
/// Linux and Android. Video containers are included because v1 only
/// extracts their audio track — video rendering is never attached.
const Set<String> supportedAudioExtensions = {
  'mp3',
  'aac',
  'm4a',
  'flac',
  'wav',
  'ogg',
  'opus',
  'wma',
  'ape',
};

const Set<String> supportedVideoContainerExtensions = {
  'mp4',
  'mkv',
  'webm',
  'mov',
  'avi',
};

const Set<String> allSupportedExtensions = {
  ...supportedAudioExtensions,
  ...supportedVideoContainerExtensions,
};

bool isSupportedMediaFile(String filePath) {
  final dot = filePath.lastIndexOf('.');
  if (dot == -1 || dot == filePath.length - 1) return false;
  final ext = filePath.substring(dot + 1).toLowerCase();
  return allSupportedExtensions.contains(ext);
}

bool isVideoContainer(String filePath) {
  final dot = filePath.lastIndexOf('.');
  if (dot == -1 || dot == filePath.length - 1) return false;
  final ext = filePath.substring(dot + 1).toLowerCase();
  return supportedVideoContainerExtensions.contains(ext);
}
