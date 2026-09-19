#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Band-keys check surface (SwiftBandKeysCheck.swift): one SgcKeySurface per
// SwiftGridKeyRouter target id. Counts and last-sample queries return -1 when
// the surface is absent (or no sample exists); create/destroy return 1 on
// success, 0 on failure.
// Full bind (sgs_ + sgk_ + sgb_) for the harness-owned private delivery target
// (a scratch router/band pair never attached to input items). The production
// target has no harness surface: the mounted grid owns both its sgb_ and sgk_
// slots once editing binds, and its key ownership is asserted through sgk_
// deliveries instead.
int32_t bandkeys_surface_create_full(uint64_t target_id, uint64_t session_id);
int32_t bandkeys_surface_destroy(uint64_t target_id);
int32_t bandkeys_arrival_count(uint64_t target_id);
int32_t bandkeys_last_verdict(uint64_t target_id);
int32_t bandkeys_last_handled(uint64_t target_id);
int32_t bandkeys_last_command(uint64_t target_id);
int32_t bandkeys_gesture_active(uint64_t target_id);
int32_t bandkeys_cancel_count(uint64_t target_id);
int32_t bandkeys_cancel_at(uint64_t target_id, int32_t index);
int32_t bandkeys_pointer_count(uint64_t target_id);
int32_t bandkeys_last_pointer_kind(uint64_t target_id);
int32_t bandkeys_last_pointer_key(uint64_t target_id);
int32_t bandkeys_last_pointer_button(uint64_t target_id);
int32_t bandkeys_last_pointer_buttons(uint64_t target_id);
int32_t bandkeys_last_pointer_modifiers(uint64_t target_id);
int32_t bandkeys_last_pointer_surface(uint64_t target_id);
double bandkeys_last_pointer_tick(uint64_t target_id);
int32_t bandkeys_wheel_count(uint64_t target_id);
double bandkeys_last_wheel_tick(uint64_t target_id);
int32_t bandkeys_last_wheel_key(uint64_t target_id);
int32_t bandkeys_last_wheel_pixel_delta_x(uint64_t target_id);
int32_t bandkeys_last_wheel_pixel_delta_y(uint64_t target_id);
int32_t bandkeys_last_wheel_angle_delta_x(uint64_t target_id);
int32_t bandkeys_last_wheel_angle_delta_y(uint64_t target_id);
int32_t bandkeys_last_wheel_modifiers(uint64_t target_id);
int32_t bandkeys_last_wheel_surface(uint64_t target_id);
int32_t bandkeys_last_wheel_inverted(uint64_t target_id);
int32_t bandkeys_leave_count(uint64_t target_id);

#ifdef __cplusplus
}
#endif
