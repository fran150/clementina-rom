; Raw MIA RAM access. Foreground-only services; arguments are little endian.
; Every DMA request uses disjoint ranges, including when the whole move overlaps.
; Only reserved descriptors F4/F5 are changed; IRQ users of A/B remain independent.
.macpack longbranch
.segment "CODE"
.export mia_mem_read, mia_mem_write, mia_mem_copy, mia_mem_fill
.export km_src, km_dst, km_count, km_value

km_src:   .res 3,0
km_dst:   .res 3,0
km_count: .res 3,0
km_value: .byte 0
km_src_end: .res 3,0
km_dst_end: .res 3,0
km_span:  .res 3,0              ; max disjoint copy chunk / available fill bytes
km_chunk: .res 2,0
km_limit: .res 3,0
km_back:  .byte 0

; Select/seek descriptor A from km_src (X=0) or km_dst (X=3).
; Caller fences interrupts. Stepping is disabled explicitly, so prior use of
; these scratch descriptors cannot affect byte reads or writes.
km_seek:
        sta IDXA_SELECT
        lda #CFG_IDXA_FLAGS
        sta CFG_SELECT
        stz CFG_PORT
        lda #CFG_IDXA_ADDR_H
        sta CFG_SELECT
        lda km_src+2,x
        sta CFG_PORT
        lda #CFG_IDXA_ADDR_M
        sta CFG_SELECT
        lda km_src+1,x
        sta CFG_PORT
        lda #CFG_IDXA_ADDR_L
        sta CFG_SELECT
        lda km_src,x
        sta CFG_PORT
        rts

; Read from km_src -> A. Write km_value to km_dst. BASIC validates addresses.
mia_mem_read:
        php
        sei
        ldx #0
        lda #KIDX_MEMORY_SRC
        jsr km_seek
        lda IDXA_PORT
        plp
        rts
mia_mem_write:
        php
        sei
        ldx #3
        lda #KIDX_MEMORY_DST
        jsr km_seek
        lda km_value
        sta IDXA_PORT
        plp
        rts

; Validate [address,address+count) and calculate its exclusive end.
; X=0 source or 3 destination. C=1 valid. Addresses must be below $40000,
; even for an empty range; exclusive ends may equal $40000.
km_range:
        lda km_src+2,x
        cmp #4
        bcs @bad
        clc
        lda km_src,x
        adc km_count
        sta km_src_end,x
        lda km_src+1,x
        adc km_count+1
        sta km_src_end+1,x
        lda km_src+2,x
        adc km_count+2
        sta km_src_end+2,x
        bcs @bad
        cmp #4
        bcc @ok
        bne @bad
        lda km_src_end,x
        ora km_src_end+1,x
        bne @bad
@ok:    sec
        rts
@bad:   clc
        rts

km_remaining:
        lda km_count
        ora km_count+1
        ora km_count+2
        rts
km_done:
        sec
        rts

mia_mem_copy:
        ldx #0
        jsr km_range
        jcc @bad
        ldx #3
        jsr km_range
        jcc @bad
        jsr km_remaining
        beq km_done
        ; Signed destination-source, then absolute magnitude. A backward
        ; move starts at the ends; chunk size never exceeds this distance.
        sec
        lda km_dst
        sbc km_src
        sta km_span
        lda km_dst+1
        sbc km_src+1
        sta km_span+1
        lda km_dst+2
        sbc km_src+2
        sta km_span+2
        bcc @forward
        lda #1
        sta km_back
        lda km_span
        ora km_span+1
        ora km_span+2
        beq km_done
        ldx #5
@ends:  lda km_src_end,x
        sta km_src,x
        dex
        bpl @ends
        bra @loop
@forward:
        stz km_back
        sec
        lda #0
        sbc km_span
        sta km_span
        lda #0
        sbc km_span+1
        sta km_span+1
        lda #0
        sbc km_span+2
        sta km_span+2
@loop:  jsr km_choose_chunk
        lda km_back
        beq @dma
        ldx #0
        jsr km_sub_addr
        ldx #3
        jsr km_sub_addr
