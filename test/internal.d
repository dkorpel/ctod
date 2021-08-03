module internal;
extern(C): @nogc: nothrow: __gshared:

private template HasVersion(string versionId) {
	mixin("version("~versionId~") {enum HasVersion = true;} else {enum HasVersion = false;}");
}
//========================================================================
// GLFW 3.3 - www.glfw.org
//------------------------------------------------------------------------
// Copyright (c) 2002-2006 Marcus Geelnard
// Copyright (c) 2006-2019 Camilla Löwy <elmindreda@glfw.org>
//
// This software is provided 'as-is', without any express or implied
// warranty. In no event will the authors be held liable for any damages
// arising from the use of this software.
//
// Permission is granted to anyone to use this software for any purpose,
// including commercial applications, and to alter it and redistribute it
// freely, subject to the following restrictions:
//
// 1. The origin of this software must not be misrepresented; you must not
//    claim that you wrote the original software. If you use this software
//    in a product, an acknowledgment in the product documentation would
//    be appreciated but is not required.
//
// 2. Altered source versions must be plainly marked as such, and must not
//    be misrepresented as being the original software.
//
// 3. This notice may not be removed or altered from any source
//    distribution.
//
//========================================================================

//#pragma once

version (_GLFW_USE_CONFIG_H) {
 public import glfw_config;
}

static if (HasVersion!"GLFW_INCLUDE_GLCOREARB" || \
    HasVersion!"GLFW_INCLUDE_ES1"       || \
    HasVersion!"GLFW_INCLUDE_ES2"       || \
    HasVersion!"GLFW_INCLUDE_ES3"       || \
    HasVersion!"GLFW_INCLUDE_ES31"      || \
    HasVersion!"GLFW_INCLUDE_ES32"      || \
    HasVersion!"GLFW_INCLUDE_NONE"      || \
    HasVersion!"GLFW_INCLUDE_GLEXT"     || \
    HasVersion!"GLFW_INCLUDE_GLU"       || \
    HasVersion!"GLFW_INCLUDE_VULKAN"    || \
    HasVersion!"GLFW_DLL") {
 static assert(0, "You must not define any header option macros when compiling GLFW");
}

version = GLFW_INCLUDE_NONE;
public import ...include.GLFW.glfw3;

enum _GLFW_INSERT_FIRST =      0;
enum _GLFW_INSERT_LAST =       1;

enum _GLFW_POLL_PRESENCE =     0;
enum _GLFW_POLL_AXES =         1;
enum _GLFW_POLL_BUTTONS =      2;
enum _GLFW_POLL_ALL =          (_GLFW_POLL_AXES | _GLFW_POLL_BUTTONS);

enum _GLFW_MESSAGE_SIZE =      1024;

alias int GLFWbool;

struct _GLFWerror ;
struct _GLFWinitconfig ;
struct _GLFWwndconfig ;
struct _GLFWctxconfig ;
struct _GLFWfbconfig ;
struct _GLFWcontext ;
struct _GLFWwindow ;
struct _GLFWlibrary ;
struct _GLFWmonitor ;
struct _GLFWcursor ;
struct _GLFWmapelement ;
struct _GLFWmapping ;
struct _GLFWjoystick ;
struct _GLFWtls ;
struct _GLFWmutex ;

alias void function(_GLFWwindow*) _GLFWmakecontextcurrentfun;
alias void function(_GLFWwindow*) _GLFWswapbuffersfun;
alias void function(int) _GLFWswapintervalfun;
alias int function(const(char)*) _GLFWextensionsupportedfun;
alias GLFWglproc function(const(char)*) _GLFWgetprocaddressfun;
alias void function(_GLFWwindow*) _GLFWdestroycontextfun;

