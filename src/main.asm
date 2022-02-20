    .include "hw.asm"
    .include "defines.asm"
    .include "game.asm"
    .include "rng.asm"
    .include "wordlist.asm"
    
    ; RAM allocations
* = $80
r0  .word ?
r1  .word ?

rng_state       .fill 3

clear_start

flags           .byte ?
joy_last        .byte ?
cursor_pos      .byte ?
game_state      .byte ?
anim_frame      .byte ?

answer_chars    .fill 5
lose_clear_start
timer_frac      .word ?
timer_sec       .byte ?
timer_min       .byte ?
cur_score       .word ?
lose_clear_end
max_score       .word ?

guess_pf_col    .byte ?
kbd_pf_col      .byte ?

guess_clear_start
guess_pos       .byte ?
guess_pfs       .fill 3 * 6
guess_chars     .fill 5 * 6
guess_clear_end

kbd_pfs         .fill 3 * 3

clear_end

draw_ptrs       .fill 2 * 15

    .cwarn * > $f7, "Very low stack space, starting at ", *
    
    ; due to how banking works, codes that access banked data must exist at
    ; the same position in every banks
bank_common  .macro
org = (\1 + 1) * $1000 - size(bank)
    .cerror * > org, "bank ", \1, " too large! (", *, ")"
    
* = org
    .logical (\1 + 1) * $2000 - size(bank)
bank    .block
    .if \1 < 2
rtsfar
    tsx
    lda 2,x
    cmp #$20 ; from bank 1?
    sta BANK0
    bcc +
    sta BANK1
+   rts

load_message_ptrs_0
update_reveal_endgame_1
    .if \1 == 0
        sta BANK1
        jmp load_message_ptrs
    .else
        sta BANK0
        jmp update_reveal_endgame
    .fi
end_frame_0
handle_game_state_1
    .if \1 == 0
        sta BANK1
        jmp end_frame
    .else
        sta BANK0
        jmp handle_game_state
    .fi
    
get_word_far
    sta BANK0,x
    .fi
    lda (r1),y
    dey
    tax
    lda (r1),y
    sta BANK1
    rts
    
reset
    sta BANK0
    jmp start
    .fill 8, 0  ; BANK0 - BANK7
    .word reset ; reset vector
    .word reset ; break vector
    .bend
    .here
    .endm

* = 0
    .logical $1000

start
    cld
    ldx #$ff
    txs

    jsr set_vblank
    jsr rng.init
    ; clear video registers
    lda #0
    ldx #(PF2-NUSIZ0)
-   sta NUSIZ0,x
    dex
    bpl -
    ldx #(RESMP1-AUDC0)
-   sta AUDC0,x
    dex
    bpl -
    sta SWACNT ; input
    sta SWBCNT ; input
    ldx #(clear_end-clear_start-1)
-   sta clear_start,x
    dex
    bpl -
    
    jsr new_game
_main_loop
_retry
    jsr g.bank.handle_game_state_1
    lda game_state
    cmp #GS_NEW
    bne _end_frame
    jsr rng.advance
    ; are we low on frame time?
    lda INTIM
    cmp #15
    bcs _retry
_end_frame
    jsr end_frame
    jmp _main_loop
    
    .dsection game_code
    .dsection rng_code
    
    ; graphic routines
    ; some game-related codes are also here
    
end_frame
    ; check end of screen timer
-
    bit INSTAT
    bpl -
    lda #2
    sta WSYNC
    sta VSYNC
    
    ; some updates are fit here
    lda flags
    eor #FLAGS_ODD_FRAME
    sta flags
    and #FLAGS_NO_TIMER
    jsr rng.advance
    
    sta WSYNC
    lda #0
    sta WSYNC
    sta VSYNC
    lda #43 ; ~36 lines
    sta TIM64T
    
    ; update frame states
    
update_timer
    lda flags
    and #FLAGS_NO_TIMER
    bne _done
    clc
    lda timer_frac
    adc #<TIMER_FRAC_ADD
    sta timer_frac
    lda timer_frac+1
    adc #>TIMER_FRAC_ADD
    sta timer_frac+1
    bcc _done
    ; rare BCD math!
    sed
    lda timer_sec
    ; sec
    adc #0
    cmp #$60
    bcc ++
    lda timer_min
    cmp #$99
    bcs +
    ; clc
    adc #1
    sta timer_min
+   lda #0
+   cld
    sta timer_sec
_done
    
