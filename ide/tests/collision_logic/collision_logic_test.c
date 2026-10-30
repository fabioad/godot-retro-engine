#include <assert.h>
#include <stdio.h>
#include "retro_collision.h"

int main(void)
{
    RetroFighter a, b;
    RetroHitResult r;
    retro_col_init(&a);
    retro_col_init(&b);
    a.state = 4; /* ATTACK */
    a.frame = 0;
    a.x = 0;
    b.state = 4; /* ATTACK frame also carries a hurtbox */
    b.frame = 0;
    b.x = 10;
    assert(retro_col_check(&a, &b, &r) == 1);
    assert(r.contact == 1 && r.hit == 1 && r.blocked == 0);
    assert(r.damage == 12);
    retro_col_apply(&a, &b, &r);
    assert(a.hitstop == 5);
    assert(b.hitstop == 9);
    assert(b.invuln == 10);
    assert(b.health == 88);
    assert(b.last_hit_id == 7);
    assert(b.x == 14); /* pushback away from the attacker */
    retro_col_tick(&a);
    retro_col_tick(&b);
    assert(a.hitstop == 4 && b.invuln == 9);
    assert(retro_col_check(&a, &b, &r) == 0); /* still invulnerable */

    /* The same HitDef ID cannot hit again. */
    b.invuln = 0;
    assert(retro_col_check(&a, &b, &r) == 0);
    b.last_hit_id = 0;

    /* BLOCK state is inferred without the caller setting blocking. */
    b.state = 6; /* BLOCK */
    b.blocking = 0;
    assert(retro_col_check(&a, &b, &r) == 1);
    assert(r.contact == 1 && r.blocked == 1 && r.hit == 0 && r.damage == 0);
    retro_col_apply(&a, &b, &r);
    assert(b.hitstop == 7);
    printf("collision runtime: PASS\n");
    return 0;
}
