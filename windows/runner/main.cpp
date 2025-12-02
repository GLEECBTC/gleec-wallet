#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Enforce single instance: create a named mutex. If it already exists or we
  // don't have access to it, try to bring the existing window to the foreground
  // and exit immediately.
  HANDLE singleInstanceMutex = CreateMutexW(nullptr, TRUE, L"Global\\GleecDEX_SingleInstanceMutex");
  DWORD createMutexError = GetLastError();
  const bool mutexIndicatesOtherInstance =
      (singleInstanceMutex == nullptr && createMutexError == ERROR_ACCESS_DENIED) ||
      (singleInstanceMutex != nullptr && createMutexError == ERROR_ALREADY_EXISTS);
  if (mutexIndicatesOtherInstance) {
    // Attempt to find the existing window by class or title and focus it.
    HWND existing = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
    if (existing == nullptr) {
      existing = FindWindowW(nullptr, L"gleecdex");
    }
    if (existing != nullptr) {
      ShowWindow(existing, SW_RESTORE);
      AllowSetForegroundWindow(ASFW_ANY);
      SetForegroundWindow(existing);
      BringWindowToTop(existing);
    }
    if (singleInstanceMutex) {
      CloseHandle(singleInstanceMutex);
    }
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"gleecdex", origin, size)) {
    if (singleInstanceMutex) {
      ReleaseMutex(singleInstanceMutex);
      CloseHandle(singleInstanceMutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (singleInstanceMutex) {
    ReleaseMutex(singleInstanceMutex);
    CloseHandle(singleInstanceMutex);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