update_input
    ; joypad inputs are combined from both 2 players
    lda SWCHA
    sta r0
    lsr a
    lsr a
    lsr a
    lsr a
    and r0
    asl INPT4
    bcc +
    asl INPT5
+   rol a
    ; get console buttons
    ldy SWCHB
    sty r0
    lsr r0 ; reset
    rol a
    lsr r0 ; select
    rol a
    ; button inputs are active low, but joy_last is active high
    eor #%01111111
    ; filter only 0 -> 1 transition (= ~last & new)
    ldy joy_last
    sta joy_last
    tya
    eor #$ff
    and joy_last
    bne +
-   jmp update_input_done
    
+   sta r0
    lda flags
    and #FLAGS_NO_INPUT
    bne -
    ; don't handle console buttons on game results
    ldx game_state
_check_sel
    lsr r0
    bcc _check_res
    cpx #GS_WIN
    bcs _check_res
    lda flags
    and #FLAGS_NO_MODE
    bne _no_mode
    lda flags
    eor #FLAGS_HARD_MODE
    sta flags
    ldy #messages.easy_mode-messages
    and #FLAGS_HARD_MODE
    beq +
    ldy #messages.hard_mode-messages
+   jsr popup_info_0
    jmp update_input_done
_no_mode
    lda #GS_ERROR2
    jsr set_game_state_0
_check_res
    lsr r0
    bcc _check_fire
    cpx #GS_WIN
    bcs _check_fire
    cpx #GS_GUASK
    bne +
    jsr popup_lose
    jmp update_input_done
+   lda #GS_GUASK
    ldy #messages.give_up-messages
    jsr popup_0
    jmp update_input_done
_check_fire
    lsr r0
    bcc _check_up
    jsr close_popup_update
    lda #GS_CHECK
    jsr set_game_state_0
    jmp update_input_done
_check_up
    lsr r0
    bcc _check_down
    jsr close_popup_update
    lda cursor_pos
    cmp #19
    bcs +++
    cmp #10
    bcs ++
    cmp #9
    bcc +
    ; P needs to advance by 1 less so it lands at the same destination as O
    ; sec
    sbc #1
    clc
+   adc #30
+   sbc #1
+   sbc #9
    sta cursor_pos
_check_down
    lsr r0
    bcc _check_left
    jsr close_popup_update
    lda cursor_pos
    cmp #9
    bcs +
    ; Q-O needs to advance by 1 more so it goes to the right
    ; clc
    adc #1
+   cmp #19
    bcc +
    ; sec
    sbc #28
+   ; clc
    adc #9
    sta cursor_pos
_check_left
    lsr r0
    bcc _check_right
    jsr close_popup_update
    dec cursor_pos
    bpl +
    lda #9
    bne +++
+   lda cursor_pos
    cmp #9
    beq +
    cmp #18
    bne _check_right
+   ; sec
    adc #8
+   sta cursor_pos
_check_right
    lsr r0
    bcc update_input_done
    jsr close_popup_update
    inc cursor_pos
    lda cursor_pos
    cmp #10
    bne +
    lda #0
    beq +++
+   cmp #19
    beq +
    cmp #28
    bne update_input_done
+   ; sec
    sbc #9
+   sta cursor_pos
    
update_input_done

update_reveal
    ldx game_state
    cpx #GS_REVEAL
    beq +
    jmp update_animation
+   ldx guess_pos
    lda anim_frame
    and #$f
    bne _second
    cpx #5*6
    bcc _first
    ; last frame
    ; oops ran out of bank
    jsr g.bank.update_reveal_endgame_1
    lda game_state
    cmp #GS_LOSE
    bne +
    jsr popup_lose
+   jmp update_animation_done

_first
    lda guess_chars,x
    sta r1+1
    lda #'#'
    sta guess_chars,x
-   jmp update_reveal_done
    
_second
    cmp #$7
    bcc -
    beq +
    jmp _second_volume
+   ; get column number
    ldy #-1
    txa
    sec
-   sbc #6
    iny
    bcs -
    ; clc
    adc #6
    sta r0+1 ; save row position for later...
    lda r1+1
    cmp answer_chars,y
    bne +
    ora #$40 ; mark green for hard mode check
    ; mark that green is revealed so later letters that would mark yellow from
    ; a match at this position won't occur
    sta answer_chars,y
    tax
    ; play green tone
    lda #12
    sta AUDC0
    lda r1
    dec r1
    and #7
    ; sec
    adc #3
    ; clc
    bne _second_set_col
    
