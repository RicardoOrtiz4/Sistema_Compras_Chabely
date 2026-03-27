#include "utils.h"

#include <algorithm>
#include <windows.h>
#include <dbghelp.h>
#include <psapi.h>
#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>

#include <iostream>
#include <iomanip>
#include <sstream>
#include <string>

namespace {

struct ModuleDetails {
  uintptr_t base = 0;
  DWORD size = 0;
  std::string path = "unknown";
};

std::string Utf8FromWide(const std::wstring& wide) {
  if (wide.empty()) {
    return std::string();
  }
  const int target_length = WideCharToMultiByte(
      CP_UTF8,
      WC_ERR_INVALID_CHARS,
      wide.c_str(),
      static_cast<int>(wide.size()),
      nullptr,
      0,
      nullptr,
      nullptr);
  if (target_length <= 0) {
    return std::string();
  }

  std::string utf8(target_length, '\0');
  const int converted = WideCharToMultiByte(
      CP_UTF8,
      WC_ERR_INVALID_CHARS,
      wide.c_str(),
      static_cast<int>(wide.size()),
      utf8.data(),
      target_length,
      nullptr,
      nullptr);
  if (converted <= 0) {
    return std::string();
  }
  return utf8;
}

std::wstring ExecutableDirectory() {
  wchar_t path[MAX_PATH];
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return L".";
  }

  std::wstring directory(path, length);
  const size_t separator = directory.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return L".";
  }
  return directory.substr(0, separator);
}

void AppendTextToFile(const std::wstring& path, const std::string& text) {
  HANDLE file = CreateFileW(
      path.c_str(),
      FILE_APPEND_DATA,
      FILE_SHARE_READ | FILE_SHARE_WRITE,
      nullptr,
      OPEN_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }

  DWORD written = 0;
  WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr);
  CloseHandle(file);
}

std::wstring BuildCrashDumpPath() {
  SYSTEMTIME now;
  GetLocalTime(&now);

  std::wostringstream name;
  name << ExecutableDirectory()
       << L"\\native_crash_"
       << now.wYear
       << L"-";
  if (now.wMonth < 10) name << L"0";
  name << now.wMonth
       << L"-";
  if (now.wDay < 10) name << L"0";
  name << now.wDay
       << L"_";
  if (now.wHour < 10) name << L"0";
  name << now.wHour;
  if (now.wMinute < 10) name << L"0";
  name << now.wMinute;
  if (now.wSecond < 10) name << L"0";
  name << now.wSecond
       << L"_"
       << GetCurrentProcessId()
       << L".dmp";
  return name.str();
}

