    .section game_code
    
new_game
    lda SWCHB
    and #%00001000 ; color switch
    beq +
    ; color, green is green
    ldx #$c7
    lda flags
    ora #FLAGS_ALT_COL
    bne ++
+   ; b/w, green is white (inverted)
    ldx #$27 ; safe for both PAL/NTSC
    lda flags
    and #~FLAGS_ALT_COL
+   ora #FLAGS_NO_INPUT | FLAGS_NO_TIMER
    stx guess_pf_col
    tay
    and #FLAGS_LOSE
    beq +
    lda #0
    ldx #lose_clear_end-lose_clear_start-1
-   sta lose_clear_start,x
    dex
    bpl -
    tya
    and #~(FLAGS_LOSE | FLAGS_NO_MODE)
    tay
+   sty flags

    ; clear guesses and initialize keyboard hilights
    ldy #0
    ldx #guess_clear_end-guess_clear_start-1
-   sty guess_clear_start,x
    dex
    bpl -
    dey ; ldy #$ff
    ldx #8
-   sty kbd_pfs,x
    dex
    bpl -
    lda #%11111001
    sta kbd_pfs+4
    sta kbd_pfs+7

    lda #GS_NEW
    ldy #messages.loading-messages
    jsr popup_0
    sec ; for close_popup_update
    rts
    
    ; popups (bank 0)
    
close_popup
    ; returns cf = popup closed
    ldx game_state
    cpx #GS_SCORE
    beq _close_score
    lda #GS_SCORE
    cpx #GS_WIN
    beq _close
    cpx #GS_LOSE
    beq _close
    lda #GS_INPUT
    cpx #GS_INFO
_close
    ; set_game_state doesn't modify carry flag
    jmp set_game_state_0
    
_close_score
    jmp new_game
    
popup_lose
    ; hack: "phew!" is exactly 5 chars long and helps fill spaces
    ldy #messages.win_6-messages
    jsr load_message_ptrs
    ldx #5*2-1
    ldy #5-1
-   lda answer_chars,y
    sty r0
    tay
    lda fontaddr_hi,y
    sta draw_ptrs+3*2,x
    dex
    lda fontaddr_lo,y
    sta draw_ptrs+3*2,x
    ldy r0
    dey
    dex
    bpl -
    lda flags
    ora #FLAGS_LOSE | FLAGS_NO_TIMER
    sta flags
    lda #GS_LOSE
    jmp set_game_state_0
    
    .send
    
    .section game_code_2
close_popup_update
    jsr close_popup
    bcs +
    rts
+   ; discard return address
    pla
    pla
    jmp update_input_done
    
set_game_state_0
    sta game_state
    lda #0
    sta anim_frame
    rts
    .send
    
    .section game_code_3
popup_info_0
    lda #GS_INFO
popup_0
    jsr set_game_state_0
load_message_ptrs
    ldx #0
-
    lda messages,y
    sty r0
    tay
    lda fontaddr_lo,y
    sta draw_ptrs,x
    inx
    lda fontaddr_hi,y
    sta draw_ptrs,x
    ldy r0
    iny
    inx
    cpx #10*2
    bne -
    jmp g.bank.rtsfar
    .send
    
    .section game_state_handler
    
handle_game_state   .block
    lda game_state
    ldx #size(_jmptable_cmp)
-   cmp _jmptable_cmp-1,x
    beq +
    dex
    bne -
+   lda _jmptable_ptr_hi,x
    pha
    lda _jmptable_ptr_lo,x
    pha
    rts
    
_ptrs := (g.bank.rtsfar, hard_mode_check, input_char, try_gen_answer) - 1
_jmptable_cmp .byte GS_CHECK_H, GS_CHECK, GS_NEW
_jmptable_ptr_lo    .byte <_ptrs
_jmptable_ptr_hi    .byte >_ptrs

