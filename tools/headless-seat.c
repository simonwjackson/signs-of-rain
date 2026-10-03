/* Optional headless testing only. See headless-seat.py --help for the protocol. */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <limits.h>
#include <linux/input-event-codes.h>
#include <math.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "virtual-keyboard-unstable-v1-client-protocol.h"
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct wl_display *display;
static struct wl_registry *registry;
static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *manager;
static struct zwp_virtual_keyboard_v1 *keyboard;
static struct zwlr_virtual_pointer_manager_v1 *pointer_manager;
static struct zwlr_virtual_pointer_v1 *pointer;
static bool held_keys[KEY_MAX + 1];
static bool held_buttons[3];
static uint32_t shift_mask;

static int fail(const char *message) {
    fprintf(stderr, "headless-seat: %s\n", message);
    return -1;
}

static int64_t milliseconds(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) < 0) {
        perror("clock_gettime");
        exit(EXIT_FAILURE);
    }
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static int pause_ms(unsigned int ms) {
    struct timespec delay = {.tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000L};
    while (nanosleep(&delay, &delay) < 0)
        if (errno != EINTR) return fail("nanosleep failed");
    return 0;
}

static void synced(void *data, struct wl_callback *callback, uint32_t serial) {
    (void)callback;
    (void)serial;
    *(bool *)data = true;
}
static const struct wl_callback_listener sync_listener = {.done = synced};

/* A stalled compositor must not leave a command or cleanup blocked forever. */
static int roundtrip(void) {
    bool done = false;
    int result = -1;
    struct wl_callback *callback = wl_display_sync(display);
    if (!callback) return fail("cannot create display sync");
    if (wl_callback_add_listener(callback, &sync_listener, &done) < 0) goto finished;
    int64_t deadline = milliseconds() + 5000;
    while (!done) {
        if (wl_display_dispatch_pending(display) < 0) goto finished;
        if (done) break;
        if (milliseconds() >= deadline) goto finished;
        if (wl_display_prepare_read(display) < 0) continue;
        struct pollfd fd = {.fd = wl_display_get_fd(display), .events = POLLIN};
        if (wl_display_flush(display) < 0) {
            if (errno != EAGAIN) {
                wl_display_cancel_read(display);
                goto finished;
            }
            fd.events |= POLLOUT;
        }
        int64_t remaining = deadline - milliseconds();
        int ready = poll(&fd, 1, remaining > 0 ? (int)remaining : 0);
        if (ready < 0 && errno == EINTR) {
            wl_display_cancel_read(display);
            continue;
        }
        if (ready <= 0 || (fd.revents & (POLLERR | POLLHUP | POLLNVAL))) {
            wl_display_cancel_read(display);
            goto finished;
        }
        if (fd.revents & POLLIN) {
            if (wl_display_read_events(display) < 0) goto finished;
        } else {
            wl_display_cancel_read(display);
        }
    }
    result = 0;
finished:
    wl_callback_destroy(callback);
    return result ? fail("Wayland sync failed or exceeded 5000 ms") : 0;
}

