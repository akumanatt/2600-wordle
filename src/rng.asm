    ; random number generator routines
    ; using 8-bit lag-2 MWC PRNG with multiplier of 224

    .section rng_code
rng     .block
init
    ; seed the initial value with (hopefully) uninitalized memory and I/O reads
    ldx #$2f
-
    lda rng_state
    eor $70,x
    sta rng_state
    lda rng_state+1
    eor $a0,x
    sta rng_state+1
    lda rng_state+2
    eor $d0,x
    bne +
    ; prevent both x and c being 0 which kills the generator
    adc #1
+   sta rng_state+2
    dex
    bpl -
    rts
    
advance
    ; also returns the new RNG state to A, X and Y
    ldx rng_state
    lda #0          ; 256x
    lsr rng_state
    ror a           ; 128x
    lsr rng_state
    ror a           ; 64x
    lsr rng_state
    ror a           ; 32x
    sec
    eor #$ff
    adc #0
    tay
    txa
    sbc rng_state   ; 256x-32x = 224x
    tax
    tya
    clc
    adc rng_state+2 ; 224x+c
    bcc +
    inx
+   ldy rng_state+1
    sty rng_state
    sta rng_state+1
    stx rng_state+2
    rts

    .bend
    .send
    