enum GL_VERSION = 0x1f02;
enum GL_NONE = 0;
enum GL_COLOR_BUFFER_BIT = 0x00004000;
enum GL_UNSIGNED_BYTE = 0x1401;
enum GL_EXTENSIONS = 0x1f03;
enum GL_NUM_EXTENSIONS = 0x821d;
enum GL_CONTEXT_FLAGS = 0x821e;
enum GL_CONTEXT_FLAG_FORWARD_COMPATIBLE_BIT = 0x00000001;
enum GL_CONTEXT_FLAG_DEBUG_BIT = 0x00000002;
enum GL_CONTEXT_PROFILE_MASK = 0x9126;
enum GL_CONTEXT_COMPATIBILITY_PROFILE_BIT = 0x00000002;
enum GL_CONTEXT_CORE_PROFILE_BIT = 0x00000001;
enum GL_RESET_NOTIFICATION_STRATEGY_ARB = 0x8256;
enum GL_LOSE_CONTEXT_ON_RESET_ARB = 0x8252;
enum GL_NO_RESET_NOTIFICATION_ARB = 0x8261;
enum GL_CONTEXT_RELEASE_BEHAVIOR = 0x82fb;
enum GL_CONTEXT_RELEASE_BEHAVIOR_FLUSH = 0x82fc;
enum GL_CONTEXT_FLAG_NO_ERROR_BIT_KHR = 0x00000008;

alias int GLint;
alias uint GLuint;
alias uint GLenum;
alias uint GLbitfield;
alias ubyte GLubyte;

alias void (GLbitfield);
alias const(GLubyte)* (GLenum);
alias void (GLenum, GLint*);
alias const(GLubyte)* (GLenum, GLuint);

enum VK_NULL_HANDLE = 0;

alias void* VkInstance;
alias void* VkPhysicalDevice;
alias ulong VkSurfaceKHR;
alias uint VkFlags;
alias uint VkBool32;

enum VkStructureType {
    VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR = 1000004000,
    VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR = 1000005000,
    VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR = 1000006000,
    VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR = 1000009000,
    VK_STRUCTURE_TYPE_MACOS_SURFACE_CREATE_INFO_MVK = 1000123000,
    VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT = 1000217000,
    VK_STRUCTURE_TYPE_MAX_ENUM = 0x7FFFFFFF
}

enum VkResult {
    VK_SUCCESS = 0,
    VK_NOT_READY = 1,
    VK_TIMEOUT = 2,
    VK_EVENT_SET = 3,
    VK_EVENT_RESET = 4,
    VK_INCOMPLETE = 5,
    VK_ERROR_OUT_OF_HOST_MEMORY = -1,
    VK_ERROR_OUT_OF_DEVICE_MEMORY = -2,
    VK_ERROR_INITIALIZATION_FAILED = -3,
    VK_ERROR_DEVICE_LOST = -4,
    VK_ERROR_MEMORY_MAP_FAILED = -5,
    VK_ERROR_LAYER_NOT_PRESENT = -6,
    VK_ERROR_EXTENSION_NOT_PRESENT = -7,
    VK_ERROR_FEATURE_NOT_PRESENT = -8,
    VK_ERROR_INCOMPATIBLE_DRIVER = -9,
    VK_ERROR_TOO_MANY_OBJECTS = -10,
    VK_ERROR_FORMAT_NOT_SUPPORTED = -11,
    VK_ERROR_SURFACE_LOST_KHR = -1000000000,
    VK_SUBOPTIMAL_KHR = 1000001003,
    VK_ERROR_OUT_OF_DATE_KHR = -1000001004,
    VK_ERROR_INCOMPATIBLE_DISPLAY_KHR = -1000003001,
    VK_ERROR_NATIVE_WINDOW_IN_USE_KHR = -1000000001,
    VK_ERROR_VALIDATION_FAILED_EXT = -1000011001,
    VK_RESULT_MAX_ENUM = 0x7FFFFFFF
}

struct VkAllocationCallbacks ;

struct VkExtensionProperties {
    char[256] extensionName;
    uint specVersion;
}