void TryWriteMiniDump(EXCEPTION_POINTERS* exception) {
  const std::wstring dump_path = BuildCrashDumpPath();
  HANDLE dump_file = CreateFileW(
      dump_path.c_str(),
      GENERIC_WRITE,
      0,
      nullptr,
      CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (dump_file == INVALID_HANDLE_VALUE) {
    return;
  }

  MINIDUMP_EXCEPTION_INFORMATION exception_info;
  exception_info.ThreadId = GetCurrentThreadId();
  exception_info.ExceptionPointers = exception;
  exception_info.ClientPointers = FALSE;

  MiniDumpWriteDump(
      GetCurrentProcess(),
      GetCurrentProcessId(),
      dump_file,
      static_cast<MINIDUMP_TYPE>(
          MiniDumpWithIndirectlyReferencedMemory | MiniDumpScanMemory),
      exception == nullptr ? nullptr : &exception_info,
      nullptr,
      nullptr);

  CloseHandle(dump_file);
}

ModuleDetails DescribeModule(HMODULE module) {
  ModuleDetails details;
  if (module == nullptr) {
    return details;
  }

  details.base = reinterpret_cast<uintptr_t>(module);

  MODULEINFO module_info{};
  if (GetModuleInformation(
          GetCurrentProcess(), module, &module_info, sizeof(module_info))) {
    details.size = module_info.SizeOfImage;
  }

  wchar_t module_path_buffer[MAX_PATH];
  const DWORD module_path_length =
      GetModuleFileNameW(module, module_path_buffer, MAX_PATH);
  if (module_path_length > 0 && module_path_length < MAX_PATH) {
    details.path = Utf8FromWide(
        std::wstring(module_path_buffer, module_path_length));
  }

  return details;
}

ModuleDetails FindModuleForAddress(const void* address) {
  ModuleDetails details;
  if (address == nullptr) {
    return details;
  }

  HMODULE module = nullptr;
  if (!GetModuleHandleExW(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          reinterpret_cast<LPCWSTR>(address),
          &module)) {
    return details;
  }

  return DescribeModule(module);
}

std::string FormatNearbyBytes(const void* address, size_t count) {
  if (address == nullptr || count == 0) {
    return "unavailable";
  }

  std::string bytes;
  bytes.reserve(count * 3);
  const auto* base = reinterpret_cast<const unsigned char*>(address);
  for (size_t index = 0; index < count; ++index) {
    unsigned char value = 0;
    SIZE_T copied = 0;
    const BOOL ok = ReadProcessMemory(
        GetCurrentProcess(),
        base + index,
        &value,
        sizeof(value),
        &copied);
    if (!ok || copied != sizeof(value)) {
      bytes += "??";
    } else {
      std::ostringstream item;
      item << std::hex << std::setw(2) << std::setfill('0')
           << static_cast<unsigned int>(value);
      bytes += item.str();
    }
    if (index + 1 < count) {
      bytes += ' ';
    }
  }
  return bytes;
}

std::string FormatRelevantModules() {
  HMODULE modules[512];
  DWORD bytes_needed = 0;
  if (!EnumProcessModules(
          GetCurrentProcess(), modules, sizeof(modules), &bytes_needed)) {
    return "unavailable";
  }

  const size_t module_count =
      std::min(static_cast<size_t>(bytes_needed / sizeof(HMODULE)),
               sizeof(modules) / sizeof(modules[0]));
  const std::string executable_directory =
      Utf8FromWide(ExecutableDirectory());
  std::string formatted;

  for (size_t index = 0; index < module_count; ++index) {
    const ModuleDetails details = DescribeModule(modules[index]);
    if (details.path == "unknown") {
      continue;
    }

    if (details.path.rfind(executable_directory, 0) != 0) {
      continue;
    }

    std::ostringstream line;
    line << "\r\n  base=0x" << std::hex << details.base
         << " size=0x" << details.size
         << " path=" << details.path;
    formatted += line.str();
  }

  return formatted.empty() ? "none" : formatted;
}

void AppendContextRecord(std::ostringstream& buffer, const CONTEXT* context) {
  if (context == nullptr) {
    return;
  }

#if defined(_M_X64)
  buffer << " registers"
         << " rip=0x" << std::hex << context->Rip
         << " rsp=0x" << context->Rsp
         << " rbp=0x" << context->Rbp
         << " rax=0x" << context->Rax
         << " rbx=0x" << context->Rbx
         << " rcx=0x" << context->Rcx
         << " rdx=0x" << context->Rdx
         << " rsi=0x" << context->Rsi
         << " rdi=0x" << context->Rdi
         << " r8=0x" << context->R8
         << " r9=0x" << context->R9
         << " r10=0x" << context->R10
         << " r11=0x" << context->R11
         << " r12=0x" << context->R12
         << " r13=0x" << context->R13
         << " r14=0x" << context->R14
         << " r15=0x" << context->R15;
#endif
}

LONG WINAPI UnhandledCrashLogger(EXCEPTION_POINTERS* exception) {
  void* exception_address =
      exception && exception->ExceptionRecord
          ? exception->ExceptionRecord->ExceptionAddress
          : nullptr;
  const ModuleDetails exception_module = FindModuleForAddress(exception_address);

  MEMORY_BASIC_INFORMATION memory_info{};
  VirtualQuery(exception_address, &memory_info, sizeof(memory_info));

  const ModuleDetails allocation_module =
      FindModuleForAddress(memory_info.AllocationBase);

  wchar_t mapped_path_buffer[MAX_PATH];
  std::string mapped_path = "unknown";
  const DWORD mapped_length = GetMappedFileNameW(
      GetCurrentProcess(),
      exception_address,
      mapped_path_buffer,
      MAX_PATH);
  if (mapped_length > 0 && mapped_length < MAX_PATH) {
    mapped_path = Utf8FromWide(std::wstring(mapped_path_buffer, mapped_length));
  }

  std::ostringstream buffer;
  buffer << "native_crash"
         << " code=0x" << std::hex
         << (exception && exception->ExceptionRecord
                 ? exception->ExceptionRecord->ExceptionCode
                 : 0)
         << " address=0x" << std::hex
         << reinterpret_cast<uintptr_t>(exception_address)
         << " module=" << exception_module.path
         << " module_base=0x" << std::hex << exception_module.base;
  if (exception_module.base != 0 && exception_address != nullptr) {
    buffer << " module_offset=0x"
           << (reinterpret_cast<uintptr_t>(exception_address) -
               exception_module.base);
  }
  buffer
         << " alloc_base=0x" << std::hex
         << reinterpret_cast<uintptr_t>(memory_info.AllocationBase)
         << " alloc_module=" << allocation_module.path
         << " alloc_module_base=0x" << allocation_module.base
         << " region_size=0x" << std::hex
         << static_cast<uintptr_t>(memory_info.RegionSize)
         << " protect=0x" << std::hex << memory_info.Protect
         << " state=0x" << std::hex << memory_info.State
         << " type=0x" << std::hex << memory_info.Type
         << " mapped=" << mapped_path
         << " thread=" << std::dec << GetCurrentThreadId();
  AppendContextRecord(
      buffer,
      exception == nullptr ? nullptr : exception->ContextRecord);
  buffer << "\r\n"
         << "nearby_bytes " << FormatNearbyBytes(exception_address, 16)
         << "\r\n"
         << "loaded_modules" << FormatRelevantModules()
         << "\r\n";

  AppendTextToFile(ExecutableDirectory() + L"\\native_crash.log", buffer.str());
  TryWriteMiniDump(exception);
  return EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

void InstallCrashHandlers() {
  // Crash investigation instrumentation removed.
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}
