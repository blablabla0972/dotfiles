#define _GNU_SOURCE
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "ext-image-capture-source.h"
#include "ext-image-copy-capture.h"
#include "ext-workspace.h"
#include "hyprland-workspace-image-capture-source.h"

struct capture {
    const char *name;
    struct ext_workspace_handle_v1 *workspace;
    struct ext_image_copy_capture_manager_v1 *copy;
    struct hyprland_workspace_image_capture_source_manager_v1 *source_manager;
    struct wl_shm *shm;
    uint32_t width, height, format, transform;
    bool ambiguous, has_format, constraints, ready, failed;
};

static int workspace_event(const void *impl, void *target, uint32_t opcode,
                           const struct wl_message *message, union wl_argument *args) {
    (void)opcode;
    struct capture *c = (struct capture *)impl;
    if (!strcmp(message->name, "name") && !strcmp(args[0].s, c->name)) {
        c->ambiguous |= c->workspace && (void *)c->workspace != target;
        c->workspace = target;
    }
    if (!strcmp(message->name, "removed") && (void *)c->workspace == target)
        c->failed = true;
    return 0;
}

static int manager_event(const void *impl, void *target, uint32_t opcode,
                         const struct wl_message *message, union wl_argument *args) {
    (void)target;
    (void)opcode;
    if (!strcmp(message->name, "workspace"))
        wl_proxy_add_dispatcher((struct wl_proxy *)args[0].o, workspace_event, impl, NULL);
    return 0;
}

static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    (void)version;
    struct capture *c = data;
    if (!strcmp(interface, ext_workspace_manager_v1_interface.name)) {
        struct wl_proxy *manager = wl_registry_bind(registry, name, &ext_workspace_manager_v1_interface, 1);
        wl_proxy_add_dispatcher(manager, manager_event, c, NULL);
    } else if (!strcmp(interface, ext_image_copy_capture_manager_v1_interface.name)) {
        c->copy = wl_registry_bind(registry, name, &ext_image_copy_capture_manager_v1_interface, 1);
    } else if (!strcmp(interface, hyprland_workspace_image_capture_source_manager_v1_interface.name)) {
        c->source_manager = wl_registry_bind(registry, name, &hyprland_workspace_image_capture_source_manager_v1_interface, 1);
    } else if (!strcmp(interface, wl_shm_interface.name)) {
        c->shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    }
}

static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static int session_event(const void *impl, void *target, uint32_t opcode,
                         const struct wl_message *message, union wl_argument *args) {
    (void)target;
    (void)opcode;
    struct capture *c = (struct capture *)impl;
    if (!strcmp(message->name, "buffer_size")) {
        c->width = args[0].u;
        c->height = args[1].u;
    } else if (!strcmp(message->name, "shm_format")) {
        if (args[0].u == WL_SHM_FORMAT_XRGB8888 || args[0].u == WL_SHM_FORMAT_ARGB8888) {
            c->format = args[0].u;
            c->has_format = true;
        }
    } else if (!strcmp(message->name, "done")) {
        c->constraints = true;
    } else if (!strcmp(message->name, "stopped")) {
        c->failed = true;
    }
    return 0;
}

static int frame_event(const void *impl, void *target, uint32_t opcode,
                       const struct wl_message *message, union wl_argument *args) {
    (void)target;
    (void)opcode;
    struct capture *c = (struct capture *)impl;
    if (!strcmp(message->name, "ready"))
        c->ready = true;
    else if (!strcmp(message->name, "failed"))
        c->failed = true;
    else if (!strcmp(message->name, "transform"))
        c->transform = args[0].u;
    return 0;
}

