/* ==============================================================================
 * REAPER Native Notator - High-Refresh Win32 Timer Bridge (notator_timer_x64.dll)
 * Unlocks 60 / 90 / 120 / 144 FPS for reaper.defer() and ReaImGui on Windows
 * by driving REAPER's main window misc timer (WM_TIMER 0x29a) at 1ms precision.
 * Zero dependency on Lua C ABI or CRT (all exports return 0 stack items).
 * ============================================================================== */

typedef void*          HWND;
typedef unsigned int   UINT;
typedef unsigned long  DWORD;
typedef unsigned __int64 UINT_PTR;
typedef __int64        LPARAM;
typedef __int64        WPARAM;
typedef __int64        LRESULT;
typedef int            BOOL;

#define NULL ((void*)0)
#define TRUE 1
#define FALSE 0
#define WM_TIMER 0x0113
#define REAPER_MISC_TIMER_ID 0x29a
#define NOTATOR_WATCHDOG_TIMER_ID 0x29b0

typedef BOOL (__stdcall *WNDENUMPROC)(HWND, LPARAM);
typedef void (__stdcall *TIMERPROC)(HWND, UINT, UINT_PTR, DWORD);

__declspec(dllimport) DWORD    __stdcall GetCurrentProcessId(void);
__declspec(dllimport) DWORD    __stdcall GetWindowThreadProcessId(HWND hWnd, DWORD *lpdwProcessId);
__declspec(dllimport) int      __stdcall GetClassNameA(HWND hWnd, char *lpClassName, int nMaxCount);
__declspec(dllimport) BOOL     __stdcall EnumWindows(WNDENUMPROC lpEnumFunc, LPARAM lParam);
__declspec(dllimport) HWND     __stdcall FindWindowExA(HWND hWndParent, HWND hWndChildAfter, const char *lpszClass, const char *lpszWindow);
__declspec(dllimport) BOOL     __stdcall IsWindow(HWND hWnd);
__declspec(dllimport) UINT_PTR __stdcall SetTimer(HWND hWnd, UINT_PTR nIDEvent, UINT uElapse, TIMERPROC lpTimerFunc);
__declspec(dllimport) BOOL     __stdcall KillTimer(HWND hWnd, UINT_PTR uIDEvent);
__declspec(dllimport) LRESULT  __stdcall SendMessageA(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
__declspec(dllimport) DWORD    __stdcall timeGetTime(void);
__declspec(dllimport) UINT     __stdcall timeBeginPeriod(UINT uPeriod);
__declspec(dllimport) UINT     __stdcall timeEndPeriod(UINT uPeriod);

static HWND  g_reaper_hwnd     = NULL;
static UINT  g_target_ms       = 30;
static DWORD g_last_frame_tick = 0;
static DWORD g_last_hb_tick    = 0;
static BOOL  g_period_active   = FALSE;
static BOOL  g_watchdog_active = FALSE;
static BOOL  g_in_dispatch     = FALSE;

static int str_eq_reaperwnd(const char *s) {
    const char *t = "REAPERwnd";
    int i = 0;
    for (i = 0; i < 10; ++i) {
        if (s[i] != t[i]) return 0;
    }
    return 1;
}

static BOOL __stdcall enum_reaper_wnd_cb(HWND hwnd, LPARAM lParam) {
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == (DWORD)lParam) {
        char cls[64];
        cls[0] = '\0';
        if (GetClassNameA(hwnd, cls, 64) > 0) {
            if (str_eq_reaperwnd(cls)) {
                g_reaper_hwnd = hwnd;
                return FALSE;
            }
        }
    }
    return TRUE;
}

static HWND get_reaper_hwnd(void) {
    if (g_reaper_hwnd && IsWindow(g_reaper_hwnd)) {
        return g_reaper_hwnd;
    }
    g_reaper_hwnd = NULL;
    EnumWindows(enum_reaper_wnd_cb, (LPARAM)GetCurrentProcessId());
    if (!g_reaper_hwnd) {
        g_reaper_hwnd = FindWindowExA(NULL, NULL, "REAPERwnd", NULL);
    }
    return g_reaper_hwnd;
}