+   ; check for yellow
    ldx #5-1
-   cmp answer_chars,x
    beq _yellow
    dex
    bpl -
    ; no matches
    ; don't remove from the keyboard if it's actually in the answer!
    ldx #5-1
    tay
-   tya
    eor answer_chars,x
    and #$1f
    beq +
    dex
    bpl -
    jsr remove_cursor_from_keyboard
+   ldx #15
    stx AUDC0
    ldx #9
    stx AUDF0
    lda r1+1
    bne _second_done
    
_yellow
    ora #$80 ; mark yellow for hard mode check
    ; currently commented out since there needs to be a logic to check if the
    ; letter at x would be green later and turns this to no matches instead
    ; sadly, I really run out of bank and time for this :(
    ; sta answer_chars,x
    tax
    ; play yellow tone
    lda #1
    sta AUDC0
    lda r1
    ; sec
    sbc #8
    sta r1
    lsr a
    lsr a
    lsr a
    clc
    adc #11
    sec
    
_second_set_col
    sta AUDF0
    lda flags
    and #FLAGS_ALT_COL
    bcc +
    eor #FLAGS_ALT_COL
+   bne _second_set_pf
    ; invert char
    txa
    ora #$20
    bne _second_done
_second_set_pf
    ; since displayed guesses have the same position as 9-column keyboard row,
    ; maskes for them can be reused, although keep in mind there's a space
    ; character in-between
    stx r0
    ldx r0+1 ; ...here
    tya
    asl a
    tay
    lda cursor_pf_mask_9,y
    ora guess_pfs,x
    sta guess_pfs,x
    lda cursor_pf_mask_9+28,y
    ora guess_pfs+6,x
    sta guess_pfs+6,x
    lda cursor_pf_mask_9+56,y
    ora guess_pfs+12,x
    sta guess_pfs+12,x
    lda r0
_second_done
    ldx guess_pos
    sta guess_chars,x
    txa
    clc
    adc #6
    sta guess_pos
    lda #$b ; slight attack time
_second_volume
    eor #$f
    asl a
    sta AUDV0
    jmp update_reveal_done

update_animation
    ; ldx game_state
    jsr play_sfx
    beq +
update_reveal_done
    inc anim_frame
    bne update_animation_done
+   cpx #GS_CHECK
    bcs update_animation_done
    ; lda #GS_NONE
    jsr set_game_state_0
    
update_animation_done
    
    ; wait until start of display
-
    bit INSTAT
    bpl -
    lda #0
    sta VBLANK
    
    ; draw screen
    
draw_title
    ; title text
    lda #$06    ; white
    bit flags
    bvc +       ; hard mode?
    lda #$c6    ; green
+
    sta r0
    ldx #0
-
    lda r0
    sta COLUPF
    ldy #3
-
    sta WSYNC           ; -68.
    lda gfx_title,x     ; -56.
    sta PF0             ; -47.
    lda gfx_title+10,x  ; -35.
    sta PF1             ; -26.
    lda gfx_title+20,x  ; -14.
    sta PF2             ; - 5.
    lda gfx_title+30,x  ;   7.
    sta PF0             ;  16.
    lda gfx_title+40,x  ;  28.
    nop                 ;  34.
    nop                 ;  40.
    sta PF1             ;  49.
    lda gfx_title+50,x  ;  61.
    dey                 ;  67.
    nop                 ;  73.
    sta PF2             ;  82.
    bne -
    inc r0
    inx
    cpx #10
    bne --
    
draw_guesses
    ; set player position
    lda #0
    sta WSYNC   ; -68.
    sta COLUPF  ; -59.
    lda #$0f    ; -53.
    sta COLUP0  ; -44.
    sta COLUP1  ; -35.
    ; three copies medium
    lda #6      ; -29.
    sta NUSIZ0  ; -20.
    sta NUSIZ1  ; -11.
    ; enable buffer
    lda #1      ; - 5.
    sta VDELP0  ;   4.
    sta VDELP1  ;  13.
    lda #$40    ;  19.
    sta HMP0    ;  28.
    lda #$60    ;  34.
    sta RESP0   ;  43. +1
    sta HMP1    ;  52.
    sta RESP1   ;  61. -1
    sta WSYNC
    sta HMOVE
    
    ldx #5
    jsr pad_lines
    
    ldx #0
_loop
_i := 0
    .rept 5
    lda guess_chars+_i*6,x  ; 4
    and #$3f                ; 2
    tay                     ; 2
    lda fontaddr_lo,y       ; 4
    sta draw_ptrs+_i*2+20   ; 3
    lda fontaddr_hi,y       ; 4
    sta draw_ptrs+_i*2+21   ; 3
_i += 1
    .next                   ; 22*5 = 110
    lda guess_pfs,x
    sta PF0
    lda guess_pfs+6,x
    sta PF1
    lda guess_pfs+12,x
    sta PF2
    
    stx r0+1
    ldy #0
-
    sta WSYNC               ; -68.
    lda (draw_ptrs+28),y    ; -53.
    sta r0                  ; -44.
    lda (draw_ptrs+20),y    ; -29.
    sta GRP0                ; -20. (44)
    lda (draw_ptrs+22),y    ; - 5. /
    sta GRP1                ;   4./(60)
    lda (draw_ptrs+24),y    ;  19.   /
    ldx @w guess_pf_col     ;  31.  /
    stx COLUPF              ;  40. /
    sta GRP0                ;  49./(76)
    lda (draw_ptrs+26),y    ;  64. /
    sta GRP1                ;  73./(96)
    lda r0                  ;  82. /
    sta GRP0                ;  91./(108)
    lda #0                  ;  97. /
    sta GRP1                ; 106./(124)
    sta GRP0                ; 115./
    sta COLUPF              ; 124.
    iny                     ; 130
    cpy #16                 ; 136.
    bcc -                   ; 145.
    
    ; draw 2 more blank
    sta GRP1
    ldx r0+1
    inx
    cpx #6
    bcs +
    jmp _loop
+
    
draw_bottom
    lda #91 ; ~78 lines
    sta WSYNC
    sta TIM64T
    sta WSYNC
    
    lda game_state
    cmp #GS_SCORE
    bne +
    jmp draw_score
+   cmp #GS_INFO
    bcc +
    jmp draw_info
+   jmp draw_keyboard
    
draw_info
    ldx game_state
    lda #$cf
    cpx #GS_WIN
    beq +
    lda #$4f
    cpx #GS_LOSE
    bne ++
+   sta COLUP0
    sta COLUP1
+   jsr draw_info_position_players
    ldx #21
    jsr pad_lines
    jsr draw_info_render
    jmp finish_drawing
    
draw_info_position_players
    lda #$40 
    ldx #-$40
draw_info_position_players_
    bit flags
    bpl +
    txa
+   jmp move_both_players
    
draw_score
    ; 0246802468
    ; time 99:59
    ; score 9999
    ; best  9999
    lda #$40 
    jsr move_both_players
    
    ldx #0
    jsr _load_text_and_reposition
    lda #<(gfx_font+':'*16)
    sta draw_ptrs+14
    lda #>(gfx_font+':'*16)
    sta draw_ptrs+15
    lda timer_min
    ldx #draw_ptrs+10
    jsr _load_bcd
    lda timer_sec
    jsr _load_bcd_16
    jsr draw_info_render
    
    ldx #5
    jsr _load_text_and_reposition
    lda cur_score+1
    ldx #draw_ptrs+12
    jsr _load_bcd
    lda cur_score
    jsr _load_bcd_16
    jsr draw_info_render
    
    ldx #11
    jsr _load_text_and_reposition
    lda max_score+1
    ldx #draw_ptrs+12
    jsr _load_bcd
    lda max_score
    jsr _load_bcd_16
    jsr draw_info_render
    
    jmp finish_drawing
    
_load_text_and_reposition
_i := 0
    .rept 6
    lda _textaddrs_lo+_i,x
    sta draw_ptrs+_i*2
    lda _textaddrs_hi+_i,x
    sta draw_ptrs+_i*2+1
_i += 1
    .next
    lda #0
    ldx #$80
    jmp draw_info_position_players_
    
_load_bcd_16
    ldx #draw_ptrs+16
_load_bcd
    ldy #>(gfx_font+'0'*16)
    sty 1,x
    sty 3,x
    tay
    ; font size is coincidentally 16 bytes so this speedup is possible
    and #$f0
    sta 0,x
    tya
    asl a
    asl a
    asl a
    asl a
    sta 2,x
    rts
    
_textaddrs = ('t','i','m','e',' ','s','c','o','r','e',' ','b','e','s','t',' ',' ') * 16 + gfx_font
_textaddrs_lo   .byte <_textaddrs
_textaddrs_hi   .byte >_textaddrs
    
    ; data that doesn't require alignment goes here
    
char_to_cursor
    ; qwertyuiopasdfghjkl=zxcvbnm<
    .byte 10, 24, 22, 12,  2, 13, 14, 15,  7, 16, 17, 18, 26
    .byte 25,  8,  9,  0,  3, 11,  4,  6, 23,  1, 21,  5, 20
    
    ; only up to inverted z are declared here since the rest are never drawn
    ; by guesses list or info, or are separately handled by draw_score
fontaddr_lo .byte <(gfx_font+range('z'+33)*16)
fontaddr_hi .byte >(gfx_font+range('z'+33)*16)
    
    .align $100
draw_info_render
    ldy #1
    bit flags
    bmi +
    lda (draw_ptrs+12),y
    sta WSYNC               ; -68.
    .page
    jmp _loop               ; -59.
+   lda (draw_ptrs+14),y
    sta WSYNC               ; -68.
    jmp _loop_2             ; -59.
    
_loop
    tax                     ; -53.
    lda (draw_ptrs+16),y    ; -38.
    sta r0                  ; -29.
    lda (draw_ptrs+0),y     ; -14.
    sta GRP0                ; - 5. (40)
    lda (draw_ptrs+4),y     ;  10. /
    sta GRP1                ;  19./(56)
    lda (draw_ptrs+8),y     ;  34. /
    sta GRP0                ;  43./(72)
    txa                     ;  49. /
    sta GRP1                ;  58./(88)
    lda r0                  ;  67. /
    sta GRP0                ;  76./(104)
    lda #0                  ;  82. /
    sta GRP1                ;  91./(120)
    iny                     ;  97. /
    sta GRP0                ; 106./
    lda #$80                ; 112.
    sta HMP0                ; 121.
    sta @w HMP1             ; 133.
    cpy #15                 ; 139.
    bcs _done               ; 145.
    
    lda (draw_ptrs+14),y    ; -68.
    sta HMOVE               ; -59.
_loop_2
    tax                     ; -53.
    lda (draw_ptrs+18),y    ; -38.
    sta r0                  ; -29.
    lda (draw_ptrs+2),y     ; -14.
    sta GRP0                ; - 5. (40)
    lda (draw_ptrs+6),y     ;  10. /
    sta GRP1                ;  19./(56)
    lda (draw_ptrs+10),y    ;  34. /
    sta GRP0                ;  43./(72)
    txa                     ;  49. /
    sta GRP1                ;  58./(88)
    lda r0                  ;  67. /
    sta GRP0                ;  76./(104)
    lda #0                  ;  82. /
    sta GRP1                ;  91./(120)
    iny                     ;  97. /
    sta GRP0                ; 106./
    ; it's not possible to move left by 8 dots per line
    ; however, by using out-of-hblank HMOVE "bug",
    ; a write just 1-2 cycles before hblank will
    ; additionally move all objects left by 8 dots (!)
    sta HMP0                ; 115.
    sta HMP1                ; 124.
    lda (draw_ptrs+12),y    ; 139.
    cpy #15                 ; 145.
    sta HMOVE               ; 154.
    nop                     ; -68.
    bcc _loop               ; -59.
    .endp
_done
    sta GRP1
    rts
    
    .page
messages    .block
loading     .text "  loading "
easy_mode   .text "easy  mode"
hard_mode   .text "hard  mode"
give_up     .text " give up? "
too_short   .text " too short"
not_a_word  .text "not a word"
exp_at      .text "exp   at  "
needs       .text " needs    "
win_1       .text "  lucky!  "
win_2       .text "  genius! "
win_3       .text "marvelous!"
win_4       .text " splendid!"
win_5       .text "  great!  "
win_6       .text "   phew!  "
    .bend
    .endp

draw_keyboard_load_pf   .macro
    ldx cursor_pos          ; 3
    bit flags               ; 3
    bpl _mix_cursor_and_pf  ; 2
_no_mix
    lda (\3)-(\2),x         ; 4
    sta PF0                 ; 3
    lda (\3)-(\2)+28,x      ; 4
    sta PF1                 ; 3
    lda (\3)-(\2)+56,x      ; 4
    sta PF2                 ; 3
    jmp _done               ; 3
                            ; = 32
_mix_cursor_and_pf
    lda kbd_pfs+(\1)        ; 3
    ora (\3)-(\2),x         ; 4
    sta PF0                 ; 3
    lda kbd_pfs+(\1)+1      ; 3
    ora (\3)-(\2)+28,x      ; 4
    sta PF1                 ; 3
    lda kbd_pfs+(\1)+2      ; 3
    ora (\3)-(\2)+56,x      ; 4
    sta PF2                 ; 3
                            ; = 39
_done
    .endm

draw_keyboard_render    .macro
    ldy #0
    bit flags
    bmi +
    sta WSYNC                   ; -68.
    .page
    bpl _loop                   ; -59.
+   sta WSYNC                   ; -68.
    bmi _loop_2                 ; -59.
    
_loop
    lda gfx_font+(\1)[8]*16+1,y ; -47.  Q-O  A-<
    sta r0                      ; -38.
    lda gfx_font+(\1)[0]*16+1,y ; -26.
    sta GRP0                    ; -17. ( 40,  44)
    lda gfx_font+(\1)[2]*16+1,y ; - 5. /
    sta GRP1                    ;   4./( 56,  60)
    lda gfx_font+(\1)[4]*16+1,y ;  16.    /
    ldx kbd_pf_col              ;  25.   /
    iny                         ;  31.  /
    stx COLUPF                  ;  40. /
    sta GRP0                    ;  49./( 72,  76)
    lda gfx_font+(\1)[6]*16,y   ;  61. /
    sta GRP1                    ;  70./( 88,  96)
    lda r0                      ;  79. /
    sta GRP0                    ;  88./(104, 108)
    lda #0                      ;  94. /
    sta GRP1                    ; 103./(120, 124)
    sta GRP0                    ; 112./
    sta COLUPF                  ; 121.
    lda #$80                    ; 127.
    sta HMP0                    ; 136.
    sta HMP1                    ; 145.
    cpy #14                     ; 151.
    bcs _done                   ; 157.
    
    sta @w HMOVE                ; -59.
_loop_2
    lda gfx_font+(\1)[9]*16+1,y ; -47.
    sta r0                      ; -38.
    lda gfx_font+(\1)[1]*16+1,y ; -26.
    sta GRP0                    ; -17. ( 40,  44)
    lda gfx_font+(\1)[3]*16+1,y ; - 5. /
    sta GRP1                    ;   4./( 56,  60)
    lda gfx_font+(\1)[5]*16+1,y ;  16.    /
    ldx kbd_pf_col              ;  25.   /
    iny                         ;  31.  /
    stx COLUPF                  ;  40. /
    sta GRP0                    ;  49./( 72,  76)
    lda gfx_font+(\1)[7]*16,y   ;  61. /
    sta GRP1                    ;  70./( 88,  96)
    lda r0                      ;  79. /
    sta GRP0                    ;  88./(104, 108)
    lda #0                      ;  94. /
    sta GRP1                    ; 103./(120, 124)
    sta GRP0                    ; 112./
    sta COLUPF                  ; 121.
    sta HMP0                    ; 130.
    sta HMP1                    ; 139.
    cpy #14                     ; 145.
    sta HMOVE                   ; 154.
    nop                         ; -68.
    bcc _loop                   ; -59.
    .endp
_done
    sta GRP1
    .endm

    .align $100
draw_keyboard
    lda #$94
    ldx #$40
    bit flags
    bpl +
    lda #$ba
    ldx #-$40
+   sta kbd_pf_col
    stx HMP0
    stx HMP1
    sta WSYNC
    sta HMOVE
    
    ldx #4
    jsr pad_lines
    
    #draw_keyboard_load_pf 0, 0, cursor_pf_mask_10
    #draw_keyboard_render "qwertyuiop"
    lda #-$20
    ldx #-$60
    jsr draw_keyboard_move
    jmp draw_keyboard_2
    
    ; bunch of code and data are inserted here to make up with alignment padding
    .page
draw_keyboard_move
    jsr draw_info_position_players_
    sta WSYNC
    sta HMOVE
    rts
    
pad_lines
    sta WSYNC
    dex
    bne pad_lines
    rts
    
play_sfx
    ; x = game state
    ; returns zf = silence played
    ldy sfx_gs_map,x
-   lda sfx_table_keyf,y
    cmp anim_frame
    beq _apply
    bcs _done
    iny
    bne -
_apply
    lda sfx_table_wvol,y
    sta AUDV0
    lsr a
    lsr a
    lsr a
    lsr a
    sta AUDC0
    lda sfx_table_freq,y
    sta AUDF0
    ora sfx_table_wvol,y
_done
    rts
    .endp
    
    .align $100
draw_keyboard_2
    #draw_keyboard_load_pf 3, 10, cursor_pf_mask_9
    #draw_keyboard_render "asdfghjkl "
    lda #0
    ldx #-$40
    jsr draw_keyboard_move
    jmp draw_keyboard_3
    
    .page
sfx_gs_map
    ; reveal sound effects are handled separately, see handle_reveal_anim
    .byte 0, 1, 3, 5, 10, 0, 0, 0, 3, 10, 3, 10, 14, 12, 1
    ;       0    1         3         5                      10      12
    ;      14
sfx_table_keyf
    .byte   0,   0,   1,   0,   1,   0,   1,   2,   3,  4,   0, 8,   0, 20
    .byte   0,  16,  24,  40,  48,  72
sfx_table_wvol
    .byte   0, $07,   0, $4f,   0, $82, $85, $88, $8a,  0, $6f, 0, $ef,  0
    .byte $c9, $c8, $c9, $c8, $c9,   0
sfx_table_freq
    .byte   0,   9,   0,   8,   0,   3,   2,   1,   1,  0,  17, 0,  11,  0
    .byte   5,   6,   7,   6,   5,   0
    .endp
    
    .align $100
draw_keyboard_3
    #draw_keyboard_load_pf 6, 19, cursor_pf_mask_9
    #draw_keyboard_render "=zxcvbnm< "
    jmp finish_drawing

    .page
remove_cursor_from_keyboard
    ldx r1+1
    ldy char_to_cursor-1,x
    ldx #0
    lda cursor_pf_mask_10,y
    jsr _remove
    lda cursor_pf_mask_10+28,y
    jsr _remove
    lda cursor_pf_mask_10+56,y
    jsr _remove
    lda cursor_pf_mask_9-10,y
    jsr _remove
    lda cursor_pf_mask_9-10+28,y
    jsr _remove
    lda cursor_pf_mask_9-10+56,y
    jsr _remove
    lda cursor_pf_mask_9-19,y
    jsr _remove
    lda cursor_pf_mask_9-19+28,y
    jsr _remove
    lda cursor_pf_mask_9-19+56,y
_remove
    eor #$ff
    and kbd_pfs,x
    sta kbd_pfs,x
    inx
    rts
    
move_both_players
    sta HMP0
    sta HMP1
    sta WSYNC
    sta HMOVE
    rts
    
set_vblank
    lda #2
    sta VBLANK
    rts
    .endp

    .align $100
    ; 74 8x16 characters (1184 bytes total)
gfx_font    .binary "gfx_font.bin"
    ; title text, 40x10 mirrored playfield register values
    ; (60 bytes total)
gfx_title   .binary "gfx_title.bin"

    .page
finish_drawing
    lda #0
    sta WSYNC
    sta PF0
    sta PF1
    sta PF2
    jsr set_vblank
    jmp g.bank.rtsfar
    
    .dsection game_code_2
    .endp

    .align $100
    ; (159 bytes total)
cursor_pf_mask_10
    .byte 0, 0, 0, 0, 0, %00110000, %11000000, 0, 0, 0
    .fill 18, 0
    .byte %00000011, 0, 0, 0, 0, 0, 0, %11000000, %00110000, %00001100
    .fill 18, 0
    .byte 0, %00000011, %00001100, %00110000, %11000000, 0, 0, 0, 0, 0
    .fill 19, 0
cursor_pf_mask_9
    .byte 0, 0, 0, 0, %00010000, %01100000, %10000000, 0, 0
    .fill 19, 0
    .byte %00000001, 0, 0, 0, 0, 0, %10000000, %01100000, %00011000
    .fill 19, 0
    .byte %00000001, %00000110, %00011000, %01100000, %10000000, 0, 0, 0, 0
    .fill 9, 0
    
    .dsection game_code_3

    .here
    
g   #bank_common 0

    ; word data banks
* = $1000
    .logical $3000
    .dsection game_state_handler
    .dsection wordlist_data_1
    .here
    #bank_common 1
    
* = $2000
    .logical $5000
    .dsection wordlist_data_2
    .here
    #bank_common 2
    
* = $3000
    .logical $7000
    .dsection wordlist_data_3
    .here
    #bank_common 3
    