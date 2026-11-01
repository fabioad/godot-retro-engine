/* Gothicvania - Mega Drive port (SGDK)
 *
 * Source-level port of the SNES/PVSnesLib game.  The original C physics,
 * collision, enemy AI and state machine are preserved; the SNES-specific
 * renderer (3 BGs + HDMA colour math + 64x64 OBJs) is translated to the Mega
 * Drive VDP (2 planes + hardware sprites).
 */
#include <genesis.h>
#include "assets.h"

#define LEVEL_COLS   300
#define LEVEL_ROWS   14
#define LEVEL_PAGES  19
#define PAGE_W       32
#define PAGE_H       32
#define PAGE_TILES   288

#define VRAM_LEVEL0  128
#define VRAM_LEVEL1  (VRAM_LEVEL0 + PAGE_TILES)
#define VRAM_BG      (VRAM_LEVEL1 + PAGE_TILES)
/* bg_tiles has 380 tiles; keep the hero band 16-tile aligned. */
#define VRAM_HERO    (VRAM_BG + ((sizeof(bg_tiles) / 32 + 15) & ~15))
#define VRAM_ENEMY0  (VRAM_HERO + 128)
#define VRAM_ENEMY1  (VRAM_ENEMY0 + 128)

#define PAL_LEVEL    0
#define PAL_BG       1
#define PAL_HERO     2
#define PAL_ENEMY    3

#define CAM_MAX      (4800 - 256)
#define HALF_W       6
#define BODY_HI      24
#define BODY_LO      4
#define HERO_FEET_Y  52
#define HERO_LEFT_DX 64

#define PLAYER_HP    3
#define ENEMY_SLOTS  2
#define SK_DEATH_F   14
#define SK_DEATH_N   5
#define SK_RISE_F    0
#define SK_RISE_N    6
#define SK_WALK_F    6
#define SK_WALK_N    8
#define GATO_WALK_F  0
#define GATO_WALK_N  4
#define GHOST_FLOAT_F 0
#define GHOST_FLOAT_N 4

#define A_IDLE_F 0
#define A_IDLE_N 4
#define A_RUN_F  4
#define A_RUN_N  6
#define A_JUMP_F 10
#define A_JUMP_N 4
#define A_CROUCH_F 14
#define A_CROUCH_N 1
#define A_ATTACK_F 15
#define A_ATTACK_N 5
#define A_HURT_F 20
#define A_HURT_N 1

#define JUMP_KEYS   (BUTTON_A | BUTTON_B)
#define ATTACK_KEYS (BUTTON_C)

typedef enum { ST_TITLE, ST_PLAY, ST_END, ST_GAMEOVER } GameState;

static u8 attackTimer, hurtFlag, hurtDir, spikeCD;
static u16 playPrevPad;
static u8 animFrame, lastAnimF;
static u16 animTimer;

static const Image *pageImgs[LEVEL_PAGES] = {
    &page00, &page01, &page02, &page03, &page04, &page05, &page06,
    &page07, &page08, &page09, &page10, &page11, &page12, &page13,
    &page14, &page15, &page16, &page17, &page18
};

static s32 feetX, feetY;
static s16 vx, vy;
static u16 camX;
static u8 onGround, facing, health;
static u16 jumpDir;

static u16 lastPage;
static s16 loadedPage[2] = { -1, -1 };

static u8 heroGfx = 0, heroUploaded = 0xFF;
static u8 heroDirty = 1;

/* ---- level pages ------------------------------------------------------- */

static void loadPageNow(u16 page, u16 slot)
{
    if (page >= LEVEL_PAGES) {
        VDP_clearTileMapRect(BG_A, slot * 32, 0, 32, 32);
        return;
    }
    VDP_drawImageEx(BG_A, pageImgs[page],
        TILE_ATTR_FULL(PAL_LEVEL, 1, 0, 0, VRAM_LEVEL0 + slot * PAGE_TILES),
        slot * 32, 0, FALSE, CPU);
}

static void ensurePage(u16 page)
{
    u16 slot;
    if (page >= LEVEL_PAGES) return;
    slot = page & 1;
    if (loadedPage[slot] == (s16)page) return;
    loadPageNow(page, slot);
    loadedPage[slot] = page;
}