static void stop_timer_internal(void) {
    HWND hwnd = get_reaper_hwnd();
    if (hwnd && g_watchdog_active) {
        KillTimer(hwnd, NOTATOR_WATCHDOG_TIMER_ID);
        g_watchdog_active = FALSE;
    }
    if (hwnd) {
        SetTimer(hwnd, REAPER_MISC_TIMER_ID, 30, NULL);
    }
    if (g_period_active) {
        timeEndPeriod(1);
        g_period_active = FALSE;
    }
    g_target_ms = 30;
}

static void __stdcall notator_watchdog_timer_proc(HWND hwnd, UINT uMsg, UINT_PTR idEvent, DWORD dwTime) {
    (void)uMsg;
    (void)idEvent;
    (void)dwTime;

    if (g_in_dispatch) {
        return;
    }

    DWORD now = timeGetTime();

    /* Auto-shutoff watchdog: if Lua script stopped calling heartbeat for > 800ms, restore defaults */
    if (g_last_hb_tick != 0 && (now - g_last_hb_tick) > 800) {
        stop_timer_internal();
        return;
    }

    /* Self-healing check: only intervene if REAPER's 0x29a timer was reset externally and missed its window */
    if (g_target_ms < 28 && hwnd && IsWindow(hwnd)) {
        DWORD elapsed = now - g_last_frame_tick;
        if (elapsed >= (g_target_ms + 6)) {
            g_in_dispatch = TRUE;
            g_last_frame_tick = now;
            SetTimer(hwnd, REAPER_MISC_TIMER_ID, g_target_ms, NULL);
            SendMessageA(hwnd, WM_TIMER, (WPARAM)REAPER_MISC_TIMER_ID, 0);
            g_in_dispatch = FALSE;
        }
    }
}

static void apply_interval_ms(UINT interval_ms) {
    HWND hwnd = get_reaper_hwnd();
    if (!hwnd) {
        return;
    }

    DWORD now = timeGetTime();
    g_last_hb_tick = now;
    g_last_frame_tick = now;
    g_target_ms = interval_ms;

    if (interval_ms < 28) {
        if (!g_period_active) {
            timeBeginPeriod(1);
            g_period_active = TRUE;
        }
        SetTimer(hwnd, REAPER_MISC_TIMER_ID, interval_ms, NULL);
        SetTimer(hwnd, NOTATOR_WATCHDOG_TIMER_ID, interval_ms, notator_watchdog_timer_proc);
        g_watchdog_active = TRUE;
    } else {
        if (g_watchdog_active) {
            KillTimer(hwnd, NOTATOR_WATCHDOG_TIMER_ID);
            g_watchdog_active = FALSE;
        }
        SetTimer(hwnd, REAPER_MISC_TIMER_ID, interval_ms, NULL);
        if (g_period_active) {
            timeEndPeriod(1);
            g_period_active = FALSE;
        }
    }
}

__declspec(dllexport) int notator_timer_heartbeat(void *L) {
    (void)L;
    DWORD now = timeGetTime();
    g_last_hb_tick = now;
    g_last_frame_tick = now;
    return 0;
}

__declspec(dllexport) int notator_set_fps_15(void *L) {
    (void)L;
    apply_interval_ms(66);
    return 0;
}

__declspec(dllexport) int notator_set_fps_30(void *L) {
    (void)L;
    apply_interval_ms(32);
    return 0;
}

__declspec(dllexport) int notator_set_fps_60(void *L) {
    (void)L;
    apply_interval_ms(16);
    return 0;
}

__declspec(dllexport) int notator_set_fps_90(void *L) {
    (void)L;
    apply_interval_ms(11);
    return 0;
}

__declspec(dllexport) int notator_set_fps_120(void *L) {
    (void)L;
    apply_interval_ms(8);
    return 0;
}

__declspec(dllexport) int notator_set_fps_144(void *L) {
    (void)L;
    apply_interval_ms(7);
    return 0;
}

__declspec(dllexport) int notator_set_fps_uncapped(void *L) {
    (void)L;
    apply_interval_ms(5);
    return 0;
}

__declspec(dllexport) int notator_restore_timer(void *L) {
    (void)L;
    stop_timer_internal();
    return 0;
}