alias void ();

version (_GLFW_VULKAN_STATIC) {
  PFN_vkVoidFunction vkGetInstanceProcAddr(VkInstance, const(char)*);
  VkResult vkEnumerateInstanceExtensionProperties(const(char)*, uint*, VkExtensionProperties*);
} else {
  alias  VkInstance;alias  const; char*){}
  
  enum vkEnumerateInstanceExtensionProperties = _glfw.vk.EnumerateInstanceExtensionProperties;
  enum vkGetInstanceProcAddr = _glfw.vk.GetInstanceProcAddr;
}

version (_GLFW_COCOA) {
 public import cocoa_platform;
} else version (_GLFW_WIN32) {
 public import win32_platform;
} else version (_GLFW_X11) {
 public import x11_platform;
} else version (_GLFW_WAYLAND) {
 public import wl_platform;
} else version (_GLFW_OSMESA) {
 public import null_platform;
} else {
 static assert(0, "No supported window creation API selected");
}

// Constructs a version number string from the public header macros
enum string _GLFW_CONCAT_VERSION(string m, string n, string r) = ` #m "." #n "." #r`;
enum string _GLFW_MAKE_VERSION(string m, string n, string r) = ` _GLFW_CONCAT_VERSION(m, n, r)`;
enum _GLFW_VERSION_NUMBER = _GLFW_MAKE_VERSION(GLFW_VERSION_MAJOR, \
                                                GLFW_VERSION_MINOR, \
                                                GLFW_VERSION_REVISION);

// Checks for whether the library has been initialized
enum string _GLFW_REQUIRE_INIT() = `                         \
    if (!_glfw.initialized)                          \
    {                                                \
        _glfwInputError(GLFW_NOT_INITIALIZED, NULL); \
        return;                                      \
    }`;
enum string _GLFW_REQUIRE_INIT_OR_RETURN(string x) = `              \
    if (!_glfw.initialized)                          \
    {                                                \
        _glfwInputError(GLFW_NOT_INITIALIZED, NULL); \
        return x;                                    \
    }`;

// Swaps the provided pointers
enum string _GLFW_SWAP_POINTERS(string x, string y) = ` \
    {                             \
        void* t;                  \
        t = x;                    \
        x = y;                    \
        y = t;                    \
    }`;

// Per-thread error structure
//
struct _GLFWerror
{
    _GLFWerror* next;
    int code;
    char[_GLFW_MESSAGE_SIZE] description;
}

// Initialization configuration
//
// Parameters relating to the initialization of the library
//
struct _GLFWinitconfig
{
    GLFWbool hatButtons;
    struct _Ns {
        GLFWbool menubar;
        GLFWbool chdir;
    }_Ns ns;
}

// Window configuration
//
// Parameters relating to the creation of the window but not directly related
// to the framebuffer.  This is used to pass window creation parameters from
// shared code to the platform API.
//
struct _GLFWwndconfig
{
    int width;
    int height;
    const(char)* title;
    GLFWbool resizable;
    GLFWbool visible;
    GLFWbool decorated;
    GLFWbool focused;
    GLFWbool autoIconify;
    GLFWbool floating;
    GLFWbool maximized;
    GLFWbool centerCursor;
    GLFWbool focusOnShow;
    GLFWbool scaleToMonitor;
    struct _Ns {
        GLFWbool retina;
        char[256] frameName;
    }_Ns ns;
    struct _X11 {
        char[256] className;
        char[256] instanceName;
    }_X11 x11;
}

// Context configuration
//
// Parameters relating to the creation of the context but not directly related
// to the framebuffer.  This is used to pass context creation parameters from
// shared code to the platform API.
//
struct _GLFWctxconfig
{
    int client;
    int source;
    int major;
    int minor;
    GLFWbool forward;
    GLFWbool debug_;
    GLFWbool noerror;
    int profile;
    int robustness;
    int release;
    _GLFWwindow* share;
    struct _Nsgl {
        GLFWbool offline;
    }_Nsgl nsgl;
}