/* ---- sprites ----------------------------------------------------------- */

static void setSpr(u16 idx, s16 x, s16 y, u16 tile, u8 pal, u8 hf, u8 vf, u8 link)
{
    VDP_setSpriteFull(idx, x, y, SPRITE_SIZE(4, 4),
        TILE_ATTR_FULL(pal, 1, vf, hf, tile), link);
}

static void hideSprRange(u16 first, u16 count)
{
    u16 i;
    for (i = 0; i < count; i++)
        setSpr(first + i, -64, -64, 0, PAL_HERO, 0, 0, 0);
}

static void linkSprites(void)
{
    u16 i;
    for (i = 0; i < 23; i++) VDP_setSpriteLink(i, i + 1);
    VDP_setSpriteLink(23, 0);
}

static void drawHero(void)
{
    s16 sx = (s16)(feetX >> 8) - (s16)camX - HERO_LEFT_DX;
    s16 sy = (s16)(feetY >> 8) - HERO_FEET_Y;
    u16 i = 0;
    u8 qx, qy;
    for (qy = 0; qy < 2; qy++) {
        for (qx = 0; qx < 4; qx++) {
            u8 srcq = facing ? (3 - qx) : qx;
            setSpr(i, sx + qx * 32, sy + qy * 32,
                VRAM_HERO + (qy * 4 + srcq) * 16, PAL_HERO, facing, 0,
                (i < 7) ? (i + 1) : 0);
            i++;
        }
    }
}

/* ---- enemies (ported from src/enemy.c) --------------------------------- */

#define ET_SKEL  0
#define ET_GATO  1
#define ET_GHOST 2
#define EN_RISE  1
#define EN_WALK  2
#define EN_DYING 3

typedef struct {
    u8 active, type, state, frame, uploaded, timer, facing, wsub;
    s16 wx, wy, baseY;
    u16 aux;
} Enemy;

static Enemy en[ENEMY_SLOTS];
static u8 upSlot = 255;
static const u8 *upSrc;

static const u16 spawnTx[] = {
    10, 17, 80, 147, 162, 200, 210, 244, 254, 270,
    53, 86, 147, 201, 111, 173, 220, 263, 284
};
static const u8 spawnTy[] = {
    12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
    11, 11, 11, 11, 7, 6, 7, 7, 7
};
static const u8 spawnType[] = {
    ET_SKEL, ET_SKEL, ET_SKEL, ET_SKEL, ET_SKEL, ET_SKEL, ET_SKEL, ET_SKEL, ET_SKEL, ET_SKEL,
    ET_GATO, ET_GATO, ET_GATO, ET_GATO,
    ET_GHOST, ET_GHOST, ET_GHOST, ET_GHOST, ET_GHOST
};
#define N_SPAWN (sizeof(spawnTx) / sizeof(spawnTx[0]))
static u8 spawned[N_SPAWN];

static const u8 enemyHalfW[3] = { 22, 38, 14 };
static s16 SKEL_WALK_SPD, GATO_SPD, GHOST_BOB_SPD;
static u16 GATO_TURN;

static u8 cellv(s16 col, s16 row)
{
    if (col < 0 || col >= LEVEL_COLS || row >= LEVEL_ROWS) return 1;
    if (row < 0) return 0;
    return level_collision[row * LEVEL_COLS + col];
}

static const u8 *skeletonFrameSrc(u8 f)
{
    return enemy_frames + (u32)f * 4096;
}

static const u8 *enemyBandSrc(u8 i)
{
    if (en[i].state == EN_DYING) return skeletonFrameSrc(en[i].frame);
    if (en[i].type == ET_GATO) return enemy_frames + (u32)(19 + en[i].frame) * 4096;
    if (en[i].type == ET_GHOST) return enemy_frames + (u32)(23 + en[i].frame) * 4096;
    return skeletonFrameSrc(en[i].frame);
}

static s8 freeSlot(void)
{
    u8 i;
    for (i = 0; i < ENEMY_SLOTS; i++) if (!en[i].active) return (s8)i;
    return -1;
}

static void hideEnemy(u8 i)
{
    hideSprRange(8 + i * 8, 8);
}

