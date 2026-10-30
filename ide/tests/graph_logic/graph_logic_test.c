#include <assert.h>
#include <stdio.h>
#include "retro_state_machine.h"

int main(void)
{
    retro_sm_init();
    assert(retro_sm_state() == RETRO_STATE_IDLE);

    /* left pressed -> WALK; cooldown is 3 frames. */
    assert(retro_sm_update(0x0200, 0x0200) == RETRO_STATE_WALK);
    assert(retro_sm_tick() == RETRO_STATE_WALK);
    assert(retro_sm_frame() == 1);
    assert(retro_sm_tick() == RETRO_STATE_IDLE); /* WALK duration 2 */

    /* cooldown still has one frame left. */
    assert(retro_sm_update(0x0200, 0x0200) == RETRO_STATE_IDLE);
    assert(retro_sm_tick() == RETRO_STATE_IDLE); /* cooldown reaches 0 */
    assert(retro_sm_update(0x0200, 0x0200) == RETRO_STATE_WALK);

    /* Compound condition: left held + B pressed -> ATTACK. */
    assert(retro_sm_update(0x0200 | 0x8000, 0x8000) == RETRO_STATE_ATTACK);
    assert(retro_sm_tick() == RETRO_STATE_ATTACK);
    assert(retro_sm_tick() == RETRO_STATE_IDLE); /* ATTACK duration 2 */

    /* Let the IDLE->WALK cooldown expire, then run the command sequence. */
    assert(retro_sm_tick() == RETRO_STATE_IDLE);
    assert(retro_sm_update(0x0200, 0x0200) == RETRO_STATE_WALK);
    assert(retro_sm_update(0x0400, 0x0400) == RETRO_STATE_WALK);
    assert(retro_sm_update(0x0100, 0x0100) == RETRO_STATE_WALK);
    assert(retro_sm_update(0x8000, 0x8000) == RETRO_STATE_SPECIAL);

    /* Explicit animation end / forced state. */
    retro_sm_force_state(RETRO_STATE_IDLE);
    assert(retro_sm_animation_end() == RETRO_STATE_IDLE);

    printf("state-graph logic: PASS\n");
    return 0;
}