// Framebuffer configuration
//
// This describes buffers and their sizes.  It also contains
// a platform-specific ID used to map back to the backend API object.
//
// It is used to pass framebuffer parameters from shared code to the platform
// API and also to enumerate and select available framebuffer configs.
//
struct _GLFWfbconfig
{
    int redBits;
    int greenBits;
    int blueBits;
    int alphaBits;
    int depthBits;
    int stencilBits;
    int accumRedBits;
    int accumGreenBits;
    int accumBlueBits;
    int accumAlphaBits;
    int auxBuffers;
    GLFWbool stereo;
    int samples;
    GLFWbool sRGB;
    GLFWbool doublebuffer;
    GLFWbool transparent;
    uintptr_t handle;
}

// Context structure
//
struct _GLFWcontext
{
    int client;
    int source;
    int major;int minor;int revision;
    GLFWbool forward;GLFWbool debug_;GLFWbool noerror;
    int profile;
    int robustness;
    int release;

    PFNGLGETSTRINGIPROC GetStringi;
    PFNGLGETINTEGERVPROC GetIntegerv;
    PFNGLGETSTRINGPROC GetString;

    _GLFWmakecontextcurrentfun makeCurrent;
    _GLFWswapbuffersfun swapBuffers;
    _GLFWswapintervalfun swapInterval;
    _GLFWextensionsupportedfun extensionSupported;
    _GLFWgetprocaddressfun getProcAddress;
    _GLFWdestroycontextfun destroy;

    // This is defined in the context API's context.h
    _GLFW_PLATFORM_CONTEXT_STATE;
    // This is defined in egl_context.h
    _GLFW_EGL_CONTEXT_STATE;
    // This is defined in osmesa_context.h
    _GLFW_OSMESA_CONTEXT_STATE;
}

// Window and context structure
//
struct _GLFWwindow
{
    struct _GLFWwindow ;_GLFWwindow* next;

    // Window settings and state
    GLFWbool resizable;
    GLFWbool decorated;
    GLFWbool autoIconify;
    GLFWbool floating;
    GLFWbool focusOnShow;
    GLFWbool shouldClose;
    void* userPointer;
    GLFWvidmode videoMode;
    _GLFWmonitor* monitor;
    _GLFWcursor* cursor;

    int minwidth;int minheight;
    int maxwidth;int maxheight;
    int numer;int denom;

    GLFWbool stickyKeys;
    GLFWbool stickyMouseButtons;
    GLFWbool lockKeyMods;
    int cursorMode;
    char[GLFW_MOUSE_BUTTON_LAST + 1] mouseButtons;
    char[GLFW_KEY_LAST + 1] keys;
    // Virtual cursor position when cursor is disabled
    double virtualCursorPosX;double virtualCursorPosY;
    GLFWbool rawMouseMotion;

    _GLFWcontext context;

    struct _Callbacks {
        GLFWwindowposfun pos;
        GLFWwindowsizefun size;
        GLFWwindowclosefun close;
        GLFWwindowrefreshfun refresh;
        GLFWwindowfocusfun focus;
        GLFWwindowiconifyfun iconify;
        GLFWwindowmaximizefun maximize;
        GLFWframebuffersizefun fbsize;
        GLFWwindowcontentscalefun scale;
        GLFWmousebuttonfun mouseButton;
        GLFWcursorposfun cursorPos;
        GLFWcursorenterfun cursorEnter;
        GLFWscrollfun scroll;
        GLFWkeyfun key;
        GLFWcharfun character;
        GLFWcharmodsfun charmods;
        GLFWdropfun drop;
    }_Callbacks callbacks;

    // This is defined in the window API's platform.h
    _GLFW_PLATFORM_WINDOW_STATE;
}

