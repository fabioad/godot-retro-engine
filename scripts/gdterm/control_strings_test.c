/* Regression: unsupported control strings must not draw text or move the
 * cursor. OpenTUI probes OSC 66 support using cursor position reports. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "tmt.h"

static void check(const char *input, size_t chunk) {
    TMT *vt = tmt_open(4, 80, NULL, NULL, NULL);
    size_t len = strlen(input);
    for (size_t pos = 0; pos < len; pos += chunk) {
        size_t n = len - pos < chunk ? len - pos : chunk;
        tmt_write(vt, input + pos, n);
    }
    const TMTSCREEN *s = tmt_screen(vt);
    assert(s->lines[0]->chars[0].c == 'A');
    assert(s->lines[0]->chars[1].c == 0x2580);
    assert(s->lines[0]->chars[2].c == 0x2584);
    assert(s->lines[0]->chars[3].c == 0x2588);
    assert(s->lines[0]->chars[4].c == 0x2026);
    assert(s->lines[0]->chars[5].c == 0x00b7);
    assert(s->lines[0]->chars[6].c == 'Z');
    assert(tmt_cursor(vt)->c == 7);
    tmt_close(vt);
}

int main(void) {
    const char *cases[] = {
        "A\033]66;w=1; \033\\▀▄█…·Z",
        "A\033]10;?\007▀▄█…·Z",
        "A\033P+q4d73\033\\\033_Gi=31337;AAAA\033\\▀▄█…·Z",
        "A\033^hidden\033\\\033Xhidden\033\\▀▄█…·Z",
        "A\033[?2027$p\033[>0q▀▄█…·Z",
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i)
        for (size_t chunk = 1; chunk <= strlen(cases[i]); ++chunk)
            check(cases[i], chunk);
    puts("TERMINAL_CONTROL_STRINGS PASS (all read boundaries)");
    return 0;
}
