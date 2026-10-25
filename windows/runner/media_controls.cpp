#include "media_controls.h"

// <unknwn.h> before the C++/WinRT headers turns on their classic COM
// support, needed for ISystemMediaTransportControlsInterop.
#include <unknwn.h>

#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Storage.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <string>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Foundation::AsyncStatus;
using winrt::Windows::Foundation::IAsyncOperation;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::PlaybackPositionChangeRequestedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties;
using winrt::Windows::Storage::StorageFile;
using winrt::Windows::Storage::Streams::RandomAccessStreamReference;

constexpr UINT kButtonMessage = WM_APP + 0x51;
constexpr UINT kSeekMessage = WM_APP + 0x52;

std::wstring Wide(const std::string& utf8) {
  if (utf8.empty()) return {};
  const int size = static_cast<int>(utf8.size());
  const int length =
      MultiByteToWideChar(CP_UTF8, 0, utf8.data(), size, nullptr, 0);
  std::wstring wide(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), size, wide.data(), length);
  return wide;
}

const EncodableValue* Field(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::string StringField(const EncodableMap& map, const char* key) {
  const EncodableValue* value = Field(map, key);
  const auto* text = value ? std::get_if<std::string>(value) : nullptr;
  return text ? *text : std::string();
}

bool BoolField(const EncodableMap& map, const char* key) {
  const EncodableValue* value = Field(map, key);
  const auto* flag = value ? std::get_if<bool>(value) : nullptr;
  return flag && *flag;
}

// The standard codec sends small ints as int32 and big ones as int64.
int64_t IntField(const EncodableMap& map, const char* key) {
  const EncodableValue* value = Field(map, key);
  if (!value) return 0;
  if (const auto* as_int32 = std::get_if<int32_t>(value)) return *as_int32;
  if (const auto* as_int64 = std::get_if<int64_t>(value)) return *as_int64;
  return 0;
}

const char* ButtonName(SystemMediaTransportControlsButton button) {
  switch (button) {
    case SystemMediaTransportControlsButton::Play:
      return "play";
    case SystemMediaTransportControlsButton::Pause:
      return "pause";
    case SystemMediaTransportControlsButton::Stop:
      return "stop";
    case SystemMediaTransportControlsButton::Next:
      return "next";
    case SystemMediaTransportControlsButton::Previous:
      return "previous";
    default:
      return nullptr;
  }
}

}  // namespace

struct MediaControls::State {
  HWND window = nullptr;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  SystemMediaTransportControls smtc{nullptr};
  winrt::event_token button_token{};
  winrt::event_token seek_token{};
  std::wstring art_path;
  // Bumped on every cover change, so a slow cover load that finishes after
  // the next song started doesn't overwrite that song's cover.
  std::shared_ptr<std::atomic<uint64_t>> art_generation =
      std::make_shared<std::atomic<uint64_t>>(0);

  void Apply(const EncodableMap& update);
};