static void spawnEnemy(u8 slot, u8 n)
{
    en[slot].active = 1;
    en[slot].type = spawnType[n];
    en[slot].uploaded = 255;
    en[slot].timer = 0;
    en[slot].wsub = 0;
    en[slot].aux = 0;
    en[slot].wx = (s16)(spawnTx[n] * 16 + 8);
    if (en[slot].type == ET_SKEL) {
        en[slot].state = EN_RISE;
        en[slot].frame = SK_RISE_F;
        en[slot].facing = 1;
        en[slot].wy = 192;
        XGM2_playPCM(sfx_rise, sizeof(sfx_rise), SOUND_PCM_CH2);
    } else if (en[slot].type == ET_GATO) {
        en[slot].state = EN_WALK;
        en[slot].frame = GATO_WALK_F;
        en[slot].facing = 0;
        en[slot].wy = 192;
        en[slot].aux = GATO_TURN;
    } else {
        en[slot].state = EN_WALK;
        en[slot].frame = GHOST_FLOAT_F;
        en[slot].facing = 0;
        en[slot].baseY = (s16)(spawnTy[n] * 16);
        en[slot].wy = en[slot].baseY;
    }
}

static void enemyInit(void)
{
    u8 i;
    for (i = 0; i < ENEMY_SLOTS; i++) {
        en[i].active = 0;
        hideEnemy(i);
    }
    for (i = 0; i < N_SPAWN; i++) spawned[i] = 0;
    upSlot = 255;
    SKEL_WALK_SPD = 128;
    GATO_SPD = 384;
    GHOST_BOB_SPD = 213;
    GATO_TURN = 200;
}

static void enemyUpdate(void)
{
    s16 px = (s16)(feetX >> 8);
    s16 ptile = px >> 4;
    u8 i;

    for (i = 0; i < N_SPAWN; i++) {
        s16 d;
        if (spawned[i]) continue;
        d = (s16)spawnTx[i] - ptile;
        if (d < 0) d = -d;
        if (d <= 8) {
            s8 slot = freeSlot();
            if (slot >= 0) {
                spawnEnemy((u8)slot, i);
                spawned[i] = 1;
            }
        }
    }

    for (i = 0; i < ENEMY_SLOTS; i++) {
        s16 ex, dx;
        if (!en[i].active) continue;

        if (en[i].state == EN_DYING) {
            if (++en[i].timer >= 6) {
                u8 rel = (u8)(en[i].frame - SK_DEATH_F + 1);
                en[i].timer = 0;
                if (rel >= SK_DEATH_N) { en[i].active = 0; hideEnemy(i); }
                else en[i].frame = (u8)(SK_DEATH_F + rel);
            }
            continue;
        }

        ex = en[i].wx;
        dx = ex - px;
        if (dx < 0) dx = -dx;
        if (dx > 200) { en[i].active = 0; hideEnemy(i); continue; }

        if (en[i].type == ET_SKEL) {
            if (en[i].state == EN_RISE) {
                if (++en[i].timer >= 6) {
                    u8 rel = (u8)(en[i].frame - SK_RISE_F + 1);
                    en[i].timer = 0;
                    if (rel >= SK_RISE_N) {
                        en[i].state = EN_WALK;
                        en[i].frame = SK_WALK_F;
                    } else en[i].frame = (u8)(SK_RISE_F + rel);
                }
            } else {
                en[i].facing = (px < ex) ? 0 : 1;
                if (dx > 10) {
                    u16 t = (u16)en[i].wsub + (u16)SKEL_WALK_SPD;
                    if (t > 0xFF) en[i].wx += (px < ex) ? -1 : 1;
                    en[i].wsub = (u8)t;
                }
                if (++en[i].timer >= 6) {
                    en[i].timer = 0;
                    en[i].frame = (u8)(SK_WALK_F + ((en[i].frame - SK_WALK_F + 1) & (SK_WALK_N - 1)));
                }
            }
        } else if (en[i].type == ET_GATO) {
            s16 dir = en[i].facing ? 1 : -1;
            s16 aheadCol = (en[i].wx + dir * 36) >> 4;
            if (en[i].aux == 0 ||
                cellv(aheadCol, 11) == 1 ||
                cellv(aheadCol, 12) != 1) {
                en[i].facing ^= 1;
                dir = -dir;
                en[i].aux = GATO_TURN;
            } else en[i].aux--;
            {
                u16 t = (u16)en[i].wsub + (u16)GATO_SPD;
                if (t > 0xFF) en[i].wx += dir;
                en[i].wsub = (u8)t;
            }
            if (++en[i].timer >= 6) {
                en[i].timer = 0;
                en[i].frame = (u8)(GATO_WALK_F + ((en[i].frame - GATO_WALK_F + 1) & (GATO_WALK_N - 1)));
            }
        } else {
            en[i].facing = (px < ex) ? 1 : 0;
            {
                u16 t = (u16)en[i].wsub + (u16)GHOST_BOB_SPD;
                if (t > 0xFF) en[i].wy += (en[i].aux & 1) ? -1 : 1;
                en[i].wsub = (u8)t;
            }
            if (en[i].wy >= en[i].baseY + 50) en[i].aux |= 1;
            else if (en[i].wy <= en[i].baseY) en[i].aux &= (u16)~1u;
            if (++en[i].timer >= 8) {
                en[i].timer = 0;
                en[i].frame = (u8)(GHOST_FLOAT_F + ((en[i].frame - GHOST_FLOAT_F + 1) & (GHOST_FLOAT_N - 1)));
            }
        }
    }
}

