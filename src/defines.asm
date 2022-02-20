TIMER_FRAC_ADD  = 1093   ; = 65536/(3579545/228/262)

FLAGS_ODD_FRAME = bits(1 << 7)
FLAGS_HARD_MODE = bits(1 << 6)
FLAGS_ALT_COL   = bits(1 << 5)
FLAGS_LOSE      = bits(1 << 4)
FLAGS_NO_MODE   = bits(1 << 2)
FLAGS_NO_TIMER  = bits(1 << 1)
FLAGS_NO_INPUT  = bits(1 << 0)

GS_NONE     = 0
GS_INPUT    = 1
GS_CHAR     = 2
GS_DEL      = 3
GS_ERROR2   = 4
; states below this will go back to GS_NONE after sfx playback
GS_CHECK    = 5
GS_CHECK_H  = 6
GS_REVEAL   = 7
; states below this will display messages
GS_INFO     = 8
GS_ERROR    = 9
GS_NEW      = 10
GS_GUASK    = 11
; states below this will not read console buttons
GS_WIN      = 12
GS_LOSE     = 13
GS_SCORE    = 14
    
    ; character values
    .enc "game"
    .cdef "  ", 0
    .cdef "az", 1
    .cdef "!!", 27
    .cdef "::", 28
    .cdef "==", 29 ; enter
    .cdef "<<", 30 ; delete
    .cdef "??", 31
    .cdef "##", 32 ; inverted space, for cursor
    .cdef "09", 64
    