// Monitor structure
//
struct _GLFWmonitor
{
    char* name;
    void* userPointer;

    // Physical dimensions in millimeters.
    int widthMM;int heightMM;

    // The window whose video mode is current on this monitor
    _GLFWwindow* window;

    GLFWvidmode* modes;
    int modeCount;
    GLFWvidmode currentMode;

    GLFWgammaramp originalRamp;
    GLFWgammaramp currentRamp;

    // This is defined in the window API's platform.h
    _GLFW_PLATFORM_MONITOR_STATE;
}

// Cursor structure
//
struct _GLFWcursor
{
    _GLFWcursor* next;

    // This is defined in the window API's platform.h
    _GLFW_PLATFORM_CURSOR_STATE;
}

// Gamepad mapping element structure
//
struct _GLFWmapelement
{
    ubyte type;
    ubyte index;
    byte axisScale;
    byte axisOffset;
}

// Gamepad mapping structure
//
struct _GLFWmapping
{
    char[128] name;
    char[33] guid;
    _GLFWmapelement[15] buttons;
    _GLFWmapelement[6] axes;
}

// Joystick structure
//
struct _GLFWjoystick
{
    GLFWbool present;
    float* axes;
    int axisCount;
    ubyte* buttons;
    int buttonCount;
    ubyte* hats;
    int hatCount;
    char* name;
    void* userPointer;
    char[33] guid;
    _GLFWmapping* mapping;

    // This is defined in the joystick API's joystick.h
    _GLFW_PLATFORM_JOYSTICK_STATE;
}

// Thread local storage structure
//
struct _GLFWtls
{
    // This is defined in the platform's thread.h
    _GLFW_PLATFORM_TLS_STATE;
}

// Mutex structure
//
struct _GLFWmutex
{
    // This is defined in the platform's thread.h
    _GLFW_PLATFORM_MUTEX_STATE;
}

// Library global data
//
struct _GLFWlibrary
{
    GLFWbool initialized;

    struct _Hints {
        _GLFWinitconfig init;
        _GLFWfbconfig framebuffer;
        _GLFWwndconfig window;
        _GLFWctxconfig context;
        int refreshRate;
    }_Hints hints;

    _GLFWerror* errorListHead;
    _GLFWcursor* cursorListHead;
    _GLFWwindow* windowListHead;

    _GLFWmonitor** monitors;
    int monitorCount;

    _GLFWjoystick[GLFW_JOYSTICK_LAST + 1] joysticks;
    _GLFWmapping* mappings;
    int mappingCount;

    _GLFWtls errorSlot;
    _GLFWtls contextSlot;
    _GLFWmutex errorLock;

    struct _Timer {
        ulong offset;
        // This is defined in the platform's time.h
        _GLFW_PLATFORM_LIBRARY_TIMER_STATE;
    }_Timer timer;

    struct _Vk {
        GLFWbool available;
        void* handle;
        char*[2] extensions;
static if (!HasVersion!"_GLFW_VULKAN_STATIC") {
        PFN_vkEnumerateInstanceExtensionProperties EnumerateInstanceExtensionProperties;
        PFN_vkGetInstanceProcAddr GetInstanceProcAddr;
}
        GLFWbool KHR_surface;
version (_GLFW_WIN32) {
        GLFWbool KHR_win32_surface;
} else version (_GLFW_COCOA) {
        GLFWbool MVK_macos_surface;
        GLFWbool EXT_metal_surface;
} else version (_GLFW_X11) {
        GLFWbool KHR_xlib_surface;
        GLFWbool KHR_xcb_surface;
} else version (_GLFW_WAYLAND) {
        GLFWbool KHR_wayland_surface;
}
    }_Vk vk;

    struct _Callbacks {
        GLFWmonitorfun monitor;
        GLFWjoystickfun joystick;
    }_Callbacks callbacks;

