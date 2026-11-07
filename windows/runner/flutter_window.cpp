#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>
#include <string>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  metrics_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "hostany/windows",
      &flutter::StandardMethodCodec::GetInstance());
  metrics_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "getDeviceMetrics") {
          result->NotImplemented();
          return;
        }
        flutter::EncodableMap metrics;
        MEMORYSTATUSEX memory{};
        memory.dwLength = sizeof(memory);
        constexpr double gib = 1024.0 * 1024.0 * 1024.0;
        if (GlobalMemoryStatusEx(&memory)) {
          metrics[flutter::EncodableValue("ramGb")] = flutter::EncodableValue(
              static_cast<int32_t>((memory.ullTotalPhys + (1ULL << 29)) / (1ULL << 30)));
          metrics[flutter::EncodableValue("availRamGb")] = flutter::EncodableValue(memory.ullAvailPhys / gib);
        }
        std::wstring storage_path;
        if (call.arguments()) {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            const auto it = arguments->find(flutter::EncodableValue("storage_path"));
            if (it != arguments->end()) {
              const auto* path = std::get_if<std::string>(&it->second);
              if (path && !path->empty()) {
                const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->c_str(), -1, nullptr, 0);
                if (length > 0) {
                  storage_path.resize(length);
                  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->c_str(), -1, storage_path.data(), length);
                }
              }
            }
          }
        }
        ULARGE_INTEGER free_bytes{};
        if (GetDiskFreeSpaceExW(storage_path.empty() ? nullptr : storage_path.c_str(), &free_bytes, nullptr, nullptr)) {
          metrics[flutter::EncodableValue("freeStorageGb")] = flutter::EncodableValue(free_bytes.QuadPart / gib);
        }
        SYSTEM_INFO system{};
        GetNativeSystemInfo(&system);
        const std::string architecture = system.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_AMD64 ? "x64" : "Windows";
        metrics[flutter::EncodableValue("cpuLabel")] = flutter::EncodableValue(
            architecture + " / " + std::to_string(system.dwNumberOfProcessors) + " logical cores");
        SYSTEM_POWER_STATUS power{};
        if (GetSystemPowerStatus(&power)) {
          if (power.BatteryLifePercent != 255) {
            metrics[flutter::EncodableValue("batteryPercent")] = flutter::EncodableValue(static_cast<int32_t>(power.BatteryLifePercent));
          }
          metrics[flutter::EncodableValue("batteryCharging")] = flutter::EncodableValue(power.ACLineStatus == 1);
        }
        result->Success(flutter::EncodableValue(metrics));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  metrics_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