static void emit_frame(const uint32_t *pixels, unsigned width, unsigned height) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const unsigned largest = width > height ? width : height;
    const unsigned scaled = largest < 320 ? largest : 320;
    const unsigned out_width = (width * scaled / largest) ? width * scaled / largest : 1;
    const unsigned out_height = (height * scaled / largest) ? height * scaled / largest : 1;
    unsigned char rgb[64 + 320 * 320 * 3];
    const size_t head = snprintf((char *)rgb, 64, "P6\n%u %u\n255\n", out_width, out_height);
    size_t length = head;
    for (unsigned y = 0; y < out_height; ++y) {
        for (unsigned x = 0; x < out_width; ++x) {
            const uint32_t color = pixels[(y * height / out_height) * width + x * width / out_width];
            rgb[length++] = color >> 16;
            rgb[length++] = color >> 8;
            rgb[length++] = color;
        }
    }
    for (size_t i = 0; i < length; i += 3) {
        const unsigned bits = (unsigned)rgb[i] << 16 |
            (i + 1 < length ? (unsigned)rgb[i + 1] << 8 : 0) |
            (i + 2 < length ? rgb[i + 2] : 0);
        putchar(alphabet[bits >> 18]);
        putchar(alphabet[bits >> 12 & 63]);
        putchar(i + 1 < length ? alphabet[bits >> 6 & 63] : '=');
        putchar(i + 2 < length ? alphabet[bits & 63] : '=');
    }
    putchar('\n');
    fflush(stdout);
}

int main(int argc, char **argv) {
    if (argc != 2)
        return 2;
    struct capture c = {.name = argv[1]};
    struct wl_display *display = wl_display_connect(NULL);
    if (!display)
        return 1;
    struct wl_registry *registry = wl_display_get_registry(display);
    const struct wl_registry_listener listener = {.global = global, .global_remove = global_remove};
    wl_registry_add_listener(registry, &listener, &c);
    if (wl_display_roundtrip(display) < 0 || wl_display_roundtrip(display) < 0 ||
        !c.workspace || c.ambiguous || c.failed || !c.copy || !c.source_manager || !c.shm) {
        fputs("Workspace capture source unavailable\n", stderr);
        return 1;
    }
    struct ext_image_capture_source_v1 *source =
        hyprland_workspace_image_capture_source_manager_v1_create_source(
            c.source_manager, c.workspace, HYPRLAND_WORKSPACE_IMAGE_CAPTURE_SOURCE_MANAGER_V1_CAPTURE_MODE_EVERYTHING);
    struct ext_image_copy_capture_session_v1 *session = ext_image_copy_capture_manager_v1_create_session(c.copy, source, 0);
    wl_proxy_add_dispatcher((struct wl_proxy *)session, session_event, &c, NULL);
    while (!c.constraints && !c.failed && wl_display_dispatch(display) >= 0) {}
    if (c.failed || !c.constraints || !c.has_format || !c.width || !c.height || c.width > 8192 || c.height > 8192) {
        fputs("Workspace capture has no supported buffer format\n", stderr);
        return 1;
    }
    const unsigned width = c.width, height = c.height;
    const size_t bytes = (size_t)width * height * 4;
    const int fd = memfd_create("cod29-workspace", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, (off_t)bytes) < 0)
        return 1;
    uint32_t *pixels = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED)
        return 1;
    struct wl_shm_pool *pool = wl_shm_create_pool(c.shm, fd, (int)bytes);
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, width * 4, c.format);
    wl_shm_pool_destroy(pool);
    close(fd);

    while (!c.failed && c.width == width && c.height == height) {
        struct ext_image_copy_capture_frame_v1 *frame = ext_image_copy_capture_session_v1_create_frame(session);
        wl_proxy_add_dispatcher((struct wl_proxy *)frame, frame_event, &c, NULL);
        ext_image_copy_capture_frame_v1_attach_buffer(frame, buffer);
        ext_image_copy_capture_frame_v1_damage_buffer(frame, 0, 0, width, height);
        c.ready = false;
        c.transform = WL_OUTPUT_TRANSFORM_NORMAL;
        ext_image_copy_capture_frame_v1_capture(frame);
        while (!c.ready && !c.failed && wl_display_dispatch(display) >= 0) {}
        ext_image_copy_capture_frame_v1_destroy(frame);
        if (c.failed || !c.ready || c.transform != WL_OUTPUT_TRANSFORM_NORMAL)
            break;
        emit_frame(pixels, width, height);
        const struct timespec interval = {.tv_nsec = 50000000};
        nanosleep(&interval, NULL);
    }
    munmap(pixels, bytes);
    wl_display_disconnect(display);
    return 1;
}