    // This is defined in the window API's platform.h
    _GLFW_PLATFORM_LIBRARY_WINDOW_STATE;
    // This is defined in the context API's context.h
    _GLFW_PLATFORM_LIBRARY_CONTEXT_STATE;
    // This is defined in the platform's joystick.h
    _GLFW_PLATFORM_LIBRARY_JOYSTICK_STATE;
    // This is defined in egl_context.h
    _GLFW_EGL_LIBRARY_CONTEXT_STATE;
    // This is defined in osmesa_context.h
    _GLFW_OSMESA_LIBRARY_CONTEXT_STATE;
}

// Global state shared between compilation units of GLFW
//
extern _GLFWlibrary _glfw;


//////////////////////////////////////////////////////////////////////////
//////                       GLFW platform API                      //////
//////////////////////////////////////////////////////////////////////////

int _glfwPlatformInit();
void _glfwPlatformTerminate();
const(char)* _glfwPlatformGetVersionString();

void _glfwPlatformGetCursorPos(_GLFWwindow* window, double* xpos, double* ypos);
void _glfwPlatformSetCursorPos(_GLFWwindow* window, double xpos, double ypos);
void _glfwPlatformSetCursorMode(_GLFWwindow* window, int mode);
void _glfwPlatformSetRawMouseMotion(_GLFWwindow* window, GLFWbool enabled);
GLFWbool _glfwPlatformRawMouseMotionSupported();
int _glfwPlatformCreateCursor(_GLFWcursor* cursor, const(GLFWimage)* image, int xhot, int yhot);
int _glfwPlatformCreateStandardCursor(_GLFWcursor* cursor, int shape);
void _glfwPlatformDestroyCursor(_GLFWcursor* cursor);
void _glfwPlatformSetCursor(_GLFWwindow* window, _GLFWcursor* cursor);

const(char)* _glfwPlatformGetScancodeName(int scancode);
int _glfwPlatformGetKeyScancode(int key);

void _glfwPlatformFreeMonitor(_GLFWmonitor* monitor);
void _glfwPlatformGetMonitorPos(_GLFWmonitor* monitor, int* xpos, int* ypos);
void _glfwPlatformGetMonitorContentScale(_GLFWmonitor* monitor, float* xscale, float* yscale);
void _glfwPlatformGetMonitorWorkarea(_GLFWmonitor* monitor, int* xpos, int* ypos, int* width, int* height);
GLFWvidmode* _glfwPlatformGetVideoModes(_GLFWmonitor* monitor, int* count);
void _glfwPlatformGetVideoMode(_GLFWmonitor* monitor, GLFWvidmode* mode);
GLFWbool _glfwPlatformGetGammaRamp(_GLFWmonitor* monitor, GLFWgammaramp* ramp);
void _glfwPlatformSetGammaRamp(_GLFWmonitor* monitor, const(GLFWgammaramp)* ramp);

void _glfwPlatformSetClipboardString(const(char)* string);
const(char)* _glfwPlatformGetClipboardString();

int _glfwPlatformPollJoystick(_GLFWjoystick* js, int mode);
void _glfwPlatformUpdateGamepadGUID(char* guid);

ulong _glfwPlatformGetTimerValue();
ulong _glfwPlatformGetTimerFrequency();