static s8 enemyCombat(u8 attacking, u8 invuln)
{
    s16 px = (s16)(feetX >> 8), py = (s16)(feetY >> 8);
    s8 hurt = 0;
    u8 i;
    for (i = 0; i < ENEMY_SLOTS; i++) {
        s16 dx, adx, dy, ady;
        u8 hw;
        if (!en[i].active || en[i].state == EN_DYING) continue;
        hw = enemyHalfW[en[i].type];
        dx = en[i].wx - px; adx = dx < 0 ? -dx : dx;
        dy = en[i].wy - py; ady = dy < 0 ? -dy : dy;
        if (attacking && ady <= 30 &&
            (facing ? (dx > -(56 + hw) && dx < (8 + hw))
                    : (dx > -(8 + hw) && dx < (56 + hw)))) {
            en[i].state = EN_DYING;
            en[i].frame = SK_DEATH_F;
            en[i].timer = 0;
            XGM2_playPCM(sfx_kill, sizeof(sfx_kill), SOUND_PCM_CH2);
            continue;
        }
        if (!invuln && adx < (hw + 4) && ady < 44)
            hurt = (dx > 0) ? -1 : 1;
    }
    return hurt;
}

static void drawEnemy(u8 i)
{
    u8 qx, qy, twoObj;
    s16 sx, sy;
    u16 base, n;
    if (!en[i].active || en[i].uploaded == 255) { hideEnemy(i); return; }
    twoObj = (en[i].type == ET_GATO && en[i].state != EN_DYING);
    if (en[i].state == EN_DYING) sy = en[i].wy - 60 - 16;
    else if (en[i].type == ET_GHOST) sy = en[i].wy - 46;
    else sy = en[i].wy - 60;
    sx = en[i].wx - (s16)camX - (twoObj ? 64 : 32);
    if (sx < -128 || sx > 256) { hideEnemy(i); return; }
    base = 8 + i * 8;
    n = 0;
    for (qy = 0; qy < 2; qy++) {
        for (qx = 0; qx < (twoObj ? 4 : 2); qx++) {
            u8 srcq = en[i].facing ? ((twoObj ? 3 : 1) - qx) : qx;
            u16 tile = (i ? VRAM_ENEMY1 : VRAM_ENEMY0) + (qy * 4 + srcq) * 16;
            setSpr(base + n, sx + qx * 32, sy + qy * 32, tile, PAL_ENEMY,
                en[i].facing, 0, 0);
            n++;
        }
    }
    while (n < 8) {
        setSpr(base + n, -64, -64, 0, PAL_ENEMY, 0, 0, 0);
        n++;
    }
}