static void global(void *data, struct wl_registry *reg, uint32_t name,
                   const char *interface, uint32_t version) {
    (void)data;
    if (!seat && !strcmp(interface, "wl_seat"))
        seat = wl_registry_bind(reg, name, &wl_seat_interface, version < 7 ? version : 7);
    if (!manager && !strcmp(interface, "zwp_virtual_keyboard_manager_v1"))
        manager = wl_registry_bind(reg, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
    if (!pointer_manager && !strcmp(interface, "zwlr_virtual_pointer_manager_v1"))
        pointer_manager = wl_registry_bind(reg, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}
static void removed(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data; (void)reg; (void)name;
}
static const struct wl_registry_listener registry_listener = {global, removed};

static int key_state(unsigned int code, bool pressed, uint32_t modifiers) {
    zwp_virtual_keyboard_v1_key(keyboard, (uint32_t)milliseconds(), code, pressed);
    zwp_virtual_keyboard_v1_modifiers(keyboard, modifiers, 0, 0, 0);
    held_keys[code] = pressed;
    return roundtrip() < 0 ? -1 : pause_ms(150);
}

static int tap(unsigned int code, uint32_t modifiers) {
    return key_state(code, true, modifiers) < 0 ? -1 : key_state(code, false, 0);
}

static int button_state(unsigned int button, bool pressed) {
    zwlr_virtual_pointer_v1_button(pointer, (uint32_t)milliseconds(), BTN_LEFT + button, pressed);
    zwlr_virtual_pointer_v1_frame(pointer);
    held_buttons[button] = pressed;
    return roundtrip() < 0 ? -1 : pause_ms(150);
}

static unsigned int code_for(char value) {
    const char *rows[] = {"1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"};
    const unsigned int starts[] = {2, 16, 30, 44};
    for (unsigned int row = 0; row < 4; ++row) {
        const char *match = strchr(rows[row], value);
        if (value && match) return starts[row] + (unsigned int)(match - rows[row]);
    }
    return 0;
}

static bool integer(const char *text, unsigned int maximum, unsigned int *value) {
    if (!text || !*text) return false;
    for (const char *p = text; *p; ++p)
        if (*p < '0' || *p > '9') return false;
    errno = 0;
    char *end;
    unsigned long number = strtoul(text, &end, 10);
    if (errno || *end || number > maximum) return false;
    *value = (unsigned int)number;
    return true;
}

static bool coordinate(const char *text, double *value) {
    if (!text || !*text) return false;
    errno = 0;
    char *end;
    *value = strtod(text, &end);
    return !errno && !*end && isfinite(*value) && *value >= -8388607 && *value <= 8388607;
}

/* Parse the entire line before emitting anything, including for name/type. */
static int command(char *line, bool check_only) {
    char *save = NULL;
    char *action = strtok_r(line, " \t\r", &save);
    char *a = strtok_r(NULL, " \t\r", &save);
    char *b = strtok_r(NULL, " \t\r", &save);
    char *extra = strtok_r(NULL, " \t\r", &save);
    if (!action || extra) return fail("empty command or too many arguments");
    if (!strcmp(action, "quit")) return a ? fail("quit takes no arguments") : 1;
    if (!a) return fail("command requires arguments");
    unsigned int value = 0;
    double x = 0, y = 0;
    enum { KEY, MOVE, SCROLL, DOWN, UP, CLICK, WAIT, TYPE, NAME } kind;
    if (!strcmp(action, "move")) {
        kind = MOVE;
        if (!coordinate(a, &x) || !coordinate(b, &y))
            return fail("move requires two finite numbers within +/-8388607");
    } else {
        if (b) return fail("unexpected extra argument");
        if (!strcmp(action, "key")) {
            kind = KEY;
            if (!integer(a, KEY_MAX, &value) || !value) return fail("key requires decimal 1..767");
        } else if (!strcmp(action, "scroll")) {
            kind = SCROLL;
            if (!coordinate(a, &x) || x < -32 || x > 32 || x == 0 || x != (int)x)
                return fail("scroll requires a nonzero whole number within +/-32");
        } else if (!strcmp(action, "wait")) {
            kind = WAIT;
            if (!integer(a, 10000, &value)) return fail("wait requires decimal 0..10000");
        } else if (!strcmp(action, "down") || !strcmp(action, "up") || !strcmp(action, "click")) {
            kind = !strcmp(action, "down") ? DOWN : !strcmp(action, "up") ? UP : CLICK;
            if (!strcmp(a, "left")) value = 0;
            else if (!strcmp(a, "right")) value = 1;
            else if (!strcmp(a, "middle")) value = 2;
            else return fail("button must be left, right, or middle");
        } else if (!strcmp(action, "type") || !strcmp(action, "name")) {
            kind = !strcmp(action, "type") ? TYPE : NAME;
            for (const char *p = a; *p; ++p)
                if (!code_for(*p)) return fail("text requires lowercase ASCII letters/digits");
        } else return fail("unknown command");
    }
    if (!check_only) {
        switch (kind) {
        case KEY:
            if (tap(value, value == KEY_LEFTSHIFT || value == KEY_RIGHTSHIFT ? shift_mask : 0) < 0) return -1;
            break;
        case MOVE:
            zwlr_virtual_pointer_v1_motion(pointer, (uint32_t)milliseconds(), wl_fixed_from_double(x), wl_fixed_from_double(y));
            zwlr_virtual_pointer_v1_frame(pointer);
            if (roundtrip() < 0 || pause_ms(150) < 0) return -1;
            break;
        case SCROLL:
            zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
            zwlr_virtual_pointer_v1_axis_discrete(pointer, (uint32_t)milliseconds(), WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_double(x * 10), (int)x);
            zwlr_virtual_pointer_v1_frame(pointer);
            if (roundtrip() < 0 || pause_ms(150) < 0) return -1;
            break;
        case DOWN: case UP: case CLICK:
            if (button_state(value, kind != UP) < 0) return -1;
            if (kind == CLICK && button_state(value, false) < 0) return -1;
            break;
        case WAIT:
            if (pause_ms(value) < 0) return -1;
            break;
        case NAME:
            /* Preserve the original helper's BW2 name-field clearing sequence. */
            for (unsigned int i = 0; i < 24; ++i)
                if (tap(KEY_BACKSPACE, 0) < 0) return -1;
            /* fall through */
        case TYPE:
            for (const char *p = a; *p; ++p)
                if (tap(code_for(*p), 0) < 0) return -1;
            break;
        }
    }
    printf("INPUT_DONE %s\n", action);
    return fflush(stdout) == EOF ? fail("stdout write failed") : 0;
}

static int setup(void) {
    display = wl_display_connect(NULL);
    if (!display) return fail("cannot connect to WAYLAND_DISPLAY");
    registry = wl_display_get_registry(display);
    if (!registry || wl_registry_add_listener(registry, &registry_listener, NULL) < 0)
        return fail("cannot listen to registry");
    if (roundtrip() < 0) return -1;
    if (!seat || !manager || !pointer_manager) return fail("seat and virtual keyboard/pointer protocols are required");
    keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager, seat);
    pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(pointer_manager, seat);
    if (!keyboard || !pointer) return fail("cannot create virtual input devices");
    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (!context) return fail("cannot create XKB context");
    const struct xkb_rule_names names = {
        .rules = "evdev", .model = "pc105", .layout = "us", .variant = "", .options = ""
    };
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    char *text = keymap ? xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1) : NULL;
    FILE *file = NULL;
    int result = -1;
    if (!text) { fail("cannot compile full US keymap"); goto finished; }
    xkb_mod_index_t shift = xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_SHIFT);
    if (shift >= 32) { fail("missing US Shift modifier"); goto finished; }
    shift_mask = 1u << shift;
    size_t size = strlen(text) + 1;
    file = tmpfile();
    if (!file || size > UINT32_MAX || fwrite(text, 1, size, file) != size || fflush(file) == EOF) {
        fail("cannot write temporary keymap"); goto finished;
    }
    zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fileno(file), (uint32_t)size);
    zwp_virtual_keyboard_v1_modifiers(keyboard, 0, 0, 0, 0);
    if (roundtrip() < 0 || pause_ms(150) < 0 || tap(KEY_LEFTSHIFT, shift_mask) < 0) goto finished;
    printf("FIXED_US_KEYMAP %zu bytes\n", size);
    result = 0;