int _glfwPlatformCreateWindow(_GLFWwindow* window, const(_GLFWwndconfig)* wndconfig, const(_GLFWctxconfig)* ctxconfig, const(_GLFWfbconfig)* fbconfig);
void _glfwPlatformDestroyWindow(_GLFWwindow* window);
void _glfwPlatformSetWindowTitle(_GLFWwindow* window, const(char)* title);
void _glfwPlatformSetWindowIcon(_GLFWwindow* window, int count, const(GLFWimage)* images);
void _glfwPlatformGetWindowPos(_GLFWwindow* window, int* xpos, int* ypos);
void _glfwPlatformSetWindowPos(_GLFWwindow* window, int xpos, int ypos);
void _glfwPlatformGetWindowSize(_GLFWwindow* window, int* width, int* height);
void _glfwPlatformSetWindowSize(_GLFWwindow* window, int width, int height);
void _glfwPlatformSetWindowSizeLimits(_GLFWwindow* window, int minwidth, int minheight, int maxwidth, int maxheight);
void _glfwPlatformSetWindowAspectRatio(_GLFWwindow* window, int numer, int denom);
void _glfwPlatformGetFramebufferSize(_GLFWwindow* window, int* width, int* height);
void _glfwPlatformGetWindowFrameSize(_GLFWwindow* window, int* left, int* top, int* right, int* bottom);
void _glfwPlatformGetWindowContentScale(_GLFWwindow* window, float* xscale, float* yscale);
void _glfwPlatformIconifyWindow(_GLFWwindow* window);
void _glfwPlatformRestoreWindow(_GLFWwindow* window);
void _glfwPlatformMaximizeWindow(_GLFWwindow* window);
void _glfwPlatformShowWindow(_GLFWwindow* window);
void _glfwPlatformHideWindow(_GLFWwindow* window);
void _glfwPlatformRequestWindowAttention(_GLFWwindow* window);
void _glfwPlatformFocusWindow(_GLFWwindow* window);
void _glfwPlatformSetWindowMonitor(_GLFWwindow* window, _GLFWmonitor* monitor, int xpos, int ypos, int width, int height, int refreshRate);
int _glfwPlatformWindowFocused(_GLFWwindow* window);
int _glfwPlatformWindowIconified(_GLFWwindow* window);
int _glfwPlatformWindowVisible(_GLFWwindow* window);
int _glfwPlatformWindowMaximized(_GLFWwindow* window);
int _glfwPlatformWindowHovered(_GLFWwindow* window);
int _glfwPlatformFramebufferTransparent(_GLFWwindow* window);
float _glfwPlatformGetWindowOpacity(_GLFWwindow* window);
void _glfwPlatformSetWindowResizable(_GLFWwindow* window, GLFWbool enabled);
void _glfwPlatformSetWindowDecorated(_GLFWwindow* window, GLFWbool enabled);
void _glfwPlatformSetWindowFloating(_GLFWwindow* window, GLFWbool enabled);
void _glfwPlatformSetWindowOpacity(_GLFWwindow* window, float opacity);

void _glfwPlatformPollEvents();
void _glfwPlatformWaitEvents();
void _glfwPlatformWaitEventsTimeout(double timeout);
void _glfwPlatformPostEmptyEvent();

void _glfwPlatformGetRequiredInstanceExtensions(char** extensions);
int _glfwPlatformGetPhysicalDevicePresentationSupport(VkInstance instance, VkPhysicalDevice device, uint queuefamily);
VkResult _glfwPlatformCreateWindowSurface(VkInstance instance, _GLFWwindow* window, const(VkAllocationCallbacks)* allocator, VkSurfaceKHR* surface);

GLFWbool _glfwPlatformCreateTls(_GLFWtls* tls);
void _glfwPlatformDestroyTls(_GLFWtls* tls);
void* _glfwPlatformGetTls(_GLFWtls* tls);
void _glfwPlatformSetTls(_GLFWtls* tls, void* value);

GLFWbool _glfwPlatformCreateMutex(_GLFWmutex* mutex);
void _glfwPlatformDestroyMutex(_GLFWmutex* mutex);
void _glfwPlatformLockMutex(_GLFWmutex* mutex);
void _glfwPlatformUnlockMutex(_GLFWmutex* mutex);


//////////////////////////////////////////////////////////////////////////
//////                         GLFW event API                       //////
//////////////////////////////////////////////////////////////////////////

