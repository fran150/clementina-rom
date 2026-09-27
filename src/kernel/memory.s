; Raw MIA RAM access. Foreground-only services; arguments are little endian.
; Every DMA request uses disjoint ranges, including when the whole move overlaps.
; Only reserved descriptors F4/F5 are changed; IRQ users of A/B remain independent.
.macpack longbranch
.segment "KERNCODE"
.export mia_mem_read, mia_mem_write, mia_mem_copy, mia_mem_fill
.export mia_mem_rect, mia_mem_fill_rect
.export km_src, km_dst, km_count, km_value
.export km_rows, km_sstride, km_dstride

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
; Rectangles: km_rows rows of km_count bytes; strides are row starts apart.
km_rows:    .res 2,0
km_sstride: .res 2,0            ; keep km_dstride right after: indexed by Y=0/2
km_dstride: .res 2,0
km_prod:  .res 3,0
km_mul:   .res 2,0
km_n:     .byte 0
km_cmd:   .byte 0
km_first: .res 6,0              ; mia_mem_fill_rect: the first row's km_dst, km_count

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
        stz km_n                ; COPY_INDEXES: third parameter 0, up to the limit
        lda #CMD_COPY_INDEXES
; A = command and km_n = its third parameter (COPY_RECT: rows, 0 = 256).
km_dma_cmd:
        sta km_cmd
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
        lda km_n
        sta CMD_PARAM3
        lda km_cmd
        sta CMD_TRIGGER
        plp
        jmp wait_cmd_dma

; ----------------------------------------------------------------------------
; Rectangles. km_rows rows of km_count bytes (at most 65535): row r reads
; km_src + r*km_sstride and writes km_dst + r*km_dstride. C=0 means invalid
; - a longer row, or either rectangle reaching past $3FFFF - and nothing is
; written. Zero rows or zero bytes do nothing. DMA copies each row forward,
; so the rectangles must not overlap, except by repeating one row (a source
; stride of 0, as mia_mem_fill_rect does).
; ----------------------------------------------------------------------------
mia_mem_rect:
        jsr km_rect_empty
        beq km_rect_done
        jsr km_rect_valid
        bcc km_rect_bad
        lda #KIDX_MEMORY_SRC        ; strides live in the descriptors' steps
        ldy #0
        jsr km_set_step
        lda #KIDX_MEMORY_DST
        ldy #2
        jsr km_set_step
        lda km_count                ; each row is km_chunk bytes: source limit
        sta km_chunk
        lda km_count+1
        sta km_chunk+1
@batch: lda km_rows+1               ; up to 256 rows per COPY_RECT (0 = 256)
        beq @last
        stz km_n
        bra @go
@last:  lda km_rows
        sta km_n
@go:    lda #CMD_COPY_RECT
        jsr km_dma_cmd
        lda km_rows+1
        beq km_rect_done            ; fewer than 256 rows: that was the last
        dec km_rows+1
        lda km_rows
        ora km_rows+1
        beq km_rect_done
        clc                         ; the next batch starts 256 rows on
        lda km_src+1
        adc km_sstride
        sta km_src+1
        lda km_src+2
        adc km_sstride+1
        sta km_src+2
        clc
        lda km_dst+1
        adc km_dstride
        sta km_dst+1
        lda km_dst+2
        adc km_dstride+1
        sta km_dst+2
        bra @batch
km_rect_done:
        sec
        rts
km_rect_bad:
        clc
        rts

; Fill km_rows rows of km_count bytes with km_value, row r at km_dst +
; r*km_dstride: fill the first row, then repeat it with a source stride of 0.
; The whole rectangle is checked before anything is written.
mia_mem_fill_rect:
        jsr km_rect_empty
        beq km_rect_done
        stz km_sstride
        stz km_sstride+1
        ldx #2
@src:   lda km_dst,x                ; check the destination as both rectangles
        sta km_src,x
        sta km_first,x
        lda km_count,x
        sta km_first+3,x
        dex
        bpl @src
        jsr km_rect_valid
        bcc km_rect_bad
        jsr mia_mem_fill            ; the first row
        ldx #2
@again: lda km_first,x              ; mia_mem_fill moved km_dst and km_count on
        sta km_src,x
        sta km_dst,x
        lda km_first+3,x
        sta km_count,x
        dex
        bpl @again
        clc                         ; the copies start one row down
        lda km_dst
        adc km_dstride
        sta km_dst
        lda km_dst+1
        adc km_dstride+1
        sta km_dst+1
        lda km_dst+2
        adc #0
        sta km_dst+2
        lda km_rows
        bne :+
        dec km_rows+1
:       dec km_rows
        jmp mia_mem_rect

; Z=1 when there is nothing to do: no rows or no bytes per row.
km_rect_empty:
        lda km_rows
        ora km_rows+1
        beq @done
        lda km_count
        ora km_count+1
        ora km_count+2
@done:  rts

; C=1 when rows fit in 65535 bytes and both rectangles end by $40000.
km_rect_valid:
        lda km_count+2
        jne km_rect_bad
        ldx #0
        ldy #0
        jsr km_rect_fits
        jcc km_rect_bad
        ldx #3
        ldy #2
; C=1 when km_src,x + (km_rows - 1) * km_sstride,y + km_count <= $40000.
; Shift-and-add straight into the end address, stopping once it passes $4FFFF.
km_rect_fits:
        clc
        lda km_src,x
        adc km_count
        sta km_limit
        lda km_src+1,x
        adc km_count+1
        sta km_limit+1
        lda km_src+2,x
        adc #0
        sta km_limit+2
        sec
        lda km_rows
        sbc #1
        sta km_mul
        lda km_rows+1
        sbc #0
        sta km_mul+1
        lda km_sstride,y
        sta km_prod
        lda km_sstride+1,y
        sta km_prod+1
        stz km_prod+2
@bit:   lsr km_mul+1                ; next bit of rows - 1, lowest first
        ror km_mul
        bcc @skip
        clc
        lda km_limit
        adc km_prod
        sta km_limit
        lda km_limit+1
        adc km_prod+1
        sta km_limit+1
        lda km_limit+2
        adc km_prod+2
        sta km_limit+2
        cmp #5
        bcs @bad
@skip:  lda km_mul
        ora km_mul+1
        beq @end
        asl km_prod                 ; the stride doubles for the next bit
        rol km_prod+1
        rol km_prod+2
        lda km_prod+2
        cmp #5                      ; and a bit is still to come: too far
        bcc @bit
        bra @bad
@end:   lda km_limit+2
        cmp #4
        bcc @ok
        bne @bad
        lda km_limit
        ora km_limit+1
        bne @bad
@ok:    sec
        rts
@bad:   clc
        rts

; Bind descriptor A to window A and set its step from km_sstride,y (Y=0) or
; km_dstride (Y=2). km_seek leaves steps alone, so they last across batches.
km_set_step:
        sta IDXA_SELECT
        lda #CFG_IDXA_STP_L
        sta CFG_SELECT
        lda km_sstride,y
        sta CFG_PORT
        lda #CFG_IDXA_STP_H
        sta CFG_SELECT
        lda km_sstride+1,y
        sta CFG_PORT
        rts