try_gen_answer
    lda rng_state
    jsr _check_valid_alpha
    bcs _fail
    sta answer_chars
    tay
    lda rng_state+2
    jsr _check_valid_alpha
    bcs _fail
    sta answer_chars+1
    tax
    jsr check_first_two_chars
    beq _fail
    lda rng_state+1
    asl a
    cmp (r0),y
    bcs _fail
    ; clc
    adc #2
    tay
    jsr get_last_3_chars
    cpx #$80
    bcc _fail
    sta r0
    stx r0+1
    and #31
    sta answer_chars+2
    jsr shift_next_char
    sta answer_chars+3
    jsr shift_next_char
    sta answer_chars+4
    jsr enable_inputs_and_timers
    lda #GS_NONE
    jmp set_game_state_1
_fail
    jmp g.bank.rtsfar
    
_check_valid_alpha
    and #31
    cmp #0 ; c flag is needed, don't optimize
    beq _done
    cmp #'z'+1
_done
    rts
    
input_char
    ldx cursor_pos
    lda _cursor_to_char,x
    ldx guess_pos
    cmp #'='
    beq _enter
    cmp #'<'
    beq _del
    cpx #5*6
    bcs +
    sta guess_chars,x
    txa
    ; clc
    adc #6
    sta guess_pos
+   lda #GS_CHAR
    jmp set_game_state_1
    
_enter
    cpx #5*6
    bcs +
    ldy #messages.too_short-messages
    jmp popup_error_1
+
    ldy guess_chars-5*6,x ; 1st char
    lda guess_chars-4*6,x ; 2nd char
    tax
    jsr check_first_two_chars
    beq _not_word
    tay
    jsr disble_inputs_and_timers
-
    jsr get_last_3_chars
    sta r0
    stx r0+1
    ldx guess_pos
    and #31
    cmp guess_chars-3*6,x ; 3rd char
    bne +
    jsr shift_next_char
    cmp guess_chars-2*6,x ; 4th char
    bne +
    jsr shift_next_char
    cmp guess_chars-1*6,x ; 5th char
    beq _valid_word
+   
    ; are we low on frame time?
    lda INTIM
    cmp #6
    bcs +
    tya
    pha
    jsr g.bank.end_frame_0
    pla
    tay
+   cpy #0
    bne -
    beq _not_word
_valid_word
    lda flags
    ; prevent switching difficulty at this point
    ora #FLAGS_NO_MODE
    sta flags
    and #FLAGS_HARD_MODE
    beq +
    lda guess_pos
    cmp #5*6 ; first guess?
    beq +
    lda #GS_CHECK_H
    jmp set_game_state_1
+   jmp set_game_state_reveal
    
_not_word
    jsr enable_inputs_and_timers
    ldy #messages.not_a_word-messages
    jmp popup_error_1
    
_del
    cpx #1*6
    bcc +
    txa
    ; sec
    sbc #6
    sta guess_pos
    tax
    lda #' '
    sta guess_chars,x
+   lda #GS_DEL
    jmp set_game_state_1
    
_cursor_to_char
    .text "qwertyuiopasdfghjkl=zxcvbnm<"
    
hard_mode_check
    ldx guess_pos
    ldy #5
_loop
    txa
    sec
    sbc #6
    tax
    lda guess_chars-1,x
    bmi _yellow
    cmp #$40
    bcc _blank
    ; check for same letter at required position
    and #$1f
    cmp guess_chars,x
    beq _green_continue
    pha
    tya
    clc
    adc #'0'
    sta r1
    ldy #messages.exp_at-messages
    jsr popup_error_1
    ; fill in missing letters
    ldx #9*2
    jsr _set_fontaddr
    pla
    sta r1
    ldx #4*2
    bne _error_done
    
_yellow
    ; check for reuse in the whole word
    and #$1f
_green_continue
    stx r0
    ldx guess_pos
    bne +
-   cmp guess_chars,x
    beq _yellow_done
+   .rept 6
        dex
    .next
    bpl -
    sta r1
    ldy #messages.needs-messages
    jsr popup_error_1
    ; fill in missing letters
    ldx #7*2
_error_done
    jsr enable_inputs_and_timers
    jmp _set_fontaddr
    
_yellow_done
    ldx r0
_blank
    dey
    bne _loop
    jmp set_game_state_reveal
    