void _glfwInputWindowFocus(_GLFWwindow* window, GLFWbool focused);
void _glfwInputWindowPos(_GLFWwindow* window, int xpos, int ypos);
void _glfwInputWindowSize(_GLFWwindow* window, int width, int height);
void _glfwInputFramebufferSize(_GLFWwindow* window, int width, int height);
void _glfwInputWindowContentScale(_GLFWwindow* window, float xscale, float yscale);
void _glfwInputWindowIconify(_GLFWwindow* window, GLFWbool iconified);
void _glfwInputWindowMaximize(_GLFWwindow* window, GLFWbool maximized);
void _glfwInputWindowDamage(_GLFWwindow* window);
void _glfwInputWindowCloseRequest(_GLFWwindow* window);
void _glfwInputWindowMonitor(_GLFWwindow* window, _GLFWmonitor* monitor);

void _glfwInputKey(_GLFWwindow* window, int key, int scancode, int action, int mods);
void _glfwInputChar(_GLFWwindow* window, uint codepoint, int mods, GLFWbool plain);
void _glfwInputScroll(_GLFWwindow* window, double xoffset, double yoffset);
void _glfwInputMouseClick(_GLFWwindow* window, int button, int action, int mods);
void _glfwInputCursorPos(_GLFWwindow* window, double xpos, double ypos);
void _glfwInputCursorEnter(_GLFWwindow* window, GLFWbool entered);
void _glfwInputDrop(_GLFWwindow* window, int count, const(char)** names);
void _glfwInputJoystick(_GLFWjoystick* js, int event);
void _glfwInputJoystickAxis(_GLFWjoystick* js, int axis, float value);
void _glfwInputJoystickButton(_GLFWjoystick* js, int button, char value);
void _glfwInputJoystickHat(_GLFWjoystick* js, int hat, char value);

void _glfwInputMonitor(_GLFWmonitor* monitor, int action, int placement);
void _glfwInputMonitorWindow(_GLFWmonitor* monitor, _GLFWwindow* window);

version (__GNUC__) {
void _glfwInputError(int code, const(char)* format, ...);
} else {
void _glfwInputError(int code, const(char)* format, ...);
}


//////////////////////////////////////////////////////////////////////////
//////                       GLFW internal API                      //////
//////////////////////////////////////////////////////////////////////////

GLFWbool _glfwStringInExtensionString(const(char)* string, const(char)* extensions);
const(_GLFWfbconfig)* _glfwChooseFBConfig(const(_GLFWfbconfig)* desired, const(_GLFWfbconfig)* alternatives, uint count);
GLFWbool _glfwRefreshContextAttribs(_GLFWwindow* window, const(_GLFWctxconfig)* ctxconfig);
GLFWbool _glfwIsValidContextConfig(const(_GLFWctxconfig)* ctxconfig);

const(GLFWvidmode)* _glfwChooseVideoMode(_GLFWmonitor* monitor, const(GLFWvidmode)* desired);
int _glfwCompareVideoModes(const(GLFWvidmode)* first, const(GLFWvidmode)* second);
_GLFWmonitor* _glfwAllocMonitor(const(char)* name, int widthMM, int heightMM);
void _glfwFreeMonitor(_GLFWmonitor* monitor);
void _glfwAllocGammaArrays(GLFWgammaramp* ramp, uint size);
void _glfwFreeGammaArrays(GLFWgammaramp* ramp);
void _glfwSplitBPP(int bpp, int* red, int* green, int* blue);

_GLFWjoystick* _glfwAllocJoystick(const(char)* name, const(char)* guid, int axisCount, int buttonCount, int hatCount);
void _glfwFreeJoystick(_GLFWjoystick* js);
void _glfwCenterCursorInContentArea(_GLFWwindow* window);

GLFWbool _glfwInitVulkan(int mode);
void _glfwTerminateVulkan();
const(char)* _glfwGetVulkanResultString(VkResult result);

char* _glfw_strdup(const(char)* source);
float _glfw_fminf(float a, float b);
float _glfw_fmaxf(float a, float b);