@dma:   jsr km_dma
        lda km_back
        bne @count
        ldx #0
        jsr km_add_addr
        ldx #3
        jsr km_add_addr
@count: jsr km_sub_count
        jsr km_remaining
        bne @loop
        jmp km_done
@bad:   clc
        rts

mia_mem_fill:
        ldx #3
        jsr km_range
        bcc @bad
        jsr km_remaining
        beq @done
        jsr wait_cmd_dma
        ; One seed byte, then copy already-filled bytes into disjoint space.
        jsr mia_mem_write
        ldx #2
@base:  lda km_dst,x
        sta km_src,x
        dex
        bpl @base
        lda #1
        sta km_span
        sta km_chunk
        stz km_span+1
        stz km_span+2
        stz km_chunk+1
@advance:
        ldx #3
        jsr km_add_addr
        jsr km_sub_count
        jsr km_remaining
        beq @done
        jsr km_choose_chunk
        jsr km_dma
        clc
        lda km_span
        adc km_chunk
        sta km_span
        lda km_span+1
        adc km_chunk+1
        sta km_span+1
        bcc @advance
        lda #$FF                ; cap reusable source length at DMA's limit
        sta km_span
        sta km_span+1
        bra @advance
@done:  jmp km_done
@bad:   clc
        rts

; km_chunk = min(count, span, 65535); count and span are both nonzero.
km_choose_chunk:
        lda #$FF
        sta km_chunk
        sta km_chunk+1
        lda km_count+2
        bne @span
        lda km_count
        sta km_chunk
        lda km_count+1
        sta km_chunk+1
@span:  lda km_span+2
        bne @done
        lda km_span+1
        cmp km_chunk+1
        bcc @smaller
        bne @done
        lda km_span
        cmp km_chunk
        bcs @done
@smaller:
        lda km_span
        sta km_chunk
        lda km_span+1
        sta km_chunk+1
@done:  rts

km_add_addr:
        clc
        lda km_src,x
        adc km_chunk
        sta km_src,x
        lda km_src+1,x
        adc km_chunk+1
        sta km_src+1,x
        lda km_src+2,x
        adc #0
        sta km_src+2,x
        rts
km_sub_addr:
        sec
        lda km_src,x
        sbc km_chunk
        sta km_src,x
        lda km_src+1,x
        sbc km_chunk+1
        sta km_src+1,x
        lda km_src+2,x
        sbc #0
        sta km_src+2,x
        rts
km_sub_count:
        sec
        lda km_count
        sbc km_chunk
        sta km_count
        lda km_count+1
        sbc km_chunk+1
        sta km_count+1
        lda km_count+2
        sbc #0
        sta km_count+2
        rts

; Start a <=65535-byte transfer and wait for BOTH command and DMA completion.
; DMA count=0 means source limit-current, an exclusive end, not a zero transfer.
km_dma:
        jsr wait_cmd_dma
        clc
        lda km_src
        adc km_chunk
        sta km_limit
        lda km_src+1
        adc km_chunk+1
        sta km_limit+1
        lda km_src+2
        adc #0
        sta km_limit+2
        php
        sei
        ldx #3
        lda #KIDX_MEMORY_DST
        jsr km_seek
        ldx #0
        lda #KIDX_MEMORY_SRC
        jsr km_seek
        lda #CFG_IDXA_LIMIT_H
        sta CFG_SELECT
        lda km_limit+2
        sta CFG_PORT
        lda #CFG_IDXA_LIMIT_M
        sta CFG_SELECT
        lda km_limit+1
        sta CFG_PORT
        lda #CFG_IDXA_LIMIT_L
        sta CFG_SELECT
        lda km_limit
        sta CFG_PORT
        lda #KIDX_MEMORY_SRC
        sta CMD_PARAM1
        lda #KIDX_MEMORY_DST
        sta CMD_PARAM2
        stz CMD_PARAM3
        lda #CMD_COPY_INDEXES
        sta CMD_TRIGGER
        plp
        jmp wait_cmd_dma