finished:
    if (file && fclose(file) == EOF) result = fail("keymap close failed");
    free(text);
    if (keymap) xkb_keymap_unref(keymap);
    xkb_context_unref(context);
    return result;
}

static int cleanup(void) {
    if (!display) return 0;
    if (keyboard) {
        for (unsigned int i = 1; i <= KEY_MAX; ++i)
            if (held_keys[i]) zwp_virtual_keyboard_v1_key(keyboard, (uint32_t)milliseconds(), i, 0);
        zwp_virtual_keyboard_v1_modifiers(keyboard, 0, 0, 0, 0);
    }
    if (pointer) {
        for (unsigned int i = 0; i < 3; ++i)
            if (held_buttons[i]) zwlr_virtual_pointer_v1_button(pointer, (uint32_t)milliseconds(), BTN_LEFT + i, 0);
        zwlr_virtual_pointer_v1_frame(pointer);
    }
    int result = roundtrip();
    if (pointer) zwlr_virtual_pointer_v1_destroy(pointer);
    if (keyboard) zwp_virtual_keyboard_v1_destroy(keyboard);
    if (pointer_manager) zwlr_virtual_pointer_manager_v1_destroy(pointer_manager);
    if (manager) zwp_virtual_keyboard_manager_v1_destroy(manager);
    if (seat) wl_seat_destroy(seat);
    if (registry) wl_registry_destroy(registry);
    if (!result) result = roundtrip();
    wl_display_disconnect(display);
    return result;
}

static int serve(bool check_only) {
    puts(check_only ? "COMMAND_CHECK_READY" : "US_SEAT_READY");
    if (fflush(stdout) == EOF) return fail("stdout write failed");
    for (;;) {
        char line[256];
        size_t length = 0;
        int c;
        while ((c = fgetc(stdin)) != EOF && c != '\n') {
            if (!c || length == sizeof(line) - 1) return fail("NUL byte or line exceeds 255 bytes");
            line[length++] = (char)c;
        }
        if (ferror(stdin)) return fail("stdin read failed");
        if (c == EOF && !length) return 0;
        line[length] = '\0';
        int result = command(line, check_only);
        if (result) return result < 0 ? -1 : 0;
    }
}

int main(int argc, char **argv) {
    bool check_only = argc == 2 && !strcmp(argv[1], "--check-commands");
    if (argc != 1 && !check_only) return fail("usage: headless-seat [--check-commands]"), EXIT_FAILURE;
    int result = check_only ? 0 : setup();
    if (!result) result = serve(check_only);
    if (cleanup() < 0) result = -1;
    return result ? EXIT_FAILURE : EXIT_SUCCESS;
}