void MediaControls::State::Apply(const EncodableMap& update) {
  auto updater = smtc.DisplayUpdater();
  if (!BoolField(update, "hasTrack")) {
    smtc.PlaybackStatus(MediaPlaybackStatus::Stopped);
    smtc.IsEnabled(false);
    art_path.clear();
    ++*art_generation;
    updater.ClearAll();
    updater.Update();
    return;
  }

  smtc.IsEnabled(true);
  smtc.IsPlayEnabled(true);
  smtc.IsPauseEnabled(true);
  smtc.IsStopEnabled(true);
  smtc.IsNextEnabled(BoolField(update, "canNext"));
  smtc.IsPreviousEnabled(BoolField(update, "canPrevious"));
  smtc.PlaybackStatus(BoolField(update, "playing")
                          ? MediaPlaybackStatus::Playing
                          : MediaPlaybackStatus::Paused);

  updater.Type(MediaPlaybackType::Music);
  auto music = updater.MusicProperties();
  music.Title(winrt::hstring(Wide(StringField(update, "title"))));
  music.Artist(winrt::hstring(Wide(StringField(update, "artist"))));
  music.AlbumTitle(winrt::hstring(Wide(StringField(update, "album"))));

  const std::wstring art = Wide(StringField(update, "artPath"));
  if (art != art_path) {
    art_path = art;
    const uint64_t generation = ++*art_generation;
    updater.Thumbnail(nullptr);
    if (!art.empty()) {
      // Loaded in the background: blocking on it here would freeze the UI
      // thread (and C++/WinRT forbids blocking waits on it).
      auto latest = art_generation;
      StorageFile::GetFileFromPathAsync(art).Completed(
          [latest, generation, updater](
              const IAsyncOperation<StorageFile>& load, AsyncStatus status) {
            if (status != AsyncStatus::Completed || *latest != generation) {
              return;
            }
            try {
              updater.Thumbnail(
                  RandomAccessStreamReference::CreateFromFile(
                      load.GetResults()));
              updater.Update();
            } catch (...) {
              // No cover in the flyout; everything else still works.
            }
          });
    }
  }
  updater.Update();

  const std::chrono::milliseconds duration(IntField(update, "durationMs"));
  const std::chrono::milliseconds position(IntField(update, "positionMs"));
  SystemMediaTransportControlsTimelineProperties timeline;
  timeline.StartTime(std::chrono::milliseconds(0));
  timeline.EndTime(duration);
  timeline.MinSeekTime(std::chrono::milliseconds(0));
  timeline.MaxSeekTime(duration);
  timeline.Position(position);
  smtc.UpdateTimelineProperties(timeline);
}

MediaControls::MediaControls(flutter::BinaryMessenger* messenger, HWND window)
    : state_(std::make_unique<State>()) {
  State* state = state_.get();
  state->window = window;
  state->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "com.musicplayer.music_player/media_controls",
      &flutter::StandardMethodCodec::GetInstance());

  try {
    auto interop = winrt::get_activation_factory<
        SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(
        window, winrt::guid_of<SystemMediaTransportControls>(),
        winrt::put_abi(state->smtc)));
    state->button_token = state->smtc.ButtonPressed(
        [window](const SystemMediaTransportControls&,
                 const SystemMediaTransportControlsButtonPressedEventArgs&
                     args) {
          PostMessage(window, kButtonMessage,
                      static_cast<WPARAM>(args.Button()), 0);
        });
    state->seek_token = state->smtc.PlaybackPositionChangeRequested(
        [window](const SystemMediaTransportControls&,
                 const PlaybackPositionChangeRequestedEventArgs& args) {
          const auto ms =
              std::chrono::duration_cast<std::chrono::milliseconds>(
                  args.RequestedPlaybackPosition())
                  .count();
          PostMessage(window, kSeekMessage, 0, static_cast<LPARAM>(ms));
        });
  } catch (...) {
    // Media controls unavailable (very old Windows): the app works without.
    state->smtc = nullptr;
  }

  state->channel->SetMethodCallHandler(
      [state](const flutter::MethodCall<EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() != "update") {
          result->NotImplemented();
          return;
        }
        const auto* update = std::get_if<EncodableMap>(call.arguments());
        if (state->smtc && update) {
          try {
            state->Apply(*update);
          } catch (...) {
            // A failed update only leaves the flyout stale.
          }
        }
        result->Success();
      });
}

MediaControls::~MediaControls() {
  state_->channel->SetMethodCallHandler(nullptr);
  if (state_->smtc) {
    try {
      state_->smtc.ButtonPressed(state_->button_token);
      state_->smtc.PlaybackPositionChangeRequested(state_->seek_token);
      state_->smtc.IsEnabled(false);
    } catch (...) {
    }
  }
}

bool MediaControls::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kButtonMessage) {
    const char* name =
        ButtonName(static_cast<SystemMediaTransportControlsButton>(wparam));
    if (name) {
      state_->channel->InvokeMethod("button",
                                    std::make_unique<EncodableValue>(name));
    }
    return true;
  }
  if (message == kSeekMessage) {
    state_->channel->InvokeMethod(
        "seek", std::make_unique<EncodableValue>(static_cast<int64_t>(lparam)));
    return true;
  }
  return false;
}