_set_fontaddr
    ; we don't have an access to fontaddr table here...
    ; r1 = char, x = offset from draw_ptrs to write fontaddr to
    lda #0      ; x256
    .rept 4
        lsr r1
        ror a
    .next       ; x16
    ; clc
    ; adc #<gfx_font
    sta draw_ptrs,x
    lda r1
    adc #>gfx_font
    sta draw_ptrs+1,x
    jmp g.bank.rtsfar
    
disble_inputs_and_timers
    lda flags
    ora #(FLAGS_NO_INPUT | FLAGS_NO_TIMER)
    sta flags
    rts
    
enable_inputs_and_timers
    lda flags
    and #~(FLAGS_NO_INPUT | FLAGS_NO_TIMER)
    sta flags
    rts
    
check_first_two_chars
    ; x = 2nd char, y = 1st char
    ; returns zf = invalid, a = word table length
    ; r0+y = pointer to word table length, r1 = word table pointer
    lda wordlist_1_ptrs_lo-1,y
    sta r1
    lda wordlist_1_ptrs_hi-1,y
    sta r1+1
    lda _mul26_lo-1,y
    clc
    adc #<wordlist_2_ofs
    sta r0
    lda _mul26_hi-1,y
    adc #>wordlist_2_ofs
    sta r0+1
    ldy #0
    dex
    beq _done
-   lda (r0),y
    beq +
    clc
    adc r1
    sta r1
    bcc +
    inc r1+1
+   iny
    dex
    bne -
_done
    lda (r0),y
    rts
    
_mul26_lo   .byte <(range(26)*26)
_mul26_hi   .byte >(range(26)*26)

get_last_3_chars
    ; r1+y-2 = word table pointer
    ; returns xa = last 3 chars, y = y-2
    lda r1+1
    ldx #-1
    sec
-   sbc #$20
    inx
    bcs -
    dey
    jmp g.bank.get_word_far
    
shift_next_char
    ; (u16) r0 >>= 5
    lda r0
    .rept 5
    lsr r0+1
    ror a
    .next
    sta r0
    and #31
    rts

    .bend
    
    ; popups (bank 1)
    
popup_error_1
    lda #GS_ERROR
popup_1
    jsr set_game_state_1
    jmp g.bank.load_message_ptrs_0
    
    ; bank 0 routine mirrors
    
set_game_state_reveal
    ; also need to prepare for animation
    lda guess_pos
    sec
    sbc #5*6
    sta guess_pos
    lda #5*8+5
    sta r1
    lda #GS_REVEAL
    
set_game_state_1
    sta game_state
    lda #0
    sta anim_frame
    jmp g.bank.rtsfar
    
update_reveal_endgame
    ; clear all markings on answer_chars for the next line
    ldx #5-1
-   lda answer_chars,x
    and #$1f
    sta answer_chars,x
    dex
    bpl -
    ; how many green tiles not revealed?
    lda r1
    and #7
    beq _win
    lda guess_pos
    cmp #5*6+5
    bcs _lose
    ; continue in the next row
    sec
    sbc #5*6-1
    sta guess_pos
    lda #~(FLAGS_NO_INPUT | FLAGS_NO_TIMER)
    ldx #GS_NONE
    bcs _set_and_done
    
_win
    ; increment score
    lda cur_score
    ldx cur_score+1
    cmp #$99
    bcc +
    cpx #$99
    bcs _score_done
+   sed
    ; clc
    adc #1
    sta cur_score
    tay
    txa
    adc #0
    sta cur_score+1
    cld
    cmp max_score+1
    bcc _score_done
    ; bne +
    cpy max_score
    bcc _score_done
+   sty max_score
    sta max_score+1
_score_done
    ; get win message based on guess position
    ldx guess_pos
    ldy _win_msg_ptrs-5*6,x
    jsr g.bank.load_message_ptrs_0
    ldx #GS_WIN
    bne _set_end_game
    
_win_msg_ptrs
    .byte messages.win_1-messages
    .byte messages.win_2-messages
    .byte messages.win_3-messages
    .byte messages.win_4-messages
    .byte messages.win_5-messages
    .byte messages.win_6-messages
    
_lose
    ldx #GS_LOSE
_set_end_game
    lda #~FLAGS_NO_INPUT
_set_and_done
    and flags
    sta flags
    txa
    jmp set_game_state_1
    
    .send
    