static void enemyUploadStep(void)
{
    u8 i;
    if (heroDirty) {
        VDP_loadTileData((const u32 *)(hero_frames + (u32)heroGfx * 4096),
            VRAM_HERO, 128, DMA_QUEUE);
        heroUploaded = heroGfx;
        heroDirty = 0;
        return;
    }
    if (upSlot != 255) {
        if (en[upSlot].active)
            VDP_loadTileData((const u32 *)(upSrc + 2048), (upSlot ? VRAM_ENEMY1 : VRAM_ENEMY0) + 64, 64, DMA_QUEUE);
        en[upSlot].uploaded = en[upSlot].frame;
        upSlot = 255;
        return;
    }
    for (i = 0; i < ENEMY_SLOTS; i++) {
        if (en[i].active && en[i].uploaded != en[i].frame) {
            upSrc = enemyBandSrc(i);
            VDP_loadTileData((const u32 *)upSrc, i ? VRAM_ENEMY1 : VRAM_ENEMY0, 64, DMA_QUEUE);
            upSlot = i;
            return;
        }
    }
}

/* ---- video / state ----------------------------------------------------- */

static u8 musicMode = 0; /* 0 none, 1 title, 2 play */

static void initVideo(void)
{
    VDP_setEnable(FALSE);
    VDP_setPlaneSize(64, 32, TRUE);
    VDP_setScrollingMode(HSCROLL_PLANE, VSCROLL_PLANE);
    PAL_setColors(0, (const u16 *)level_pal, 16, DMA);
    PAL_setColors(16, (const u16 *)bg_pal, 16, DMA);
    PAL_setColors(32, (const u16 *)hero_pal, 16, DMA);
    PAL_setColors(48, (const u16 *)enemy_pal, 16, DMA);
    PAL_setColor(0, ((const u16 *)bg_pal)[0]);
    VDP_setBackgroundColor(0);
    VDP_loadTileData((const u32 *)bg_tiles, VRAM_BG, sizeof(bg_tiles) / 32, CPU);
    VDP_waitDMACompletion();
    VDP_clearPlane(BG_A, TRUE);
    VDP_clearPlane(BG_B, TRUE);
    VDP_setTileMapDataRectEx(BG_B, (const u16 *)bg_map,
        TILE_ATTR_FULL(PAL_BG, 0, 0, 0, VRAM_BG), 0, 0, 64, 32, 64, CPU);
    VDP_waitDMACompletion();
    VDP_setHorizontalScroll(BG_A, 0);
    VDP_setHorizontalScroll(BG_B, 0);
    VDP_setVerticalScroll(BG_A, 0);
    VDP_setVerticalScroll(BG_B, 0);
}

static void drawCentered(const char *text, u16 y)
{
    u16 x = (32 - strlen(text)) / 2;
    VDP_drawTextEx(BG_A, text, TILE_ATTR_FULL(PAL_HERO, 1, 0, 0, 0), x, y, CPU);
}

static void enterTitle(void)
{
    VDP_setEnable(FALSE);
    PAL_setColors(32, (const u16 *)title_pal, 16, DMA);
    VDP_clearSprites();
    VDP_updateSprites(0, DMA);
    VDP_clearPlane(BG_A, TRUE);
    VDP_setHorizontalScroll(BG_A, 0);
    VDP_setHorizontalScroll(BG_B, 0);
    VDP_drawImageEx(BG_A, &title_overlay,
        TILE_ATTR_FULL(PAL_HERO, 1, 0, 0, 0), 0, 0, FALSE, CPU);
    VDP_setEnable(TRUE);
    if (musicMode != 1) {
        XGM2_play(title);
        musicMode = 1;
    }
}

static void enterPlay(void)
{
    VDP_setEnable(FALSE);
    PAL_setColors(32, (const u16 *)hero_pal, 16, DMA);
    VDP_clearSprites();
    VDP_updateSprites(0, DMA);
    VDP_clearPlane(BG_A, TRUE);
    camX = 0;
    feetX = (s32)80 << 8;
    feetY = (s32)192 << 8;
    vx = vy = 0;
    onGround = 0;
    facing = 0;
    jumpDir = 0;
    health = PLAYER_HP;
    lastPage = 0;
    loadedPage[0] = loadedPage[1] = -1;
    loadPageNow(0, 0);
    loadPageNow(1, 1);
    loadedPage[0] = 0;
    loadedPage[1] = 1;
    attackTimer = 0;
    hurtFlag = 0;
    hurtDir = 0;
    spikeCD = 0;
    playPrevPad = 0;
    animFrame = 0;
    lastAnimF = 255;
    animTimer = 0;
    heroGfx = A_IDLE_F;
    heroUploaded = 0xFF;
    heroDirty = 1;
    enemyInit();
    VDP_setEnable(TRUE);
    if (musicMode != 2) {
        XGM2_play(baroque);
        musicMode = 2;
    }
}

