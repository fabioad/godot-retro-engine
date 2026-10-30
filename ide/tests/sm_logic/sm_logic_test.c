#include <assert.h>
#include <stdio.h>
#include "retro_state_machine.h"

int main(void)
{
    retro_sm_init();
    assert(retro_sm_state() == RETRO_STATE_IDLE);

    /* Press-type action: only a pressed bit triggers it. */
    assert(retro_sm_update(KEY_LEFT, 0) == RETRO_STATE_IDLE);
    assert(retro_sm_update(KEY_LEFT, KEY_LEFT) == RETRO_STATE_WALK);
    assert(retro_sm_update(0, 0) == RETRO_STATE_WALK);

    /* Attack A maps to ATTACK. */
    assert(retro_sm_update(KEY_B, KEY_B) == RETRO_STATE_ATTACK);
    assert(retro_sm_update(0, 0) == RETRO_STATE_ATTACK);

    /* Hold combo has higher priority and a next-state transition. */
    assert(retro_sm_update(KEY_R | KEY_X, 0) == RETRO_STATE_SUPER);
    assert(retro_sm_update(KEY_R | KEY_X, KEY_B) == RETRO_STATE_SUPER);
    assert(retro_sm_frame() == 0);
    assert(retro_sm_tick() == RETRO_STATE_SUPER);
    assert(retro_sm_frame() == 1);
    assert(retro_sm_tick() == RETRO_STATE_IDLE);
    assert(retro_sm_frame() == 0);

    /* Explicit animation-end still works. */
    assert(retro_sm_update(KEY_R | KEY_X, 0) == RETRO_STATE_SUPER);
    assert(retro_sm_animation_end() == RETRO_STATE_IDLE);

    retro_sm_force_state(RETRO_STATE_BLOCK);
    assert(retro_sm_state() == RETRO_STATE_BLOCK);

    printf("state-machine logic: PASS\n");
    return 0;
}
