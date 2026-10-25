#ifndef RUNNER_MEDIA_CONTROLS_H_
#define RUNNER_MEDIA_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

// Windows' media controls (System Media Transport Controls): media keys and
// the media flyout show and control the playing song. Dart sends what's
// playing over the "com.musicplayer.music_player/media_controls" channel
// (lib/core/platform/windows_media_controls.dart); button presses go back
// the same way.
class MediaControls {
 public:
  MediaControls(flutter::BinaryMessenger* messenger, HWND window);
  ~MediaControls();

  MediaControls(const MediaControls&) = delete;
  MediaControls& operator=(const MediaControls&) = delete;

  // Windows raises button events on a background thread; they're posted to
  // the window as messages so Dart is only ever called on the main thread.
  // Returns true when [message] was one of those.
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  struct State;
  std::unique_ptr<State> state_;
};

#endif  // RUNNER_MEDIA_CONTROLS_H_