static void enterEnd(const char *text)
{
    VDP_setEnable(FALSE);
    PAL_setColors(32, (const u16 *)text_pal, 16, DMA);
    VDP_clearSprites();
    VDP_updateSprites(0, DMA);
    VDP_clearPlane(BG_A, TRUE);
    VDP_setHorizontalScroll(BG_A, 0);
    drawCentered(text, 13);
    VDP_setEnable(TRUE);
    XGM2_stop();
    musicMode = 0;
}

static void updatePlay(void)
{
    u16 pad = JOY_readJoypad(JOY_1);
    u16 prevPad = playPrevPad;
    u8 attacking, crouching, animF, animN, animSpd, sub, loop = 1;
    s16 ix, iy, c, fcol, frow, prevFeetPx;
    u16 mv;

    mv = pad;
    if ((pad & JUMP_KEYS) && !(pad & (BUTTON_LEFT | BUTTON_RIGHT)))
        mv |= (prevPad & (BUTTON_LEFT | BUTTON_RIGHT));
    if (onGround) jumpDir = mv & (BUTTON_LEFT | BUTTON_RIGHT);
    else if (jumpDir && !(mv & (BUTTON_LEFT | BUTTON_RIGHT))) mv |= jumpDir;
    vx = 0;

    if ((pad & ATTACK_KEYS) && !(prevPad & ATTACK_KEYS) && !attackTimer && onGround && !hurtFlag) {
        attackTimer = A_ATTACK_N * 5;
        XGM2_playPCM(sfx_attack, sizeof(sfx_attack), SOUND_PCM_CH2);
    }
    if (attackTimer) attackTimer--;
    attacking = (attackTimer != 0);

    crouching = (onGround && (pad & BUTTON_DOWN) && !attacking);
    if (!attacking && !crouching && !hurtFlag) {
        if (mv & BUTTON_LEFT)  { vx = -640; facing = 1; }
        if (mv & BUTTON_RIGHT) { vx =  640; facing = 0; }
    }
    if (hurtFlag) vx = (s16)hurtDir * 427;
    if ((pad & JUMP_KEYS) && !(prevPad & JUMP_KEYS) && onGround && !attacking && !hurtFlag) {
        vy = -725;
        onGround = 0;
        XGM2_playPCM(sfx_jump, sizeof(sfx_jump), SOUND_PCM_CH2);
    }
    prevPad = pad;
    playPrevPad = pad;

    vy += 21;
    if (vy > 1024) vy = 1024;

    feetX += vx;
    ix = feetX >> 8; iy = feetY >> 8;
    if (vx > 0) {
        c = (ix + HALF_W) >> 4;
        if (cellv(c, (iy - BODY_LO) >> 4) == 1 || cellv(c, (iy - BODY_HI) >> 4) == 1)
            feetX = (s32)((c << 4) - HALF_W) << 8;
    } else if (vx < 0) {
        c = (ix - HALF_W) >> 4;
        if (cellv(c, (iy - BODY_LO) >> 4) == 1 || cellv(c, (iy - BODY_HI) >> 4) == 1)
            feetX = (s32)(((c + 1) << 4) + HALF_W) << 8;
    }

    prevFeetPx = feetY >> 8;
    feetY += vy;
    ix = feetX >> 8; iy = feetY >> 8;
    fcol = ix >> 4;
    if (vy >= 0) {
        frow = iy >> 4;
        c = cellv(fcol, frow);
        if (c == 1 || (c == 2 && prevFeetPx <= (frow << 4))) {
            feetY = (s32)(frow << 4) << 8;
            vy = 0;
            onGround = 1;
            hurtFlag = 0;
        } else onGround = 0;
    } else onGround = 0;

    if (spikeCD) spikeCD--;
    if (!spikeCD && (feetY >> 8) >= 206) {
        u16 hc = (u16)((feetX >> 8) >> 4);
        if ((hc >= 122 && hc <= 125) || (hc >= 166 && hc <= 180)) {
            spikeCD = 40;
            vy = -640;
            onGround = 0;
            XGM2_playPCM(sfx_hurt, sizeof(sfx_hurt), SOUND_PCM_CH2);
            if (--health == 0) { enterEnd("GAME OVER"); return; }
        }
    }

    ix = feetX >> 8;
    c = ix - 128;
    if (c < 0) c = 0;
    if (c > CAM_MAX) c = CAM_MAX;
    camX = c;

    if ((feetY >> 8) > 240) {
        enterPlay();
        return;
    }
    if ((feetX >> 8) >= 4680) {
        enterEnd("THANKS FOR PLAYING");
        return;
    }

    {
        u16 p = camX >> 8;
        if (p != lastPage) {
            lastPage = p;
            ensurePage(p);
            ensurePage(p + 1);
        }
    }

    if (hurtFlag)         { animF = A_HURT_F;   animN = A_HURT_N;   animSpd = 2; loop = 0; }
    else if (attacking)   { animF = A_ATTACK_F; animN = A_ATTACK_N; animSpd = 5; loop = 0; }
    else if (!onGround)   { animSpd = 7;
                            if (vy < 0) { animF = A_JUMP_F;     animN = 2;            loop = 0; }
                            else        { animF = A_JUMP_F + 2; animN = A_JUMP_N - 2; } }
    else if (crouching)   { animF = A_CROUCH_F; animN = A_CROUCH_N; animSpd = 1; }
    else if (vx != 0)     { animF = A_RUN_F;    animN = A_RUN_N;    animSpd = 6; }
    else                  { animF = A_IDLE_F;   animN = A_IDLE_N;   animSpd = 12; }

    if (animF != lastAnimF) { animFrame = 0; animTimer = 0; lastAnimF = animF; }
    if (++animTimer >= animSpd) {
        animTimer = 0;
        if (loop) animFrame = (animFrame + 1) % animN;
        else if (animFrame < animN - 1) animFrame++;
    }
    sub = animFrame;
    if (sub >= animN) sub = animN - 1;
    heroGfx = animF + sub;
    if (heroGfx != heroUploaded) heroDirty = 1;

    enemyUpdate();
    {
        s8 kb = enemyCombat(attacking, hurtFlag);
        if (kb) {
            hurtFlag = 1;
            hurtDir = kb;
            onGround = 0;
            vy = -640;
            vx = (s16)kb * 427;
            attackTimer = 0;
            XGM2_playPCM(sfx_hurt, sizeof(sfx_hurt), SOUND_PCM_CH2);
            if (--health == 0) { enterEnd("GAME OVER"); return; }
        }
    }

    drawHero();
    {
        u8 i;
        for (i = 0; i < ENEMY_SLOTS; i++) drawEnemy(i);
    }
    linkSprites();
    VDP_updateSprites(24, DMA);

    VDP_setHorizontalScroll(BG_A, camX & 511);
    VDP_setHorizontalScroll(BG_B, (camX * 7) / 100);
    VDP_setVerticalScroll(BG_A, 0);
    VDP_setVerticalScroll(BG_B, 0);
    enemyUploadStep();
}

int main(bool hard)
{
    GameState state = ST_TITLE;
    (void)hard;
    JOY_init();
    initVideo();
    enterTitle();
    while (TRUE) {
        SYS_doVBlankProcess();
        if (state == ST_TITLE) {
            static u16 prev = 0;
            u16 pad = JOY_readJoypad(JOY_1);
            if ((pad & BUTTON_START) && !(prev & BUTTON_START)) {
                enterPlay();
                state = ST_PLAY;
            }
            prev = pad;
        } else if (state == ST_PLAY) {
            updatePlay();
            if (health == 0 || (feetX >> 8) >= 4680) state = ST_PLAY + 1;
        } else {
            static u16 prev = 0;
            u16 pad = JOY_readJoypad(JOY_1);
            if ((pad & BUTTON_START) && !(prev & BUTTON_START)) {
                enterTitle();
                state = ST_TITLE;
            }
            prev = pad;
        }
    }
    return 0;
}
