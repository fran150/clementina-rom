; ============================================================================
; clementina_extra.s - Clementina BASIC console glue (EXTRA segment)
; ----------------------------------------------------------------------------
; Thin thunks from BASIC's console contract into the Clementina kernel jump
; table. In the combined image the kernel lives at $0400 and owns the console.
; Keep these addresses in sync with src/kernel/kernel.inc / docs/memory-map.md.
; ============================================================================

.segment "EXTRA"
.export BASIC_COLD_START, BASIC_WARM_START, MONRDKEY, MONRDKEY_NB, MONCOUT, MONRDLINE
.export bg_play_tick

KERN_CHROUT       = $0406
KERN_CHRIN        = $0409
KERN_GETKEY_NB    = $040C
KERN_EDITKEY      = $0424
KERN_CHROUT_GLYPH = $0427
KERN_WOZMON       = $042A
KERN_SET_BACKDROP = $042D

; Console control codes (CHROUT interprets these) and overlay geometry. Keep in
; sync with src/kernel/kernel.inc.
CHR_FF            = $0C    ; form feed: clear screen and home the cursor
CHR_CRSR_DOWN     = $11    ; cursor down one row
CHR_HOME          = $13    ; cursor to top-left
CHR_CRSR_RIGHT    = $1D    ; cursor right one cell
SCR_COLS          = 40
SCR_ROWS          = 25

; ----------------------------------------------------------------------------
; MIA register subset used by the sound statements (BASIC does not include
; kernel.inc). Full map: src/kernel/kernel.inc + the clementina-mia repo.
; Sound writes go through MIA index window B so they never contend with the
; kernel console's window A.
; ----------------------------------------------------------------------------
CFG_SELECT        = $FFE2
CFG_PORT          = $FFE3
IDXB_PORT         = $FFE4
IDXB_SELECT       = $FFE5
CMD_PARAM1        = $FFE6
CMD_PARAM2        = $FFE7
CMD_PARAM3        = $FFE8
CMD_TRIGGER       = $FFE9

CFG_IDXB_ADDR_L   = $10    ; CFG field ids that set window B's 24-bit address
CFG_IDXB_ADDR_M   = $11
CFG_IDXB_ADDR_H   = $12

; ----------------------------------------------------------------------------
; MIA register subset used by the video statements (Phase 1, see
; docs/basic-video.md). These go through window A (shared with the console
; cursor - see vid_seek/vid_layer_set above), not window B. Keep in sync with
; src/kernel/kernel.inc.
; ----------------------------------------------------------------------------
IDXA_PORT           = $FFE0
IDXA_SELECT         = $FFE1

CFG_IDXA_ADDR_L     = $00  ; CFG field ids that set window A's 24-bit address
CFG_IDXA_ADDR_M     = $01
CFG_IDXA_ADDR_H     = $02

VIDX_RENDER_CONTROL = $80  ; streams the 32-byte render control page ($20..)
VIDX_LAYER_ENABLE   = $81  ; 1 byte: background/overlay/sprite enables
VIDX_PALETTE_0      = $90  ; first of 16 palette-bank indexes

CMD_VIDEO_SET_MODE  = $43

; LAYER_ENABLE bits (bit0 background, bit1 overlay, bit2 sprite)
LAYER_BACKGROUND    = %00000001
LAYER_SPRITE         = %00000100

; VIDEO_MODE: bit0 = video enable.
VIDEO_MODE_ENABLE   = %00000001

; Render control page ($00020-$0003F) field addresses - see vid_seek. Mid/high
; address bytes are always $00: the whole page fits in page 0 of MIA RAM.
RC_BG_VIEWPORT_MODE = $22
RC_BG_ACTIVE_SET    = $23
RC_SCROLL_X_L       = $24  ; +1 = high byte
RC_SCROLL_Y_L       = $26  ; +1 = high byte
RC_BG_CHR_BANK      = $28
RC_BG_ALT_CHR_BANK  = $29
RC_SPRITE_CHR_BANK  = $2C
RC_CHR_1BPP_MASK    = $2D
RC_CHR_1BPP_PLANES  = $2E
RC_OAM_LAST_INDEX   = $30

; Bulk regions' base addresses (24-bit MIA RAM address, L/M/H) - see vid_seek_abs
; (Phase 2). Bank/table strides are added at runtime.
MIA_CHR_BASE_L      = $00  ; CHR banks: $00200, 6144 bytes/bank
MIA_CHR_BASE_M      = $02
MIA_BG_NT_BASE_L    = $00  ; BG nametables: $0C200, 1000 bytes/table
MIA_BG_NT_BASE_M    = $C2
MIA_BG_ATTR_BASE_L  = $40  ; BG attributes: $0E140, 1000 bytes/table
MIA_BG_ATTR_BASE_M  = $E1
MIA_OAM_BASE_L      = $50  ; OAM: $10850, 5 bytes/entry
MIA_OAM_BASE_M      = $08
MIA_OAM_BASE_H      = $01

; MIA audio (PWM PSG), layout version 2. State block $12000-$1204F: a 16-byte
; header then four 16-byte voice records. See clementina-mia docs/audio.md.
CMD_AUDIO_ENABLE  = $60
CMD_AUDIO_STOP    = $61
CMD_AUDIO_RESET   = $62
IIDX_AUDIO_ALL    = $D0    ; MIA index spanning the whole audio block

AUD_HDR_VOLUME    = $01    ; block offset: master volume (0-15)
AUDV_FREQ_L       = $00    ; voice-record field offsets
AUDV_PULSE_WIDTH  = $02
AUDV_ATTACK_DECAY = $03
AUDV_WAVEFORM     = $05
AUDV_PAN          = $06
AUDV_CONTROL      = $07
AUDV_VOLUME       = $08
AUD_GATE          = $01    ; CONTROL bit 0
AUD_GATE_RETRIG   = $03    ; CONTROL: GATE | RESET_PHASE

; Kernel free-running tick counter (16-bit LE, ~16 Hz at 1 MHz PHI2). Keep in
; sync with KJIFFY in src/kernel/kernel.inc. PLAY uses it for note timing.
KJIFFY            = $00F7

BASIC_COLD_START:
        jmp COLD_START

; Warm restart: keep the current program/variables and return to the READY
; prompt. Used by the kernel warmstart entry (KERN_WARMSTART) so a user can quit
; the WOZ monitor back to BASIC without losing their program.
BASIC_WARM_START:
        jmp RESTART

; A = character to print. Kernel CHROUT preserves A/X/Y.
MONCOUT:
        jmp KERN_CHROUT

; Blocking read; returns the character in A.
MONRDKEY:
        jmp KERN_CHRIN

; Non-blocking read; C=1 and A=char if available, else C=0.
MONRDKEY_NB:
        jmp KERN_GETKEY_NB

; Line-input reader: returns the next character of the screen-edited logical
; line (printable bytes then a terminating CR). BASIC's GETLN uses this so line
; editing runs in the kernel; GET keeps using the raw single-char MONRDKEY.
MONRDLINE:
        jmp KERN_EDITKEY

; Enter the WOZ monitor. Return to BASIC from WozMon with Q.
BASIC_MON:
        jmp KERN_WOZMON

; ----------------------------------------------------------------------------
; BASIC console statements
;
; MON       enter the WOZ monitor; return to BASIC from WozMon with Q.
; CLS       clear the screen and home the cursor.
; CRSR x,y  move the cursor to column x (0..SCR_COLS-1), row y (0..SCR_ROWS-1).
;           0,0 is the top-left corner; 39,24 the bottom-right.
;
; Both drive the cursor through the kernel console (MONCOUT/CHROUT) so the
; software cursor glyph and the logical-line link table stay consistent: CLS
; emits a form feed (clrscr + home), CRSR homes then steps the cursor with
; the cursor-down / cursor-right control codes. Out-of-range arguments raise
; ILLEGAL QUANTITY, matching COLOR/STYLE.
;
; NOTE: these keyword names are short on purpose. BASIC's tokenizer indexes the
; keyword name table with an 8-bit Y register, so ALL keyword names plus the
; terminator must fit in 256 bytes (see token.s). Long names overflow the table
; and hang the tokenizer on every typed line.
; ----------------------------------------------------------------------------
BASIC_CLS:
        lda     #$00
        sta     POSX                    ; BASIC column tracker: home is column 0
        lda     #CHR_FF
        jmp     MONCOUT                 ; clear + home (tail call; cursor handled)

BASIC_CRSR:
        jsr     GETBYT                  ; X = column
        cpx     #SCR_COLS
        bcs     @iq
        stx     LINNUM                  ; survives the second GETBYT (POKE pattern)
        jsr     COMBYTE                 ; X = row
        cpx     #SCR_ROWS
        bcs     @iq
        lda     #CHR_HOME
        jsr     MONCOUT                 ; cursor to (0,0); preserves X
        txa                             ; A = row count (sets Z)
        beq     @cols
@rows:
        lda     #CHR_CRSR_DOWN
        jsr     MONCOUT                 ; preserves X
        dex
        bne     @rows
@cols:
        ldx     LINNUM
        beq     @done
@colloop:
        lda     #CHR_CRSR_RIGHT
        jsr     MONCOUT                 ; preserves X
        dex
        bne     @colloop
@done:
        lda     LINNUM                  ; column = LINNUM (preserved through MONCOUT)
        sta     POSX                    ; keep BASIC's column (POS/TAB/PRINT) in sync
        rts
@iq:
        jmp     IQERR

; MONCOUT routes A through the kernel console; chrout preserves A/X/Y, so the
; loops above can hold their counter in X across the call.

; ----------------------------------------------------------------------------
; BCOLOR n  set the screen background to the same color COLOR n gives text.
;
; The backdrop is a palette selector: bits 3-6 pick the palette bank, bits 0-2
; the color index within it (see VIDX_BACKDROP_COLOR). COLOR n draws text in
; color index 1 of palette bank n, so BCOLOR n = (n<<3)|1 paints the background
; in that exact ink color. n is 0-15, matching COLOR; BCOLOR 6 restores the
; default backdrop blue (palette 6's ink is the backdrop blue - see the startup
; palette in docs/phase5-charset-keyboard.md). Out-of-range raises ILLEGAL
; QUANTITY, like COLOR.
;
; BCOLOR is an extension-token statement (the primary keyword table is full):
; it is registered in the EXT_NAME_TABLE / EXT_ADDRESS_TABLE in token.s and
; dispatched via the TOKEN_EXT prefix. It is entered exactly like a primary
; statement handler (A = first arg char, TXTPTR positioned), so nothing here is
; special-cased.
; ----------------------------------------------------------------------------
BASIC_BCOLOR:
        jsr     GETBYT                  ; X = color 0-15
        cpx     #$10
        bcs     @iq
        txa
        asl     a
        asl     a
        asl     a                       ; n<<3 -> palette bank field (bits 3-6)
        ora     #$01                    ; color index 1 = the ink color of palette n
        jmp     KERN_SET_BACKDROP       ; tail call; kernel does the IRQ-safe write
@iq:
        jmp     IQERR

; ----------------------------------------------------------------------------
; Background/sprite/CHR/palette/video-mode control - Phase 1 (see
; docs/basic-video.md). These are all direct register wrappers, same shape as
; BCOLOR above: parse args (GETBYT/COMBYTE, IQERR on out-of-range), write the
; MIA render-control page. Phase 2 (BGCHAR/BGLOAD/BGALOAD/OAMLOAD/CHRLOAD/
; SPRITE and friends) needs a DATA-stream bulk-read primitive and mode-aware
; cell addressing and lands separately.
;
; Shared helpers:
;   vid_seek A=page offset  - bind window A to VIDX_RENDER_CONTROL and position
;     its current address at render-control page offset A (mid/high byte are
;     always $00 - the whole 32-byte page sits in page 0 of MIA RAM). Must be
;     called inside an sei fence: it walks CFG_SELECT/CFG_PORT and window A is
;     shared with the console cursor, which the cursor-blink IRQ repositions.
;     Same trick snd_seek (below) uses for the audio block. Clobbers A.
;   vid_wr1 A=page offset, X=value - sei-fenced single-byte write via vid_seek.
;   vid_layer_set/vid_layer_clear A=mask - OR/AND-NOT mask into LAYER_ENABLE via
;     its own dedicated 1-byte index (VIDX_LAYER_ENABLE): a 1-byte window wraps
;     back to itself after each access, so read-modify-write needs no
;     reposition between the read and the write, unlike the shared 32-byte
;     render-control window used for everything else here.
; ----------------------------------------------------------------------------
vid_seek:
        pha
        lda     #VIDX_RENDER_CONTROL
        sta     IDXA_SELECT
        lda     #CFG_IDXA_ADDR_H
        sta     CFG_SELECT
        lda     #$00
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_M
        sta     CFG_SELECT
        lda     #$00
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_L
        sta     CFG_SELECT
        pla                             ; page offset -> current address low byte
        sta     CFG_PORT
        rts

vid_wr1:
        php
        sei
        jsr     vid_seek
        stx     IDXA_PORT
        plp
        rts

vid_layer_set:
        sta     TEMP1
        php
        sei
        lda     #VIDX_LAYER_ENABLE
        sta     IDXA_SELECT
        lda     IDXA_PORT
        ora     TEMP1
        sta     IDXA_PORT
        plp
        rts

vid_layer_clear:
        eor     #$FF
        sta     TEMP1
        php
        sei
        lda     #VIDX_LAYER_ENABLE
        sta     IDXA_SELECT
        lda     IDXA_PORT
        and     TEMP1
        sta     IDXA_PORT
        plp
        rts

CHR_BIT_TABLE:
        .byte   $01,$02,$04,$08,$10,$20,$40,$80

; BGON / BGOFF - background layer on/off (LAYER_ENABLE bit 0).
BASIC_BGON:
        lda     #LAYER_BACKGROUND
        jmp     vid_layer_set
BASIC_BGOFF:
        lda     #LAYER_BACKGROUND
        jmp     vid_layer_clear

; SPRON / SPROFF - sprite layer on/off (LAYER_ENABLE bit 2). Per-sprite
; show/hide is a field of the SPRITE statement (Phase 2), not a separate verb -
; this pair is only the whole-layer switch.
BASIC_SPRON:
        lda     #LAYER_SPRITE
        jmp     vid_layer_set
BASIC_SPROFF:
        lda     #LAYER_SPRITE
        jmp     vid_layer_clear

; VIDON / VIDOFF - whole video output on/off (VIDEO_MODE bit 0). Goes through
; CMD_VIDEO_SET_MODE (a queued MIA command, like SNDON/SNDOFF's CMD_AUDIO_*),
; not a plain index write.
BASIC_VIDON:
        lda     #VIDEO_MODE_ENABLE
        bne     vid_mode_cmd            ; immediate operand is nonzero: always taken
BASIC_VIDOFF:
        lda     #$00
vid_mode_cmd:
        sta     CMD_PARAM1
        php
        sei
        lda     #$00
        sta     CMD_PARAM2
        sta     CMD_PARAM3
        lda     #CMD_VIDEO_SET_MODE
        sta     CMD_TRIGGER
        plp
        rts

; BGMODE n : BG viewport mode 0-5 - how the BG layer's up-to-8 raw 40x25 tables
; tile together into one scrollable canvas (see docs/basic-video.md).
BASIC_BGMODE:
        jsr     GETBYT                  ; X = mode 0-5
        cpx     #$06
        jcs     snd_iqerr
        lda     #RC_BG_VIEWPORT_MODE
        jmp     vid_wr1

; BGSET n : 0/1, selects which of the two BG table sets (+4 to every raw table
; index) the current BGMODE arrangement is drawn from.
BASIC_BGSET:
        jsr     GETBYT                  ; X = 0 or 1
        cpx     #$02
        jcs     snd_iqerr
        lda     #RC_BG_ACTIVE_SET
        jmp     vid_wr1

; BGBANK n / BGALT n : CHR bank 0-7 the BG layer draws from normally / where a
; cell's CHR_ALT attribute bit is set.
BASIC_BGBANK:
        jsr     GETBYT                  ; X = bank 0-7
        cpx     #$08
        jcs     snd_iqerr
        lda     #RC_BG_CHR_BANK
        jmp     vid_wr1

BASIC_BGALT:
        jsr     GETBYT                  ; X = bank 0-7
        cpx     #$08
        jcs     snd_iqerr
        lda     #RC_BG_ALT_CHR_BANK
        jmp     vid_wr1

; SPRBANK n : CHR bank 0-7 sprites draw from.
BASIC_SPRBANK:
        jsr     GETBYT                  ; X = bank 0-7
        cpx     #$08
        jcs     snd_iqerr
        lda     #RC_SPRITE_CHR_BANK
        jmp     vid_wr1

; SPRCOUNT n : highest OAM index (0-255) the renderer scans each frame. Any
; byte value is valid - no range check.
BASIC_SPRCOUNT:
        jsr     GETBYT                  ; X = last OAM index to scan
        lda     #RC_OAM_LAST_INDEX
        jmp     vid_wr1

; SCROLL x,y : BG layer pixel scroll, two 16-bit values (0-65535; wraps per the
; current BGMODE's canvas size in hardware). Word args parsed like FREQ's hz.
BASIC_SCROLL:
        jsr     FRMNUM
        jsr     GETADR                  ; x -> LINNUM/LINNUM+1
        php
        sei
        lda     #RC_SCROLL_X_L
        jsr     vid_seek
        lda     LINNUM
        sta     IDXA_PORT
        lda     LINNUM+1
        sta     IDXA_PORT
        plp
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR                  ; y -> LINNUM/LINNUM+1
        php
        sei
        lda     #RC_SCROLL_Y_L
        jsr     vid_seek
        lda     LINNUM
        sta     IDXA_PORT
        lda     LINNUM+1
        sta     IDXA_PORT
        plp
        rts

; CHRMODE bank,flag : mark CHR bank 0-7 as 1bpp (flag<>0) or 3bpp (flag=0) -
; read-modify-write of CHR_1BPP_MASK's bit `bank`. Re-seeks between the read
; and the write: the 32-byte render-control window steps past the target byte
; on the read, unlike the dedicated 1-byte LAYER_ENABLE index above.
BASIC_CHRMODE:
        jsr     GETBYT                  ; X = bank 0-7
        cpx     #$08
        jcs     snd_iqerr
        txa
        pha
        jsr     COMBYTE                 ; X = flag (0 = off, nonzero = on)
        pla                             ; A = bank
        tay
        lda     CHR_BIT_TABLE,y         ; A = 1 << bank
        sta     TEMP1
        cpx     #$00
        beq     @clr
        php
        sei
        lda     #RC_CHR_1BPP_MASK
        jsr     vid_seek
        lda     IDXA_PORT
        ora     TEMP1
        tax
        lda     #RC_CHR_1BPP_MASK
        jsr     vid_seek
        stx     IDXA_PORT
        plp
        rts
@clr:
        lda     TEMP1
        eor     #$FF
        sta     TEMP1
        php
        sei
        lda     #RC_CHR_1BPP_MASK
        jsr     vid_seek
        lda     IDXA_PORT
        and     TEMP1
        tax
        lda     #RC_CHR_1BPP_MASK
        jsr     vid_seek
        stx     IDXA_PORT
        plp
        rts

; CHRPLANE bg,spr,ovl : which of a 1bpp CHR bank's 3 planes each layer decodes
; (0-3 each; only matters for banks CHRMODE marked 1bpp). Packs bg | (spr<<2) |
; (ovl<<4) and overwrites the whole CHR_1BPP_PLANES byte in one shot.
BASIC_CHRPLANE:
        jsr     GETBYT                  ; X = bg plane 0-3
        cpx     #$04
        jcs     snd_iqerr
        txa
        pha
        jsr     COMBYTE                 ; X = sprite plane 0-3
        cpx     #$04
        jcs     snd_iqerr
        txa
        asl     a
        asl     a                       ; sprite plane << 2
        sta     TEMP1
        pla                             ; A = bg plane
        ora     TEMP1
        pha
        jsr     COMBYTE                 ; X = overlay plane 0-3
        cpx     #$04
        jcs     snd_iqerr
        txa
        asl     a
        asl     a
        asl     a
        asl     a                       ; overlay plane << 4
        sta     TEMP1
        pla                             ; A = bg | (sprite<<2)
        ora     TEMP1
        tax
        lda     #RC_CHR_1BPP_PLANES
        jmp     vid_wr1

; PALETTE bank,index,r,g,b : write one palette RGB565 entry. bank 0-15, index
; 0-7 (one of that bank's 8 colors), r 0-31, g 0-63, b 0-31.
;
; Target address = $100 + bank*16 + index*2 (max $100+240+14 = $1FE), so the
; +$100 base lands entirely in the address's middle byte (always $01) and
; bank*16+index*2 (max 254) is the whole low byte - no 16-bit carry to track.
; bank recovers from that low byte as (bank*16+index*2)>>4, since index*2 < 16
; never carries into the bank*16 nibble; selecting VIDX_PALETTE_0+bank (rather
; than any fixed bank index) keeps the CFG-forced address within that
; descriptor's own declared 16-byte range.
BASIC_PALETTE:
        jsr     GETBYT                  ; X = bank 0-15
        cpx     #$10
        jcs     snd_iqerr
        txa
        asl     a
        asl     a
        asl     a
        asl     a                       ; bank << 4
        sta     TEMP1
        jsr     COMBYTE                 ; X = index 0-7
        cpx     #$08
        jcs     snd_iqerr
        txa
        asl     a                       ; index << 1
        clc
        adc     TEMP1
        sta     TEMP1                   ; TEMP1 = bank*16 + index*2
        jsr     COMBYTE                 ; X = r 0-31
        cpx     #$20
        jcs     snd_iqerr
        txa
        asl     a
        asl     a
        asl     a                       ; r << 3 -> high byte bits 7-3
        sta     TEMP2
        jsr     COMBYTE                 ; X = g 0-63
        cpx     #$40
        jcs     snd_iqerr
        txa
        pha
        lsr     a
        lsr     a
        lsr     a                       ; g >> 3 -> high byte bits 2-0
        ora     TEMP2
        sta     TEMP2                   ; TEMP2 = high byte = (r<<3)|(g>>3)
        pla
        and     #$07
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a                       ; (g&7) << 5 -> low byte bits 7-5
        sta     TEMP3
        jsr     COMBYTE                 ; X = b 0-31
        cpx     #$20
        jcs     snd_iqerr
        txa
        ora     TEMP3
        sta     TEMP3                   ; TEMP3 = low byte = ((g&7)<<5)|b

        php
        sei
        lda     TEMP1
        lsr     a
        lsr     a
        lsr     a
        lsr     a                       ; bank back out of TEMP1 (index*2 < 16)
        clc
        adc     #VIDX_PALETTE_0
        sta     IDXA_SELECT
        lda     #CFG_IDXA_ADDR_H
        sta     CFG_SELECT
        lda     #$00
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_M
        sta     CFG_SELECT
        lda     #$01
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_L
        sta     CFG_SELECT
        lda     TEMP1
        sta     CFG_PORT
        lda     TEMP3                   ; low byte first: the target address's
        sta     IDXA_PORT               ; first (lower) byte is the RGB565 low
        lda     TEMP2                   ; byte per the renderer's LE read
        sta     IDXA_PORT
        plp
        rts

; ----------------------------------------------------------------------------
; Background/sprite/CHR/palette bulk loading - Phase 2 (see docs/basic-video.md).
;
; Two shared primitives make these possible:
;
;   vid_seek_abs/vid_wr_abs - like vid_seek/vid_wr1, but for an arbitrary 24-bit
;     MIA RAM address (VID_ADDR/VID_ADDR2) instead of a render-control page
;     offset: CFG overrides window A's current address directly regardless of
;     which index is selected as the anchor, and a write always lands at that
;     exact byte (limit/wrap only affects the *next* auto-step, which nothing
;     here relies on - every access re-seeks first). VID_ADDR2/vid_wr_abs2 is
;     a second, independent stream for BGLOAD's two parallel writes
;     (nametable + attribute).
;
;   vid_data_byte - pulls one value out of the current DATA position, exactly
;     as READ would (including a real ?OUT OF DATA error when the program runs
;     out), without hand-duplicating BASIC's cross-line DATA search. It works
;     by borrowing the real READ statement and GETBYT against a reserved
;     scratch variable, Z9: point TXTPTR at "Z9" and jsr READ (Z9 = next DATA
;     value, DATPTR advances correctly), then point TXTPTR at "Z9" again and
;     jsr GETBYT (X = Z9 as a byte 0-255, same range check GETBYT always
;     applies). vid_data_begin/vid_data_end save/restore Z9's prior value
;     around the whole bulk command so nothing user-visible changes except
;     that a variable named Z9 exists after the first bulk-load call.
;
; Both primitives clobber TXTPTR; callers save the real TXTPTR once before
; their loop and restore it once before returning - not per item.
; ----------------------------------------------------------------------------
VID_ADDR:
        .res    3                       ; running 24-bit address
VID_ADDR2:
        .res    3                       ; second stream (BGLOAD's attribute half)
VID_COUNT:
        .res    2                       ; 16-bit down-counter, private to the
                                         ; bulk-load loops (LINNUM/TEMP1-3 are
                                         ; not safe to hold a value in across a
                                         ; jsr READ/FRMNUM/PTRGET - those use
                                         ; them as their own scratch)
VID_STRIDE:
        .res    1                       ; fields per item (1: CHRLOAD/PALLOAD;
                                         ; 2: BGLOAD; 5: OAMLOAD)
VID_STREAM2:
        .res    1                       ; bitmask: field i of each item writes
                                         ; through vid_wr_abs2/VID_ADDR2 instead
                                         ; of vid_wr_abs/VID_ADDR (BGLOAD only)
VID_FIELD:
        .res    1                       ; vid_bulk_run's field-within-item
                                         ; index (see vid_bulk_run - not Y,
                                         ; which vid_data_byte clobbers)

VID_DATA_VARNAME:
        .byte   "Z9",$00
VID_DATA_SAVE:
        .res    BYTES_FP

; vid_seek_abs: X = stream (0 -> VID_ADDR, 3 -> VID_ADDR2 - declared back to
; back, so indexing by X reaches either). Must be called inside an sei fence
; (shares window A with the console cursor).
vid_seek_abs:
        lda     #VIDX_RENDER_CONTROL
        sta     IDXA_SELECT
        lda     #CFG_IDXA_ADDR_H
        sta     CFG_SELECT
        lda     VID_ADDR+2,x
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_M
        sta     CFG_SELECT
        lda     VID_ADDR+1,x
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_L
        sta     CFG_SELECT
        lda     VID_ADDR,x
        sta     CFG_PORT
        rts

; vid_wr_abs/vid_wr_abs2: X = value, written at VID_ADDR/VID_ADDR2. sei-fenced;
; increments the 24-bit address afterward. The stream offset (0/3) is carried
; through TEMP2, not Y or X - callers (SPRITE's own write loop, vid_bulk_run's
; field loop) use Y as their own loop counter across this call and must see it
; come back unchanged; X is needed for the value, then for vid_seek_abs's own
; indexing, then again for the final indexed increment, so it can't carry
; anything across those either.
vid_wr_abs:
        lda     #0
        sta     TEMP2
        jmp     vid_wr_common
vid_wr_abs2:
        lda     #3
        sta     TEMP2
vid_wr_common:
        stx     TEMP3
        php
        sei
        ldx     TEMP2
        jsr     vid_seek_abs
        ldx     TEMP3
        stx     IDXA_PORT
        plp
        ldx     TEMP2
        inc     VID_ADDR,x
        bne     @wrdone
        inc     VID_ADDR+1,x
        bne     @wrdone
        inc     VID_ADDR+2,x
@wrdone:
        rts

; vid_addr_add16/vid_addr_add16_2: add LINNUM/LINNUM+1 into VID_ADDR/VID_ADDR2
; (24-bit). Clobbers A. Call immediately after GETADR, before anything else
; can reuse LINNUM.
vid_addr_add16:
        lda     VID_ADDR
        clc
        adc     LINNUM
        sta     VID_ADDR
        lda     VID_ADDR+1
        adc     LINNUM+1
        sta     VID_ADDR+1
        bcc     @done
        inc     VID_ADDR+2
@done:
        rts

vid_addr_add16_2:
        lda     VID_ADDR2
        clc
        adc     LINNUM
        sta     VID_ADDR2
        lda     VID_ADDR2+1
        adc     LINNUM+1
        sta     VID_ADDR2+1
        bcc     @done
        inc     VID_ADDR2+2
@done:
        rts

; vid_data_begin/vid_data_end: save/restore Z9's value around a bulk-load
; command (see banner above). Mirror images of each other, so both are thin
; entry points into one shared body; A on entry to the body (via X) tells it
; which direction to copy.
vid_data_begin:
        ldx     #0
        jmp     vid_data_swap
vid_data_end:
        ldx     #1
vid_data_swap:
        stx     TEMP3
        lda     #<VID_DATA_VARNAME
        ldy     #>VID_DATA_VARNAME
        sta     TXTPTR
        sty     TXTPTR+1
        jsr     PTRGET                  ; A,Y -> pointer to Z9's value bytes
        sta     TEMP1
        sty     TEMP2
        ldy     #BYTES_FP-1
        lda     TEMP3
        bne     @restore
@save:
        lda     (TEMP1),y
        sta     VID_DATA_SAVE,y
        dey
        bpl     @save
        rts
@restore:
        lda     VID_DATA_SAVE,y
        sta     (TEMP1),y
        dey
        bpl     @restore
        rts

vid_data_byte:
        lda     #<VID_DATA_VARNAME
        ldy     #>VID_DATA_VARNAME
        sta     TXTPTR
        sty     TXTPTR+1
        jsr     READ                    ; Z9 = next DATA value; DATPTR advances
        lda     #<VID_DATA_VARNAME
        ldy     #>VID_DATA_VARNAME
        sta     TXTPTR
        sty     TXTPTR+1
        jmp     GETBYT                  ; X = Z9 as a byte 0-255 (tail call)

; mul_table_1000: A = table/bank index (0-7) -> TEMP2/TEMP3 = index*1000
; (16-bit). Self-contained (no nested BASIC calls), so TEMP1-3 are safe here.
mul_table_1000:
        tax
        lda     #$00
        sta     TEMP2
        sta     TEMP3
        cpx     #$00
        beq     @done
@loop:
        lda     TEMP2
        clc
        adc     #<1000
        sta     TEMP2
        lda     TEMP3
        adc     #>1000
        sta     TEMP3
        dex
        bne     @loop
@done:
        rts

; mul_bank_6144: A = CHR bank (0-7) -> TEMP2/TEMP3 = bank*6144 (16-bit).
mul_bank_6144:
        tax
        lda     #$00
        sta     TEMP2
        sta     TEMP3
        cpx     #$00
        beq     @done
@loop:
        lda     TEMP2
        clc
        adc     #<6144
        sta     TEMP2
        lda     TEMP3
        adc     #>6144
        sta     TEMP3
        dex
        bne     @loop
@done:
        rts

; bg_seek_nt/bg_seek_attr: A = raw BG table (0-7). Sets VID_ADDR/VID_ADDR2 to
; that table's nametable/attribute base ($0C200/$0E140 + table*1000).
bg_seek_nt:
        jsr     mul_table_1000
        lda     #MIA_BG_NT_BASE_L
        clc
        adc     TEMP2
        sta     VID_ADDR
        lda     #MIA_BG_NT_BASE_M
        adc     TEMP3
        sta     VID_ADDR+1
        lda     #$00
        adc     #$00
        sta     VID_ADDR+2
        rts

bg_seek_attr:
        jsr     mul_table_1000
        lda     #MIA_BG_ATTR_BASE_L
        clc
        adc     TEMP2
        sta     VID_ADDR2
        lda     #MIA_BG_ATTR_BASE_M
        adc     TEMP3
        sta     VID_ADDR2+1
        lda     #$00
        adc     #$00
        sta     VID_ADDR2+2
        rts

; chr_seek: A = CHR bank (0-7). Sets VID_ADDR to that bank's base ($00200 +
; bank*6144).
chr_seek:
        jsr     mul_bank_6144
        lda     #MIA_CHR_BASE_L
        clc
        adc     TEMP2
        sta     VID_ADDR
        lda     #MIA_CHR_BASE_M
        adc     TEMP3
        sta     VID_ADDR+1
        lda     #$00
        adc     #$00
        sta     VID_ADDR+2
        rts

; oam_seek_n: A = OAM index n (0-255). Sets VID_ADDR = $10850 + n*5, via
; n*5 = (n<<2)+n.
oam_seek_n:
        sta     TEMP1
        sta     TEMP2
        lda     #$00
        sta     TEMP3
        lda     TEMP1
        asl     a
        rol     TEMP3
        asl     a
        rol     TEMP3                   ; A,TEMP3 = n<<2 (16-bit)
        clc
        adc     TEMP2                   ; + n (low byte)
        sta     TEMP2
        lda     TEMP3
        adc     #$00
        sta     TEMP3                   ; TEMP2/TEMP3 = n*5 (16-bit)
        lda     #MIA_OAM_BASE_L
        clc
        adc     TEMP2
        sta     VID_ADDR
        lda     #MIA_OAM_BASE_M
        adc     TEMP3
        sta     VID_ADDR+1
        lda     #MIA_OAM_BASE_H
        adc     #$00
        sta     VID_ADDR+2
        rts

; vid_addr_add_small: A = a small (0-4) offset to add to VID_ADDR (24-bit).
; Used by the single-field sprite setters to nudge VID_ADDR from oam_seek_n's
; base (the tile byte) to whichever OAM field they touch.
vid_addr_add_small:
        clc
        adc     VID_ADDR
        sta     VID_ADDR
        bcc     @done
        inc     VID_ADDR+1
        bne     @done
        inc     VID_ADDR+2
@done:
        rts

; vid_rmw_abs: read-modify-write one byte at VID_ADDR (stream 0 - not used by
; BGLOAD). A = AND-mask (bits to clear), X = OR-value (already shifted into
; position) to combine in. VID_ADDR is left unchanged (no auto-advance) -
; callers position it themselves (oam_seek_n + vid_addr_add_small) first.
vid_rmw_abs:
        sta     TEMP1
        stx     TEMP2
        php
        sei
        ldx     #0
        jsr     vid_seek_abs
        lda     IDXA_PORT
        and     TEMP1
        ora     TEMP2
        sta     TEMP3
        ldx     #0
        jsr     vid_seek_abs            ; re-seek: the read above stepped it
        lda     TEMP3
        sta     IDXA_PORT
        plp
        rts

; vid_bulk_run: the loop shared by BGLOAD/CHRLOAD/PALLOAD/OAMLOAD. Callers set
; VID_ADDR (+ VID_ADDR2 for BGLOAD), VID_COUNT (number of *items*, not fields),
; VID_STRIDE (fields per item) and VID_STREAM2 (bitmask - bit i set means
; field i of each item writes through vid_wr_abs2/VID_ADDR2 instead of
; vid_wr_abs/VID_ADDR; only BGLOAD uses this), then tail-call this.
; Saves/restores the real TXTPTR and Z9 (via vid_data_begin/vid_data_end)
; around the whole operation.
vid_bulk_run:
        lda     TXTPTR                  ; save the real program position - the
        ldy     TXTPTR+1                ; DATA-pulling below repositions TXTPTR
        pha
        tya
        pha
        jsr     vid_data_begin
@item:
        lda     VID_COUNT
        ora     VID_COUNT+1
        beq     @done
        lda     #$00
        sta     VID_FIELD               ; field index lives in memory, not Y -
                                         ; vid_data_byte clobbers Y internally
                                         ; (it calls into READ/GETBYT), so Y
                                         ; can't survive across that call
@field:
        jsr     vid_data_byte
        ldy     VID_FIELD               ; reload Y fresh for this one use
        lda     VID_STREAM2
        and     CHR_BIT_TABLE,y
        beq     @s1
        jsr     vid_wr_abs2
        jmp     @nextfield
@s1:
        jsr     vid_wr_abs
@nextfield:
        inc     VID_FIELD
        lda     VID_FIELD
        cmp     VID_STRIDE
        bne     @field
        lda     VID_COUNT
        bne     @dec
        dec     VID_COUNT+1
@dec:
        dec     VID_COUNT
        jmp     @item
@done:
        jsr     vid_data_end
        pla
        tay
        pla
        sta     TXTPTR
        sty     TXTPTR+1
        rts

; divmod40/divmod25: A = value -> A = value/divisor (quotient), X = value MOD
; divisor (remainder). Repeated subtraction: value is always a validated
; small coordinate (col < 160, row < 100 - see BASIC_BGCHAR below), so this
; never loops more than 3-4 times. CMP sets carry exactly the way SBC needs it
; (no explicit SEC), since neither loop touches carry in between.
divmod40:
        ldx     #0
@loop:
        cmp     #40
        jcc     @done
        sbc     #40
        inx
        jmp     @loop
@done:
        rts

divmod25:
        ldx     #0
@loop:
        cmp     #25
        jcc     @done
        sbc     #25
        inx
        jmp     @loop
@done:
        rts

; BGCHAR col,row,tile,attr : write one BG nametable+attribute cell, mode-aware
; - resolves which of the up-to-8 raw 40x25 tables (see docs/basic-video.md's
; BGMODE diagram) and where in it, replaying the renderer's bgTableAndLocal
; (clementina-video-client internal/render/renderer.go) in 6502. col/row are
; *map-relative* coordinates for the CURRENT BGMODE (0..planeCols-1 /
; 0..planeRows-1 - e.g. for BGMODE 3, col is 0-159), not screen-relative -
; out-of-range raises ILLEGAL QUANTITY rather than wrapping, unlike the
; renderer's own positiveMod (a typo here should not silently write the wrong
; cell).
BGC_COL:
        .res    1
BGC_ROW:
        .res    1
BGC_TILE:
        .res    1
BGC_ATTR:
        .res    1
BGC_MODE:
        .res    1
BGC_ASET:
        .res    1
BGC_LOCALX:
        .res    1
BGC_LOCALY:
        .res    1
BGC_QCOL:
        .res    1
BGC_QROW:
        .res    1
BGC_TABLE:
        .res    1

BASIC_BGCHAR:
        jsr     GETBYT                  ; X = col
        stx     BGC_COL
        jsr     COMBYTE                 ; X = row
        stx     BGC_ROW
        jsr     COMBYTE                 ; X = tile
        stx     BGC_TILE
        jsr     COMBYTE                 ; X = attr
        stx     BGC_ATTR

        php
        sei
        lda     #RC_BG_VIEWPORT_MODE
        jsr     vid_seek
        lda     IDXA_PORT               ; mode (this read auto-steps to the
        sta     BGC_MODE                ; next render-control byte)
        lda     IDXA_PORT               ; active_set
        sta     BGC_ASET
        plp

        lda     BGC_MODE
        cmp     #6
        jcs     snd_iqerr               ; mode is always 0-5 if only BGMODE
                                         ; ever wrote it, but a raw POKE could
                                         ; have set anything - check anyway
        cmp     #1
        beq     @m1
        cmp     #2
        beq     @m2
        cmp     #3
        beq     @m3
        cmp     #4
        beq     @m4
        cmp     #5
        beq     @m5
        ; mode 0: 40x25, single table
        lda     #40
        jsr     bgc_check_col
        lda     #25
        jsr     bgc_check_row
        jmp     @divide
@m1:                                    ; 80x25
        lda     #80
        jsr     bgc_check_col
        lda     #25
        jsr     bgc_check_row
        jmp     @divide
@m2:                                    ; 40x50
        lda     #40
        jsr     bgc_check_col
        lda     #50
        jsr     bgc_check_row
        jmp     @divide
@m3:                                    ; 160x25
        lda     #160
        jsr     bgc_check_col
        lda     #25
        jsr     bgc_check_row
        jmp     @divide
@m4:                                    ; 40x100
        lda     #40
        jsr     bgc_check_col
        lda     #100
        jsr     bgc_check_row
        jmp     @divide
@m5:                                    ; 80x50
        lda     #80
        jsr     bgc_check_col
        lda     #50
        jsr     bgc_check_row

@divide:
        lda     BGC_COL
        jsr     divmod40                ; A = localX, X = col/40
        sta     BGC_LOCALX
        stx     BGC_QCOL
        lda     BGC_ROW
        jsr     divmod25                ; A = localY, X = row/25
        sta     BGC_LOCALY
        stx     BGC_QROW

        ; table = mode's tableForCell(qCol,qRow), then + active_set*4
        lda     BGC_MODE
        cmp     #1
        beq     @t_qcol
        cmp     #2
        beq     @t_qrow2
        cmp     #3
        beq     @t_qcol
        cmp     #4
        beq     @t_qrow
        cmp     #5
        beq     @t_5
        lda     #0                      ; mode 0
        jmp     @tdone
@t_qcol:
        lda     BGC_QCOL
        jmp     @tdone
@t_qrow2:
        lda     BGC_QROW
        asl     a
        jmp     @tdone
@t_qrow:
        lda     BGC_QROW
        jmp     @tdone
@t_5:
        lda     BGC_QROW
        asl     a
        clc
        adc     BGC_QCOL
@tdone:
        ldx     BGC_ASET
        beq     @noaset
        clc
        adc     #4
@noaset:
        sta     BGC_TABLE

        ; cell = localY*40 + localX (0-999, 16-bit) - straight into
        ; LINNUM/LINNUM+1 (what vid_addr_add16/_2 read), computed BEFORE
        ; bg_seek_nt/bg_seek_attr since those reuse TEMP2/TEMP3 (mul_table_1000
        ; scratch) for their own table*1000 multiply.
        lda     BGC_LOCALY
        sta     TEMP1
        lda     #0
        sta     LINNUM
        sta     LINNUM+1
        lda     TEMP1
        beq     @celldone
@cellloop:
        lda     LINNUM
        clc
        adc     #40
        sta     LINNUM
        lda     LINNUM+1
        adc     #0
        sta     LINNUM+1
        dec     TEMP1
        bne     @cellloop
@celldone:
        lda     LINNUM
        clc
        adc     BGC_LOCALX
        sta     LINNUM
        lda     LINNUM+1
        adc     #0
        sta     LINNUM+1

        lda     BGC_TABLE
        pha
        jsr     bg_seek_nt              ; VID_ADDR = nametable base + table*1000
        jsr     vid_addr_add16          ; + cell
        pla
        jsr     bg_seek_attr            ; VID_ADDR2 = attr base + table*1000
        jsr     vid_addr_add16_2        ; + cell

        ldx     BGC_TILE
        jsr     vid_wr_abs
        ldx     BGC_ATTR
        jmp     vid_wr_abs2

; bgc_check_col/bgc_check_row: A = this mode's planeCols/planeRows. Errors via
; ILLEGAL QUANTITY unless BGC_COL/BGC_ROW is strictly less than A.
bgc_check_col:
        cmp     BGC_COL
        jcc     snd_iqerr               ; A < BGC_COL -> col > planeCols, invalid
        jeq     snd_iqerr               ; A == BGC_COL -> col == planeCols, invalid
        rts

bgc_check_row:
        cmp     BGC_ROW
        jcc     snd_iqerr
        jeq     snd_iqerr
        rts

; BGLOAD table,cell,count : bulk-load `count` (tile,attr) pairs from the
; current DATA position into raw BG table `table` (0-7), starting at cell
; `cell` (0-999). Writes the nametable and attribute planes in lockstep -
; author DATA as tile0,attr0,tile1,attr1,...
; ============================================================================
; File-sourced asset I/O (see docs/basic-file.md): CHRREAD/PALREAD/OAMREAD/
; NTREAD/ATRREAD bulk-load from the current DATA position, exactly as
; CHRLOAD/PALLOAD/OAMLOAD/BGLOAD used to (BGLOAD itself is retired - its
; interleaved nametable+attribute case is now two calls, NTREAD/NTLOAD +
; ATRREAD/ATRLOAD). CHRLOAD/PALLOAD/OAMLOAD/NTLOAD/ATRLOAD now instead mean
; "load from an SD file" (matching classic LOAD's real meaning - storage, not
; DATA), with *SAVE siblings for the reverse. All ten share the exact address
; computation their *READ twin already had, differing only in where the bytes
; come from/go: vid_bulk_run for *READ, mia_sd_load_trigger/
; mia_sd_save_trigger (this file, near BASIC_OPEN) for the rest.
; ============================================================================

; NTREAD table,cell,count : bulk-load `count` raw nametable (tile) bytes from
; the current DATA position into raw BG table `table` (0-7), starting at
; `cell` (0-999).
BASIC_NTREAD:
        jsr     GETBYT                  ; X = table 0-7
        cpx     #$08
        jcs     snd_iqerr
        txa
        pha
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR                  ; cell -> LINNUM/LINNUM+1
        lda     LINNUM                  ; cell must be < 1000 ($03E8)
        cmp     #<1000
        lda     LINNUM+1
        sbc     #>1000
        jcs     snd_iqerr
        pla                             ; A = table
        jsr     bg_seek_nt              ; VID_ADDR = nametable base + table*1000
        jsr     vid_addr_add16          ; + cell
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR                  ; count -> LINNUM/LINNUM+1
        lda     LINNUM
        sta     VID_COUNT
        lda     LINNUM+1
        sta     VID_COUNT+1
        lda     #1
        sta     VID_STRIDE
        lda     #0
        sta     VID_STREAM2
        jmp     vid_bulk_run

; NTLOAD table,cell,count,"file" : as NTREAD, but reads from a file.
BASIC_NTLOAD:
        jsr     GETBYT
        cpx     #$08
        jcs     snd_iqerr
        txa
        pha
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR
        lda     LINNUM
        cmp     #<1000
        lda     LINNUM+1
        sbc     #>1000
        jcs     snd_iqerr
        pla
        jsr     bg_seek_nt
        jsr     vid_addr_add16
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR                  ; count -> LINNUM/LINNUM+1
        lda     LINNUM
        sta     VID_COUNT
        lda     LINNUM+1
        sta     VID_COUNT+1
        jsr     mia_parse_path_arg
        jmp     mia_sd_load_trigger

; NTSAVE table,cell,count,"file" : as NTLOAD, in reverse (nametable -> file).
BASIC_NTSAVE:
        jsr     GETBYT
        cpx     #$08
        jcs     snd_iqerr
        txa
        pha
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR
        lda     LINNUM
        cmp     #<1000
        lda     LINNUM+1
        sbc     #>1000
        jcs     snd_iqerr
        pla
        jsr     bg_seek_nt
        jsr     vid_addr_add16
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR
        lda     LINNUM
        sta     VID_COUNT
        lda     LINNUM+1
        sta     VID_COUNT+1
        jsr     mia_parse_path_arg
        jmp     mia_sd_save_trigger

; ATRREAD table,cell,count : as NTREAD, but the attribute half of the table.
BASIC_ATRREAD:
        jsr     GETBYT                  ; X = table 0-7
        cpx     #$08
        jcs     snd_iqerr
        txa
        pha
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR
        lda     LINNUM
        cmp     #<1000
        lda     LINNUM+1
        sbc     #>1000
        jcs     snd_iqerr
        pla                             ; A = table
        jsr     bg_seek_attr            ; VID_ADDR2 = attr base + table*1000
        lda     VID_ADDR2               ; copy to VID_ADDR: this is the
        sta     VID_ADDR                ; single-stream path (STREAM2=0), and
        lda     VID_ADDR2+1             ; vid_bulk_run/mia_sd_*_trigger only
        sta     VID_ADDR+1              ; ever read VID_ADDR, never VID_ADDR2
        lda     VID_ADDR2+2             ; (that register is BGCHAR/BGLOAD's
        sta     VID_ADDR+2              ; own dual-stream second target)
        jsr     vid_addr_add16          ; + cell
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR                  ; count -> LINNUM/LINNUM+1
        lda     LINNUM
        sta     VID_COUNT
        lda     LINNUM+1
        sta     VID_COUNT+1
        lda     #1
        sta     VID_STRIDE
        lda     #0
        sta     VID_STREAM2
        jmp     vid_bulk_run

; ATRLOAD table,cell,count,"file" : as ATRREAD, but reads from a file.
BASIC_ATRLOAD:
        jsr     GETBYT
        cpx     #$08
        jcs     snd_iqerr
        txa
        pha
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR
        lda     LINNUM
        cmp     #<1000
        lda     LINNUM+1
        sbc     #>1000
        jcs     snd_iqerr
        pla
        jsr     bg_seek_attr            ; VID_ADDR2 = attr base + table*1000
        lda     VID_ADDR2               ; copy to VID_ADDR - see ATRREAD above
        sta     VID_ADDR
        lda     VID_ADDR2+1
        sta     VID_ADDR+1
        lda     VID_ADDR2+2
        sta     VID_ADDR+2
        jsr     vid_addr_add16          ; + cell
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR
        lda     LINNUM
        sta     VID_COUNT
        lda     LINNUM+1
        sta     VID_COUNT+1
        jsr     mia_parse_path_arg
        jmp     mia_sd_load_trigger

; ATRSAVE table,cell,count,"file" : as ATRLOAD, in reverse (attrs -> file).
BASIC_ATRSAVE:
        jsr     GETBYT
        cpx     #$08
        jcs     snd_iqerr
        txa
        pha
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR
        lda     LINNUM
        cmp     #<1000
        lda     LINNUM+1
        sbc     #>1000
        jcs     snd_iqerr
        pla
        jsr     bg_seek_attr            ; VID_ADDR2 = attr base + table*1000
        lda     VID_ADDR2               ; copy to VID_ADDR - see ATRREAD above
        sta     VID_ADDR
        lda     VID_ADDR2+1
        sta     VID_ADDR+1
        lda     VID_ADDR2+2
        sta     VID_ADDR+2
        jsr     vid_addr_add16          ; + cell
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR
        lda     LINNUM
        sta     VID_COUNT
        lda     LINNUM+1
        sta     VID_COUNT+1
        jsr     mia_parse_path_arg
        jmp     mia_sd_save_trigger

; CHRREAD bank,offset,count : bulk-load `count` raw tile/graphics bytes from
; the current DATA position into CHR bank `bank` (0-7), starting at byte
; `offset` (0-6143).
BASIC_CHRREAD:
        jsr     GETBYT                  ; X = bank 0-7
        cpx     #$08
        jcs     snd_iqerr
        txa
        pha
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR                  ; offset -> LINNUM/LINNUM+1
        lda     LINNUM
        cmp     #<6144
        lda     LINNUM+1
        sbc     #>6144
        jcs     snd_iqerr               ; offset must be < 6144
        pla                             ; A = bank
        jsr     chr_seek
        jsr     vid_addr_add16
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR                  ; count -> LINNUM/LINNUM+1
        lda     LINNUM
        sta     VID_COUNT
        lda     LINNUM+1
        sta     VID_COUNT+1
        lda     #1
        sta     VID_STRIDE
        lda     #0
        sta     VID_STREAM2
        jmp     vid_bulk_run

; CHRLOAD bank,offset,count,"file" : as CHRREAD, but reads from a file.
BASIC_CHRLOAD:
        jsr     GETBYT
        cpx     #$08
        jcs     snd_iqerr
        txa
        pha
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR
        lda     LINNUM
        cmp     #<6144
        lda     LINNUM+1
        sbc     #>6144
        jcs     snd_iqerr
        pla
        jsr     chr_seek
        jsr     vid_addr_add16
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR                  ; count -> LINNUM/LINNUM+1
        lda     LINNUM
        sta     VID_COUNT
        lda     LINNUM+1
        sta     VID_COUNT+1
        jsr     mia_parse_path_arg
        jmp     mia_sd_load_trigger

; CHRSAVE bank,offset,count,"file" : as CHRLOAD, in reverse (CHR -> file).
BASIC_CHRSAVE:
        jsr     GETBYT
        cpx     #$08
        jcs     snd_iqerr
        txa
        pha
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR
        lda     LINNUM
        cmp     #<6144
        lda     LINNUM+1
        sbc     #>6144
        jcs     snd_iqerr
        pla
        jsr     chr_seek
        jsr     vid_addr_add16
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR
        lda     LINNUM
        sta     VID_COUNT
        lda     LINNUM+1
        sta     VID_COUNT+1
        jsr     mia_parse_path_arg
        jmp     mia_sd_save_trigger

; PALREAD bank,offset,count : bulk-load `count` raw palette bytes from the
; current DATA position, starting `offset` bytes into palette bank `bank`
; (each bank is 16 bytes: 8 colors x RGB565).
BASIC_PALREAD:
        jsr     GETBYT                  ; X = bank 0-15
        cpx     #$10
        jcs     snd_iqerr
        txa
        asl     a
        asl     a
        asl     a
        asl     a                       ; bank << 4
        sta     TEMP2
        jsr     COMBYTE                 ; X = offset 0-15
        cpx     #$10
        jcs     snd_iqerr
        txa
        clc
        adc     TEMP2                   ; bank*16 + offset (max 255, fits a byte)
        sta     VID_ADDR
        lda     #$01                    ; palette base $00100: mid byte always
        sta     VID_ADDR+1              ; $01 (see BASIC_PALETTE above), high $00
        lda     #$00
        sta     VID_ADDR+2
        jsr     COMBYTE                 ; X = count
        stx     VID_COUNT
        lda     #$00
        sta     VID_COUNT+1
        lda     #1
        sta     VID_STRIDE
        lda     #0
        sta     VID_STREAM2
        jmp     vid_bulk_run

; PALLOAD bank,offset,count,"file" : as PALREAD, but reads from a file.
BASIC_PALLOAD:
        jsr     GETBYT
        cpx     #$10
        jcs     snd_iqerr
        txa
        asl     a
        asl     a
        asl     a
        asl     a
        sta     TEMP2
        jsr     COMBYTE                 ; X = offset 0-15
        cpx     #$10
        jcs     snd_iqerr
        txa
        clc
        adc     TEMP2
        sta     VID_ADDR
        lda     #$01
        sta     VID_ADDR+1
        lda     #$00
        sta     VID_ADDR+2
        jsr     COMBYTE                 ; X = count
        stx     VID_COUNT
        lda     #$00
        sta     VID_COUNT+1
        jsr     mia_parse_path_arg
        jmp     mia_sd_load_trigger

; PALSAVE bank,offset,count,"file" : as PALLOAD, in reverse (palette -> file).
BASIC_PALSAVE:
        jsr     GETBYT
        cpx     #$10
        jcs     snd_iqerr
        txa
        asl     a
        asl     a
        asl     a
        asl     a
        sta     TEMP2
        jsr     COMBYTE
        cpx     #$10
        jcs     snd_iqerr
        txa
        clc
        adc     TEMP2
        sta     VID_ADDR
        lda     #$01
        sta     VID_ADDR+1
        lda     #$00
        sta     VID_ADDR+2
        jsr     COMBYTE                 ; X = count
        stx     VID_COUNT
        lda     #$00
        sta     VID_COUNT+1
        jsr     mia_parse_path_arg
        jmp     mia_sd_save_trigger

; OAMREAD n,count : bulk-load `count` sprites' raw 5-byte OAM records
; (tile,xlo,ylo,attr,ext - see docs/basic-video.md for the attr/ext bit
; layout) from the current DATA position, starting at OAM index `n` (0-255).
BASIC_OAMREAD:
        jsr     GETBYT                  ; X = n
        txa
        jsr     oam_seek_n
        jsr     COMBYTE                 ; X = count (of sprites), 0-255 - OAM
        stx     VID_COUNT               ; only has 256 slots total, so a byte
        lda     #0                      ; is never actually a limitation here
        sta     VID_COUNT+1
        lda     #5
        sta     VID_STRIDE
        lda     #0
        sta     VID_STREAM2
        jmp     vid_bulk_run

; OAMLOAD n,count,"file" : as OAMREAD, but reads from a file.
BASIC_OAMLOAD:
        jsr     GETBYT                  ; X = n
        txa
        jsr     oam_seek_n
        jsr     COMBYTE                 ; X = count
        stx     VID_COUNT
        lda     #0
        sta     VID_COUNT+1
        jsr     mia_parse_path_arg
        jmp     mia_sd_load_trigger

; OAMSAVE n,count,"file" : as OAMLOAD, in reverse (OAM -> file).
BASIC_OAMSAVE:
        jsr     GETBYT                  ; X = n
        txa
        jsr     oam_seek_n
        jsr     COMBYTE                 ; X = count
        stx     VID_COUNT
        lda     #0
        sta     VID_COUNT+1
        jsr     mia_parse_path_arg
        jmp     mia_sd_save_trigger

; SPRITE n,tile,x,y,pal,flags : full OAM entry setup in one call. n 0-255
; (OAM index), tile 0-255, x -512..511, y -256..255, pal 0-15, flags: bit0
; disable, bit1 priority, bit2 flip-X, bit3 flip-Y (see docs/basic-video.md
; for how these map onto the hardware attr/ext bytes).
; Declared in OAM field order (tile,xlo,ylo,attr,ext) and contiguous, so the
; final write sequence in BASIC_SPRITE can loop over them indexed by Y instead
; of five unrolled ldx/jsr pairs.
SPR_TILE:
        .res    1
SPR_XLO:
        .res    1
SPR_YLO:
        .res    1
SPR_ATTR:
        .res    1
SPR_EXT:
        .res    1

BASIC_SPRITE:
        jsr     GETBYT                  ; X = n
        txa
        jsr     oam_seek_n              ; A clobbered by oam_seek_n; do this
        jsr     COMBYTE                 ; first - X = tile next
        stx     SPR_TILE
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     AYINT                   ; x -> FAC_LAST-1 (hi) / FAC_LAST (lo)
        lda     FAC_LAST-1
        bmi     @xneg
        cmp     #$02
        jcs     snd_iqerr
        jmp     @xok
@xneg:
        cmp     #$FE
        jcc     snd_iqerr
@xok:
        and     #$03
        sta     SPR_EXT                 ; ext bits 0-1 = x hi
        lda     FAC_LAST
        sta     SPR_XLO
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     AYINT                   ; y -> FAC_LAST-1/FAC_LAST
        lda     FAC_LAST-1
        beq     @yok
        cmp     #$FF
        jne     snd_iqerr
@yok:
        and     #$01
        asl     a
        asl     a                       ; -> ext bit 2 = y hi
        ora     SPR_EXT
        sta     SPR_EXT
        lda     FAC_LAST
        sta     SPR_YLO
        jsr     COMBYTE                 ; X = pal 0-15
        cpx     #$10
        jcs     snd_iqerr
        stx     SPR_ATTR
        jsr     COMBYTE                 ; X = flags
        txa
        sta     TEMP1
        and     #$01
        asl     a
        asl     a
        asl     a                       ; disable -> ext bit 3
        ora     SPR_EXT
        sta     SPR_EXT
        lda     TEMP1
        and     #$0E                    ; priority/flipX/flipY (bits 1-3)
        asl     a
        asl     a
        asl     a                       ; -> attr bits 4-6
        ora     SPR_ATTR
        sta     SPR_ATTR

        ldy     #0
@wr:
        ldx     SPR_TILE,y
        jsr     vid_wr_abs
        iny
        cpy     #5
        bne     @wr
        rts

; SPRTILE n,t : change one sprite's tile/frame index without respecifying
; every other SPRITE field (cheap per-frame animation update).
BASIC_SPRTILE:
        jsr     GETBYT                  ; X = n
        txa
        jsr     oam_seek_n              ; VID_ADDR = base+0 (tile)
        jsr     COMBYTE                 ; X = tile
        jmp     vid_wr_abs

; SPRX n,x / SPRY n,y : change one sprite's position without respecifying
; every other SPRITE field. Same signed range/encoding as SPRITE's x/y.
BASIC_SPRX:
        jsr     GETBYT                  ; X = n
        txa
        jsr     oam_seek_n              ; VID_ADDR = base+0
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     AYINT                   ; x -> FAC_LAST-1 (hi) / FAC_LAST (lo)
        lda     FAC_LAST-1
        bmi     @xneg
        cmp     #$02
        jcs     snd_iqerr
        jmp     @xok
@xneg:
        cmp     #$FE
        jcc     snd_iqerr
@xok:
        and     #$03
        sta     TEMP1                   ; TEMP1 = new ext xhi bits (0-1)
        lda     FAC_LAST
        tax                             ; X = xlo
        lda     #1
        jsr     vid_addr_add_small      ; VID_ADDR = base+1 (xlo)
        jsr     vid_wr_abs              ; write xlo; VID_ADDR now base+2
        lda     #2
        jsr     vid_addr_add_small      ; VID_ADDR = base+4 (ext)
        lda     #%11111100              ; clear ext bits 0-1
        ldx     TEMP1
        jmp     vid_rmw_abs

BASIC_SPRY:
        jsr     GETBYT                  ; X = n
        txa
        jsr     oam_seek_n              ; VID_ADDR = base+0
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     AYINT                   ; y -> FAC_LAST-1/FAC_LAST
        lda     FAC_LAST-1
        beq     @yok
        cmp     #$FF
        jne     snd_iqerr
@yok:
        and     #$01
        asl     a
        asl     a                       ; -> ext bit 2
        sta     TEMP1
        lda     FAC_LAST
        tax                             ; X = ylo
        lda     #2
        jsr     vid_addr_add_small      ; VID_ADDR = base+2 (ylo)
        jsr     vid_wr_abs              ; write ylo; VID_ADDR now base+3
        lda     #1
        jsr     vid_addr_add_small      ; VID_ADDR = base+4 (ext)
        lda     #%11111011              ; clear ext bit 2
        ldx     TEMP1
        jmp     vid_rmw_abs

; SPRCOLOR n,pal : change one sprite's palette (attr bits 0-3) without
; touching its priority/flip bits.
BASIC_SPRCOLOR:
        jsr     GETBYT                  ; X = n
        txa
        jsr     oam_seek_n              ; VID_ADDR = base+0
        jsr     COMBYTE                 ; X = pal 0-15
        cpx     #$10
        jcs     snd_iqerr
        stx     TEMP1
        lda     #3
        jsr     vid_addr_add_small      ; VID_ADDR = base+3 (attr)
        lda     #%11110000              ; clear the palette nibble
        ldx     TEMP1
        jmp     vid_rmw_abs

; SPRFLIP n,fx,fy : change one sprite's flip-X/flip-Y (attr bits 5-6) without
; touching its palette/priority bits.
BASIC_SPRFLIP:
        jsr     GETBYT                  ; X = n
        txa
        jsr     oam_seek_n              ; VID_ADDR = base+0
        jsr     COMBYTE                 ; X = fx (0/nonzero)
        cpx     #$00
        beq     @fx0
        lda     #%00100000
        jmp     @fxset
@fx0:
        lda     #$00
@fxset:
        sta     TEMP1
        jsr     COMBYTE                 ; X = fy (0/nonzero)
        cpx     #$00
        beq     @fy0
        lda     #%01000000
        jmp     @fyset
@fy0:
        lda     #$00
@fyset:
        ora     TEMP1
        tax
        lda     #3
        jsr     vid_addr_add_small      ; VID_ADDR = base+3 (attr)
        lda     #%10011111              ; clear bits 5-6
        jmp     vid_rmw_abs

; SPRPRI n,p : change one sprite's priority (attr bit 4) without touching its
; palette/flip bits.
BASIC_SPRPRI:
        jsr     GETBYT                  ; X = n
        txa
        jsr     oam_seek_n              ; VID_ADDR = base+0
        jsr     COMBYTE                 ; X = p (0/nonzero)
        cpx     #$00
        beq     @p0
        lda     #%00010000
        jmp     @pset
@p0:
        lda     #$00
@pset:
        tax
        lda     #3
        jsr     vid_addr_add_small      ; VID_ADDR = base+3 (attr)
        lda     #%11101111              ; clear bit 4
        jmp     vid_rmw_abs

; ----------------------------------------------------------------------------
; BASIC sound statements - MIA 4-voice PWM PSG. See src/basic/CLEMENTINA.md and
; the clementina-mia repo docs/audio.md. Voices are 0-3 (matching the hardware
; and COLOR/CRSR's 0-based style). Audio starts stopped: issue SNDON once, after
; setting a voice up, before you expect sound.
;
;   SNDON / SNDOFF / SNDCLR   start / stop / clear+reset the PSG
;   VOL n                     master volume, 0-15 (0 mutes)
;   VOL v,n                   voice v volume, 0-255 (255 = unity)
;   WAVE v,w                  waveform: 0 sine 1 pulse 2 saw 3 triangle 4 noise
;   FREQ v,hz                 pitch in Hz, 0-4095
;   NOTE v,n                  pitch as semitone 0-95 (0=C0, 48=C4); gate on+retrig
;   GATE v,g                  g<>0 = note-on (no retrigger), g=0 = release
;   ADSR v,a,d,s,r            envelope: attack/decay/sustain/release, nibbles 0-15
;   PULSE v,pw                pulse duty 0-255 (affects the pulse waveform only)
;   PAN v,p                   stereo position -64..63 (0 = centre)
;   PLAY s$                   blocking MML music string (handler further below)
;
; Every MIA register write goes through index window B and is fenced with sei so
; a cursor-blink IRQ (which rebinds window A and shares CFG_SELECT/CFG_PORT)
; cannot interleave. Out-of-range arguments raise ILLEGAL QUANTITY, like COLOR.
; Argument expressions are parsed before any register write; the MSBASIC error
; path resets the 6502 stack, so handlers do not unwind pushes on the error exit.
; ----------------------------------------------------------------------------
BASIC_SNDON:
        lda     #CMD_AUDIO_ENABLE
        bne     snd_cmd                 ; immediate operand is nonzero: always taken
BASIC_SNDOFF:
        lda     #CMD_AUDIO_STOP
        bne     snd_cmd
BASIC_SNDCLR:
        lda     #CMD_AUDIO_RESET
snd_cmd:
        ldx     #$00
        php
        sei
        stx     CMD_PARAM1
        stx     CMD_PARAM2
        stx     CMD_PARAM3
        sta     CMD_TRIGGER
        plp
        rts

; VOL: one argument = master volume (0-15). "v,n" = per-voice volume (v 0-3,
; n any byte). GETBYT leaves the following character in A, so a comma selects
; the two-argument form.
BASIC_VOL:
        jsr     GETBYT                  ; X = first number
        cmp     #$2C                    ; ','
        beq     @voice
        cpx     #$10
        jcs     snd_iqerr
        lda     #AUD_HDR_VOLUME
        jmp     snd_wr1                 ; A = block offset, X = level
@voice:
        cpx     #$04
        jcs     snd_iqerr
        txa
        pha
        jsr     COMBYTE                 ; X = gain 0-255
        pla
        jsr     snd_voff
        clc
        adc     #AUDV_VOLUME
        jmp     snd_wr1

BASIC_WAVE:
        jsr     snd_arg2                ; A = voice base offset, X = w
        cpx     #$05
        jcs     snd_iqerr
        clc
        adc     #AUDV_WAVEFORM
        jmp     snd_wr1

BASIC_PULSE:
        jsr     snd_arg2                ; A = base, X = pw (any byte valid)
        clc
        adc     #AUDV_PULSE_WIDTH
        jmp     snd_wr1

BASIC_GATE:
        jsr     snd_arg2                ; A = base, X = g
        cpx     #$01
        ldx     #AUD_GATE               ; g >= 1 -> gate on (no retrigger)
        bcs     @wr
        ldx     #$00                    ; g = 0  -> release
@wr:
        clc
        adc     #AUDV_CONTROL
        jmp     snd_wr1

; NOTE v,n : semitone 0-95 -> FREQ_L/H from the octave-0 table, then CONTROL =
; GATE | RESET_PHASE so the note (re)triggers from phase 0. Voice rides the 6502
; stack across the note expression (safe, like the POKE pattern); the base offset
; then rides X through the php/sei fence (snd_seek leaves X alone).
BASIC_NOTE:
        jsr     GETBYT                  ; X = voice
        cpx     #$04
        jcs     snd_iqerr
        txa
        pha
        jsr     COMBYTE                 ; X = note
        cpx     #96
        jcs     snd_iqerr
        txa
        jsr     note_freq               ; LINNUM / LINNUM+1 = Hz * 16
        pla                             ; A = voice
        jsr     snd_voff
        tax                             ; X = base offset; survives the php/sei fence
        php
        sei
        txa
        jsr     snd_seek                ; -> base + AUDV_FREQ_L ($00)
        lda     LINNUM
        sta     IDXB_PORT               ; FREQ_L  (window B steps to FREQ_H)
        lda     LINNUM+1
        sta     IDXB_PORT               ; FREQ_H
        txa
        clc
        adc     #AUDV_CONTROL
        jsr     snd_seek
        lda     #AUD_GATE_RETRIG
        sta     IDXB_PORT
        plp
        rts

; FREQ v,hz : hz 0-4095 -> register value hz * 16 (16-bit).
BASIC_FREQ:
        jsr     GETBYT                  ; X = voice
        cpx     #$04
        jcs     snd_iqerr
        txa
        pha
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR                  ; hz -> LINNUM (low) / LINNUM+1 (high)
        lda     LINNUM+1
        cmp     #$10                    ; hz >= 4096 -> out of range
        jcs     snd_iqerr
        ldx     #$04
@sh:
        asl     LINNUM
        rol     LINNUM+1
        dex
        bne     @sh
        pla                             ; A = voice
        jsr     snd_voff
        php
        sei
        jsr     snd_seek                ; -> base + AUDV_FREQ_L ($00)
        lda     LINNUM
        sta     IDXB_PORT
        lda     LINNUM+1
        sta     IDXB_PORT
        plp
        rts

; ADSR v,a,d,s,r : each nibble 0-15. Packs ATTACK_DECAY and SUSTAIN_RELEASE and
; writes both (they are consecutive fields, so one seek covers them).
BASIC_ADSR:
        jsr     GETBYT                  ; voice
        cpx     #$04
        jcs     snd_iqerr
        stx     LINNUM                  ; voice survives every COMBYTE (POKE pattern)
        jsr     COMBYTE                 ; a
        cpx     #$10
        jcs     snd_iqerr
        txa
        asl     a
        asl     a
        asl     a
        asl     a                       ; a << 4
        sta     LINNUM+1
        jsr     COMBYTE                 ; d
        cpx     #$10
        jcs     snd_iqerr
        txa
        ora     LINNUM+1                ; ATTACK_DECAY
        sta     LINNUM+1
        jsr     COMBYTE                 ; s
        cpx     #$10
        jcs     snd_iqerr
        txa
        asl     a
        asl     a
        asl     a
        asl     a                       ; s << 4
        pha
        jsr     COMBYTE                 ; r
        cpx     #$10
        jcs     snd_iqerr
        pla
        sta     TEMP1                   ; s << 4 (transient: no eval, no fence yet)
        txa
        ora     TEMP1                   ; SUSTAIN_RELEASE
        tax                             ; X = SR; survives the php/sei fence
        lda     LINNUM                  ; voice
        jsr     snd_voff
        clc
        adc     #AUDV_ATTACK_DECAY
        php
        sei
        jsr     snd_seek
        lda     LINNUM+1                ; ATTACK_DECAY  (window B steps to next field)
        sta     IDXB_PORT
        stx     IDXB_PORT               ; SUSTAIN_RELEASE
        plp
        rts

; PAN v,p : p is signed -64..63 (0 = centre). MIA's PAN register is int8, so the
; low byte of the two's-complement value is what gets written.
BASIC_PAN:
        jsr     GETBYT                  ; X = voice
        cpx     #$04
        jcs     snd_iqerr
        txa
        pha
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     AYINT                   ; FAC_LAST-1 : FAC_LAST = signed 16-bit
        lda     FAC_LAST-1
        beq     @pos                    ; $00xx -> 0..63
        cmp     #$FF
        jne     snd_iqerr               ; not $00xx / $FFxx -> out of range
        lda     FAC_LAST
        cmp     #$C0                    ; -64 = $FFC0 ; valid when >= $C0
        jcc     snd_iqerr
        jmp     @store
@pos:
        lda     FAC_LAST
        cmp     #64                     ; valid when <= 63
        jcs     snd_iqerr
@store:
        tax                             ; X = pan byte
        pla                             ; A = voice
        jsr     snd_voff
        clc
        adc     #AUDV_PAN
        jmp     snd_wr1

snd_iqerr:
        jmp     IQERR

; --- sound helpers -------------------------------------------------------------
; snd_arg2: parse "voiceExpr , valueExpr". Range-checks voice 0-3 (else IQERR).
; Returns A = voice's base offset within the audio block, X = value byte.
snd_arg2:
        jsr     GETBYT                  ; X = voice
        cpx     #$04
        jcs     snd_iqerr
        txa
        pha
        jsr     COMBYTE                 ; X = value
        pla
; snd_voff: A = voice 0-3 -> A = that voice record's offset within the block.
snd_voff:
        asl     a
        asl     a
        asl     a
        asl     a                       ; voice * 16
        clc
        adc     #$10                    ; + 16-byte header
        rts

; snd_wr1: write one byte. A = block offset ($00-$4F), X = value. sei-fenced.
snd_wr1:
        php
        sei
        jsr     snd_seek
        stx     IDXB_PORT
        plp
        rts

; snd_seek: bind MIA index window B ($D0, whole audio block) to $12000 + A
; (A = 0..$4F) and leave it ready for IDXB_PORT reads/writes. Must be called
; inside an sei fence (it walks CFG_SELECT/CFG_PORT). Clobbers A.
snd_seek:
        pha
        lda     #IIDX_AUDIO_ALL
        sta     IDXB_SELECT
        lda     #CFG_IDXB_ADDR_H
        sta     CFG_SELECT
        lda     #$01                    ; $12000 bits 16-23
        sta     CFG_PORT
        lda     #CFG_IDXB_ADDR_M
        sta     CFG_SELECT
        lda     #$20                    ; $12000 bits 8-15
        sta     CFG_PORT
        lda     #CFG_IDXB_ADDR_L
        sta     CFG_SELECT
        pla                             ; block offset -> $12000 bits 0-7
        sta     CFG_PORT
        rts

; note_freq: A = semitone 0-95 (0 = C0). Returns Hz * 16 in LINNUM (low) /
; LINNUM+1 (high) as octave0_table[note MOD 12] << (note DIV 12). Clobbers A/X/Y.
note_freq:
        sec
        ldx     #$FF
@div:
        inx
        sbc     #12
        bcs     @div                    ; X = octave; A underflowed
        adc     #12                     ; carry was clear: A = semitone 0-11
        asl     a                       ; * 2 for the word table
        tay
        lda     note_freq_tbl,y
        sta     LINNUM
        lda     note_freq_tbl+1,y
        sta     LINNUM+1
@shift:
        cpx     #$00
        beq     @done
        asl     LINNUM
        rol     LINNUM+1
        dex
        bne     @shift
@done:
        rts

; Octave 0, equal temperament, A4 = 440 Hz; entries are round(Hz * 16). Higher
; octaves come from left shifts, so the top octaves run a few cents sharp of the
; rounded C0 base - inaudible on a PSG.
note_freq_tbl:
        .word   262, 277, 294, 311, 330, 349
        .word   370, 392, 415, 440, 466, 494

; ============================================================================
; PLAY <string$> - blocking MML-style music player. See docs/basic-sound.md.
;
; Tokens (case-insensitive; spaces and commas separate):
;   A-G   note in the current octave; optional # or + (sharp) / - (flat);
;         optional length digits; optional trailing . (dotted, x1.5).
;   R P   rest for one length.
;   O n   set octave 0-7.        <   octave down.     >   octave up.
;   L n   default note length: 1 2 4 8 16 32 (whole .. 32nd note).
;   T n   tempo: ticks per quarter note, 1-255 (a tick is ~1/160 s at 1 MHz
;         PHI2 and scales with PHI2; T80 ~= 120 BPM, the default).
;   V n   route the following notes to voice n (0-3).
;   W n   set the current voice's waveform 0-4.
;
; PLAY writes only FREQ and the gate - set WAVE/ADSR/PAN/VOL and issue SNDON
; first. It is monophonic per voice and serial across voices. RUN/STOP (Ctrl-C)
; aborts and silences every voice. An unknown token raises SYNTAX ERROR; a bad
; number raises ILLEGAL QUANTITY; either way the voices are silenced first.
;
; Parser state lives in STYLE_SIDE_BUF ($03D3+), which the line tokenizer only
; touches while a line is being typed - never during RUN, when PLAY executes.
; The moving string pointer is INDEX; note_freq scratch is LINNUM.
; ============================================================================
PLAY_TEMPO_DEF  = 80            ; ticks per quarter note (~120 BPM at 1 MHz PHI2)
PLAY_OCT_DEF    = 4
PLAY_LDEF_DEF   = 4             ; quarter notes

PLAY_LEN        = STYLE_SIDE_BUF + 0    ; chars left in the string
PLAY_BASE       = STYLE_SIDE_BUF + 1    ; current voice record base ($10/$20/$30/$40)
PLAY_OCT        = STYLE_SIDE_BUF + 2    ; current octave 0-7
PLAY_TEMPO      = STYLE_SIDE_BUF + 3    ; ticks per quarter note
PLAY_LDEF       = STYLE_SIDE_BUF + 4    ; default length code
PLAY_DUR        = STYLE_SIDE_BUF + 5    ; note duration in ticks (16-bit) [5..6]
PLAY_TGT        = STYLE_SIDE_BUF + 7    ; delay target tick value (16-bit) [7..8]
PLAY_SEMI       = STYLE_SIDE_BUF + 9    ; scratch: semitone in octave (signed -1..12)
PLAY_TMP        = STYLE_SIDE_BUF + 10   ; general 16-bit scratch [10..11]

; BASIC_PLAY: "PLAY" with no argument (end of statement/line) stops the
; background player. "PLAY s$" blocks, as before. "PLAY s$,n" with n<>0
; starts s$ playing in the background (tail-jumps to bg_play_start with
; INDEX/PLAY_LEN already set from FRESTR); n=0 is the same as no comma at
; all - blocks. A holds the entry character (see the @ext dispatch comment
; above); CHRGOT re-reads it after FRESTR repurposes A for the length.
BASIC_PLAY:
        cmp     #$00
        jeq     @stop
        cmp     #':'
        jeq     @stop
        jsr     FRMEVL                  ; evaluate the argument expression
        jsr     FRESTR                  ; A = length, INDEX -> string character bytes
        sta     PLAY_LEN
        jsr     CHRGOT                  ; re-read the current char (A now := length)
        cmp     #','
        bne     @blocking
        ; COMBYTE/GETBYT/FRMNUM parse the flag number and, like most of the
        ; interpreter's numeric-parse path, are free to reuse INDEX as their
        ; own scratch - save/restore it around the call so the string pointer
        ; FRESTR just set (needed below, blocking or not) survives intact.
        lda     INDEX
        pha
        lda     INDEX+1
        pha
        jsr     COMBYTE                 ; consume ',' -> X = background flag
        pla
        sta     INDEX+1
        pla
        sta     INDEX
        cpx     #$00
        jne     bg_play_start           ; n<>0 -> background (tail; INDEX/PLAY_LEN valid)
@blocking:
        lda     #$10
        sta     PLAY_BASE               ; voice 0
        lda     #PLAY_OCT_DEF
        sta     PLAY_OCT
        lda     #PLAY_TEMPO_DEF
        sta     PLAY_TEMPO
        lda     #PLAY_LDEF_DEF
        sta     PLAY_LDEF
@loop:
        jsr     play_getc
        bcc     @done
        jsr     TOKEN_UPPER             ; keywords are case-insensitive
        cmp     #' '
        beq     @loop
        cmp     #','
        beq     @loop
        cmp     #'A'
        bcc     @sym
        cmp     #'G'+1
        bcs     @sym
        jsr     play_do_note            ; A = 'A'..'G'
        jmp     @loop
@sym:
        cmp     #'R'
        jeq     @rest
        cmp     #'P'
        jeq     @rest
        cmp     #'<'
        jeq     @octdn
        cmp     #'>'
        jeq     @octup
        cmp     #'O'
        jeq     @oct
        cmp     #'L'
        jeq     @ldef
        cmp     #'T'
        jeq     @tempo
        cmp     #'V'
        jeq     @voice
        cmp     #'W'
        jeq     @wave
        jsr     play_all_off
        jmp     SYNERR
@done:
        jsr     play_all_off
        rts
@stop:
        jmp     bg_play_stop            ; bare PLAY -> stop the background player (tail)

@rest:
        jsr     play_do_rest
        jmp     @loop
@octdn:
        lda     PLAY_OCT
        jeq     @loop
        dec     PLAY_OCT
        jmp     @loop
@octup:
        lda     PLAY_OCT
        cmp     #7
        jcs     @loop
        inc     PLAY_OCT
        jmp     @loop
@oct:
        jsr     play_num_req            ; X = value
        cpx     #8
        jcs     play_iq
        stx     PLAY_OCT
        jmp     @loop
@tempo:
        jsr     play_num_req
        cpx     #$00
        bne     :+
        ldx     #$01                    ; T0 -> 1
:       stx     PLAY_TEMPO
        jmp     @loop
@voice:
        jsr     play_num_req
        cpx     #4
        jcs     play_iq
        txa
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #$10                    ; -> $10/$20/$30/$40
        sta     PLAY_BASE
        jmp     @loop
@wave:
        jsr     play_num_req
        cpx     #5
        jcs     play_iq
        lda     PLAY_BASE
        clc
        adc     #AUDV_WAVEFORM
        jsr     snd_wr1                 ; A = offset, X = value
        jmp     @loop
@ldef:
        jsr     play_num_req
        jsr     play_len_ok            ; X in {1,2,4,8,16,32} or IQERR
        stx     PLAY_LDEF
        jmp     @loop

play_iq:
        jsr     play_all_off
        jmp     IQERR
play_syn:
        jsr     play_all_off
        jmp     SYNERR

; --- PLAY note / rest --------------------------------------------------------
; play_do_note: A = 'A'..'G'. Emits FREQ + gate-on for one note, waits its
; duration. Tail-jumps into play_delay.
play_do_note:
        sec
        sbc     #'A'
        tax
        lda     play_note_semi,x
        sta     PLAY_SEMI
        jsr     play_peek
        bcc     @len
        cmp     #'#'
        beq     @sharp
        cmp     #'+'
        beq     @sharp
        cmp     #'-'
        beq     @flat
        jmp     @len
@sharp:
        jsr     play_adv
        inc     PLAY_SEMI
        jmp     @len
@flat:
        jsr     play_adv
        dec     PLAY_SEMI
@len:
        jsr     play_num               ; C=1 & X=code if length digits present
        bcs     @havelen
        ldx     PLAY_LDEF
@havelen:
        jsr     play_len_ok
        jsr     play_len_to_dur
        jsr     play_maybe_dot
        ldx     PLAY_OCT
        lda     play_oct12,x
        clc
        adc     PLAY_SEMI              ; octave base + semitone (signed)
        cmp     #96
        bcc     @emit
        cmp     #$80
        bcs     @zero                  ; wrapped negative -> clamp low
        lda     #95
        bne     @emit
@zero:
        lda     #$00
@emit:
        jsr     play_note_on
        jmp     play_delay             ; tail

; play_do_rest: gate the current voice off, wait one length.
play_do_rest:
        jsr     play_num
        bcs     @havelen
        ldx     PLAY_LDEF
@havelen:
        jsr     play_len_ok
        jsr     play_len_to_dur
        jsr     play_maybe_dot
        lda     PLAY_BASE
        clc
        adc     #AUDV_CONTROL
        ldx     #$00
        jsr     snd_wr1                ; CONTROL = 0 -> release
        jmp     play_delay

; play_note_on: A = absolute semitone 0-95 -> release the current voice, set
; FREQ_L/H, then gate on with RESET_PHASE. The brief CONTROL=0 before the gate
; forces an envelope low->high edge, so every PLAY note re-attacks (otherwise
; the gate would stay high across the whole string and only the first note would
; have an attack - repeated notes would be inaudible).
play_note_on:
        jsr     note_freq              ; LINNUM/LINNUM+1 = Hz * 16
        lda     PLAY_BASE
        tax                            ; X = voice base offset
        php
        sei
        txa
        clc
        adc     #AUDV_CONTROL
        jsr     snd_seek               ; base + AUDV_CONTROL
        lda     #$00
        sta     IDXB_PORT              ; CONTROL = 0: release any sounding note
        txa
        jsr     snd_seek               ; base + AUDV_FREQ_L ($00)
        lda     LINNUM
        sta     IDXB_PORT
        lda     LINNUM+1
        sta     IDXB_PORT
        txa
        clc
        adc     #AUDV_CONTROL
        jsr     snd_seek
        lda     #AUD_GATE_RETRIG
        sta     IDXB_PORT              ; CONTROL = GATE|RESET_PHASE: re-attack
        plp
        rts

; --- PLAY timing -----------------------------------------------------------
; play_delay: wait PLAY_DUR kernel ticks, polling for Ctrl-C. On Ctrl-C it
; silences all voices and breaks to BASIC (never returns).
play_delay:
        jsr     play_jiffy             ; PLAY_TMP = coherent KJIFFY snapshot
        lda     PLAY_TMP
        clc
        adc     PLAY_DUR
        sta     PLAY_TGT
        lda     PLAY_TMP+1
        adc     PLAY_DUR+1
        sta     PLAY_TGT+1
@wait:
        jsr     play_check_stop
        jsr     play_jiffy
        lda     PLAY_TMP
        sec
        sbc     PLAY_TGT
        lda     PLAY_TMP+1
        sbc     PLAY_TGT+1
        bmi     @wait                  ; ticks - target still negative -> keep waiting
        rts

; play_jiffy: coherent 16-bit read of KJIFFY into PLAY_TMP. Reads high/low/high
; and retries if the high byte changed - the Timer-1 IRQ can carry between the
; two byte reads, and a torn read there would skew the wait by up to 256 ticks.
play_jiffy:
        lda     KJIFFY+1
@r:
        sta     PLAY_TMP+1
        lda     KJIFFY
        sta     PLAY_TMP
        lda     KJIFFY+1
        cmp     PLAY_TMP+1
        bne     @r
        rts

play_check_stop:
        jsr     MONRDKEY_NB            ; C=1 & A=key if one was queued (popped)
        bcc     @none
        cmp     #$03
        beq     @break
@none:
        rts
@break:
        jsr     play_all_off
        lda     #$03
        cmp     #$03                   ; C=1, Z=1 - the state ISCNTC enters STOP with
        jmp     STOP

play_all_off:
        lda     #$10 + AUDV_CONTROL
        ldy     #$04
@l:
        pha
        ldx     #$00
        jsr     snd_wr1
        pla
        clc
        adc     #$10
        dey
        bne     @l
        rts

; --- PLAY length -> duration --------------------------------------------------
; play_len_ok: X in {1,2,4,8,16,32} -> return; else silence + ILLEGAL QUANTITY.
play_len_ok:
        cpx     #1
        beq     @ok
        cpx     #2
        beq     @ok
        cpx     #4
        beq     @ok
        cpx     #8
        beq     @ok
        cpx     #16
        beq     @ok
        cpx     #32
        beq     @ok
        jmp     play_iq
@ok:
        rts

; play_len_to_dur: X = valid length code -> PLAY_DUR (16-bit) ticks, from
; PLAY_TEMPO (ticks per quarter). k=1 -> T<<2, k=2 -> T<<1, k=4 -> T,
; k=8 -> T>>1, k=16 -> T>>2, k=32 -> T>>3. Minimum 1 tick.
play_len_to_dur:
        lda     PLAY_TEMPO
        sta     PLAY_DUR
        lda     #$00
        sta     PLAY_DUR+1
        cpx     #4
        beq     @min
        bcs     @right
        cpx     #1
        bne     @one
        jsr     @shl                   ; k=1: two left shifts
@one:
        jsr     @shl                   ; k=1 or k=2: one more
        jmp     @min
@right:
        jsr     @shr
        cpx     #8
        beq     @min
        jsr     @shr
        cpx     #16
        beq     @min
        jsr     @shr
@min:
        lda     PLAY_DUR
        ora     PLAY_DUR+1
        bne     @ret
        lda     #$01
        sta     PLAY_DUR
@ret:
        rts
@shl:
        asl     PLAY_DUR
        rol     PLAY_DUR+1
        rts
@shr:
        lsr     PLAY_DUR+1
        ror     PLAY_DUR
        rts

; play_maybe_dot: if the next char is '.', consume it and PLAY_DUR += PLAY_DUR/2.
play_maybe_dot:
        jsr     play_peek
        bcc     @no
        cmp     #'.'
        bne     @no
        jsr     play_adv
        lda     PLAY_DUR+1
        lsr     a
        sta     PLAY_TMP+1
        lda     PLAY_DUR
        ror     a
        sta     PLAY_TMP
        lda     PLAY_DUR
        clc
        adc     PLAY_TMP
        sta     PLAY_DUR
        lda     PLAY_DUR+1
        adc     PLAY_TMP+1
        sta     PLAY_DUR+1
@no:
        rts

; --- PLAY string cursor ----------------------------------------------------
play_peek:                              ; C=0 at end; else C=1 and A = next char
        lda     PLAY_LEN
        beq     @e
        ldy     #$00
        lda     (INDEX),y
        sec
        rts
@e:
        clc
        rts

play_adv:                               ; consume one char (after a kept peek)
        dec     PLAY_LEN
        inc     INDEX
        bne     @r
        inc     INDEX+1
@r:
        rts

play_getc:                              ; C=0 at end; else C=1 and A = char (consumed)
        jsr     play_peek
        bcc     @e
        pha
        jsr     play_adv
        pla
        sec
        rts
@e:
        clc
        rts

; --- PLAY number scan ------------------------------------------------------
; play_num: read a run of decimal digits (nothing consumed if none). Returns
; X = value (mod 256), C=1 if >= 1 digit was read, else C=0. Uses PLAY_TMP.
play_num:
        lda     #$00
        sta     PLAY_TMP               ; accumulator
        sta     PLAY_TMP+1             ; digit-seen flag
@l:
        jsr     play_peek
        bcc     @end
        cmp     #'0'
        bcc     @end
        cmp     #'9'+1
        bcs     @end
        jsr     play_adv
        and     #$0F
        pha                            ; [digit]
        lda     PLAY_TMP
        asl     a
        pha                            ; [digit, acc*2]
        asl     a
        asl     a                      ; acc*8
        sta     PLAY_TMP
        pla                            ; acc*2
        clc
        adc     PLAY_TMP              ; acc*10
        sta     PLAY_TMP
        pla                            ; digit
        clc
        adc     PLAY_TMP
        sta     PLAY_TMP
        lda     #$01
        sta     PLAY_TMP+1
        jmp     @l
@end:
        ldx     PLAY_TMP
        lda     PLAY_TMP+1
        beq     @none
        sec
        rts
@none:
        clc
        rts

; play_num_req: play_num, but SYNTAX ERROR (voices silenced) if no digits.
play_num_req:
        jsr     play_num
        jcc     play_syn
        rts

play_note_semi:                         ; A B C D E F G -> semitone within octave
        .byte   9, 11, 0, 2, 4, 5, 7
play_oct12:                             ; octave 0..7 -> base semitone
        .byte   0, 12, 24, 36, 48, 60, 72, 84

.ifdef STYLED_STRINGS
; ----------------------------------------------------------------------------
; BASIC style commands
;
; COLOR n       sets default palette color 0-15
; FLIPX/FLIPY n set/clear default flip bits (0=clear, nonzero=set)
; ALT n         set/clear default CHR_ALT/reverse bit (0=clear, nonzero=set)
; STYLE n       policy bitmask, user bits: 1=color, 2=flipX, 4=flipY, 8=ALT.
;               Internally stored as an overlay-attribute override mask:
;               $0F/$10/$20/$80. Bit off means use stored style; bit on means
;               use BASIC_DEFAULT_ATTR for that field.
; ----------------------------------------------------------------------------
BASIC_COLOR:
        jsr     GETBYT
        txa
        cmp     #$10
        bcs     @iq
        sta     TEMP1
        lda     BASIC_DEFAULT_ATTR
        and     #$B0            ; keep flip-X, flip-Y, CHR_ALT; clear color/raw
        ora     TEMP1
        jmp     style_store_default_attr
@iq:
        jmp     IQERR

BASIC_FLIPX:
        jsr     GETBYT
        lda     #$10
        jmp     style_set_default_bit

BASIC_FLIPY:
        jsr     GETBYT
        lda     #$20
        jmp     style_set_default_bit

BASIC_ALT:
        jsr     GETBYT
        lda     #$80
        jmp     style_set_default_bit

style_set_default_bit:
        sta     TEMP1
        txa
        beq     @clear
        lda     BASIC_DEFAULT_ATTR
        ora     TEMP1
        jmp     style_store_default_attr
@clear:
        lda     TEMP1
        eor     #$FF
        and     BASIC_DEFAULT_ATTR
style_store_default_attr:
        and     #DISPLAY_ATTR_MASK
        sta     BASIC_DEFAULT_ATTR      ; COLOR/FLIPX/FLIPY/ALT set the BASIC pen only.
        rts                             ; The live editor pen (TEXT_ATTR) is independent
                                        ; and is never overwritten here.

BASIC_STYLE:
        jsr     GETBYT
        txa
        cmp     #$10
        bcs     @iq
        lda     #$00
        sta     TEMP1
        txa
        and     #$01
        beq     :+
        lda     TEMP1
        ora     #$0F
        sta     TEMP1
:       txa
        and     #$02
        beq     :+
        lda     TEMP1
        ora     #$10
        sta     TEMP1
:       txa
        and     #$04
        beq     :+
        lda     TEMP1
        ora     #$20
        sta     TEMP1
:       txa
        and     #$08
        beq     :+
        lda     TEMP1
        ora     #$80
        sta     TEMP1
:       lda     TEMP1
        sta     BASIC_STYLE_MASK
        rts
@iq:
        jmp     IQERR

; A = stored string attr, including BASIC's internal STRING_RAW_TILE marker.
; Stores the effective attr into TEXT_ATTR according to BASIC_STYLE_MASK.
set_effective_text_attr:
        sta     TEMP1
        lda     BASIC_STYLE_MASK
        eor     #$FF
        and     TEMP1
        sta     TEMP1
        lda     BASIC_DEFAULT_ATTR
        and     BASIC_STYLE_MASK
        ora     TEMP1
        sta     TEXT_ATTR
        rts

; A = tile -> console drawn as a raw glyph, never interpreted as a control code.
; Used by STRPRT_STYLED for the high/graphic tile codes that styled strings carry
; (which would otherwise hit chrout's cursor-move/CR handling). Preserves A/X/Y.
MONCOUT_GLYPH:
        jmp KERN_CHROUT_GLYPH
.endif

.ifdef STYLED_STRINGS
; ----------------------------------------------------------------------------
; STRPRT_STYLED - PRINT a string applying per-character attributes. Entered via
; an absolute jmp from STRPRT (print.s) with A = N (length) and INDEX = character
; data pointer; FREFAC has already run. Heap strings carry an attribute half at
; (data + N); program-text literals/messages do not, and print at BASIC_DEFAULT_ATTR.
; Classify by data address: program text/messages below STREND are literals; heap
; strings sit at or above the heap bottom. We compare heap strings against DEST,
; a snapshot of FRETOP that STRPRT takes *before* FREFAC: FREFAC frees a printed
; temp and raises FRETOP above it, but the temp keeps its bytes (including the
; attr half), so classifying against the post-free FRETOP would misread a styled
; temp (PRINT A$+B$, PRINT LEFT$(A$,3)) as a literal. Lives in the EXTRA segment
; so it never perturbs the CODE segment's tight branches. See
; docs/styled-strings.md §3.7/§5.
; ----------------------------------------------------------------------------
STRPRT_STYLED:
        tax                     ; hold N while we stack the live pen
        lda     TEXT_ATTR
        pha                     ; save the pen *under* N; every exit restores it, so a
        txa                     ; styled string (whose per-char loop rewrites TEXT_ATTR)
        pha                     ; leaves the pen unchanged. Then save N, as before.
        lda     STREND
        ora     STREND+1
        beq     @class_heap
        ldy     INDEX+1
        cpy     STREND+1
        bcc     @lit
        bne     @class_heap
        ldy     INDEX
        cpy     STREND
        bcc     @lit
@class_heap:
        ldy     INDEX+1
        cpy     DEST+1          ; DEST = FRETOP snapshot from STRPRT (pre-FREFAC)
        bcc     @lit
        bne     @heap
        ldy     INDEX
        cpy     DEST
        bcc     @lit
@heap:
        pla                     ; A = N
        pha
        clc
        adc     INDEX           ; FRESPC = data + N (attribute base)
        sta     FRESPC
        lda     INDEX+1
        adc     #$00
        sta     FRESPC+1
        pla                     ; A = N
        tax
        ldy     #$00
        inx
@hloop:
        dex
        beq     @hdone
        lda     (FRESPC),y      ; this character's attribute
        jsr     set_effective_text_attr
        lda     (INDEX),y       ; the character / tile
        jsr     styled_outc
        iny
        jmp     @hloop
@hdone:
        pla                     ; restore the pen saved at entry (the editor pen for
        sta     TEXT_ATTR       ; user output; the BASIC pen for a STROUT message)
        rts
@lit:
        ; Numbers, unstyled literals and messages carry no attribute half and are
        ; plain unstyled text - including CR/LF formatting that CHROUT must interpret
        ; (message strings begin with CR+LF, and LF is ignored). So print them through
        ; plain OUTDO: only the heap path (graphic tile codes) needs raw-glyph output.
        ; They print at the BASIC pen - styled string literals are promoted to heap
        ; strings (STRLT2 / styled_program_literal_to_heap) and take the @heap path in
        ; their written colors, so only genuinely unstyled output reaches here. E.g.
        ; PRINT "FRAN";A prints FRAN in its stored color but the number A in the BASIC
        ; pen. The pen saved at entry is restored at @ldone. (STROUT messages arrive
        ; with the BASIC pen already loaded; this is consistent.)
        lda     BASIC_DEFAULT_ATTR
        sta     TEXT_ATTR
        pla                     ; A = N
        tax
        ldy     #$00
        inx
@lloop:
        dex
        beq     @ldone
        lda     (INDEX),y
        jsr     OUTDO
        iny
        cmp     #$0D
        bne     @lloop
        jsr     PRINTNULLS
        jmp     @lloop
@ldone:
        pla                     ; balance the pen saved at entry (literals leave it
        sta     TEXT_ATTR       ; unchanged, so this just restores the same value)
        rts

; ----------------------------------------------------------------------------
; styled_outc - output one byte of a *heap* (styled) string, pen already in
; TEXT_ATTR. Heap strings can carry graphic tile codes from Phase 5 glyph modes.
; Editor-harvested control-range tiles are tagged with STRING_RAW_TILE in their
; attr byte, so tile $0D can draw raw while CHR$(13) (minted with DEFAULT_ATTR)
; still breaks lines. Plain text $20-$7E goes through OUTDO; untagged $0D stays a
; newline; all other controls/high bytes draw raw via chrout_glyph. The raw path
; still advances POSX one column and honors Z14 (output suppress) to match OUTDO.
; NOT used for literals/messages (those go through plain OUTDO; see @lit).
; Preserves X/Y. See docs/styled-strings.md §3.6.
; ----------------------------------------------------------------------------
styled_outc:
        bit     TEXT_ATTR
        bvs     @tagged_raw
        cmp     #$0D
        beq     @cr
        cmp     #$20
        bcc     @raw
        cmp     #$7F
        bcs     @raw
        jmp     OUTDO           ; normal text (tail call)
@cr:
        jsr     OUTDO           ; carriage return -> newline
        jmp     PRINTNULLS      ; (tail call)
@tagged_raw:
        pha
        lda     TEXT_ATTR
        and     #DISPLAY_ATTR_MASK
        sta     TEXT_ATTR
        pla
@raw:
        bit     Z14
        bmi     @suppressed     ; output suppressed: match OUTDO (no draw, no POSX)
        pha
        jsr     MONCOUT_GLYPH   ; raw tile draw (kernel; preserves X/Y)
        inc     POSX            ; one column per glyph, as OUTDO does for >=$20
        pla
@suppressed:
        rts
.endif

; ============================================================================
; Background PLAY - fixed RAM control block, below RAMSTART2 ($5D00). Plain
; equates, never part of the loaded image (same pattern as KVARS/KJIFFY) - see
; Makefile MAX_KERNEL_BYTES and defines_clementina.s RAMSTART2. Persists across
; arbitrary BASIC execution between IRQ calls, so unlike blocking PLAY's
; STYLE_SIDE_BUF-based state, this can never be time-shared with the tokenizer
; or anything else. See docs/memory-map.md.
; ============================================================================
; BGP_IDX/BGP_LEN are a byte cursor/length into BGP_BUF, not a pointer pair,
; because BGP_BUF is a fixed compile-time address read with absolute,X/Y
; addressing (bg_peek) - (ptr),y indirect addressing (like INDEX in blocking
; PLAY) only works for zero-page pointers, and BGP_BUF is deliberately NOT in
; zero page (see the block header comment above).
BGP_BASE        = $5C00
BGP_FLAGS       = BGP_BASE + $00       ; bit0: background player active
BGP_IDX         = BGP_BASE + $01       ; read cursor into BGP_BUF (0-127)
BGP_LEN         = BGP_BASE + $02       ; valid bytes in BGP_BUF
BGP_TICKS       = BGP_BASE + $03       ; [2] ticks left on the current note/rest
BGP_VOICE       = BGP_BASE + $05       ; current voice record base ($10/$20/$30/$40)
BGP_OCTAVE      = BGP_BASE + $06
BGP_TEMPO       = BGP_BASE + $07
BGP_LDEF        = BGP_BASE + $08
BGP_SEMI        = BGP_BASE + $09       ; scratch: semitone in octave (signed -1..12)
BGP_FREQ        = BGP_BASE + $0A       ; [2] bg_note_freq result (private - NOT LINNUM,
                                        ; which arbitrary interrupted foreground code
                                        ; (POKE args, expressions) also uses as scratch)
BGP_TMP         = BGP_BASE + $0C       ; [2] bg parser scratch (digits / dotted-length)
BGP_SP          = BGP_BASE + $0E       ; saved 6502 stack pointer - see bg_next_event
BGP_BUF         = BGP_BASE + $0F       ; [128] copied MML text
BGP_BUF_SIZE    = 128

; DIR's own scratch, in the free space between BGP_BUF and RAMSTART2 ($5D00) -
; a name must be fully read out of the MIA dir-entry window into CPU RAM
; before any of it is printed. MONCOUT (kernel CHROUT) draws to the screen
; through MIA's own indexed-RAM window mechanism (the same IDXA_SELECT/
; IDXA_PORT pair DIR itself uses to read FS_READDIR results), so interleaving
; a read with a MONCOUT call lets CHROUT's own use of window A silently
; reposition it out from under DIR - confirmed the hard way: only an entry's
; first character came out right, with the rest replaced by whatever CHROUT
; had just left window A pointing at. 40 bytes comfortably covers any
; filename this console can usefully display (a 40-column screen).
DIR_NAME_BUF      = BGP_BUF + BGP_BUF_SIZE
DIR_NAME_BUF_SIZE = 40

BGP_FLAG_PLAYING = $01

; ----------------------------------------------------------------------------
; EXTFN_DISPATCH - TOKEN_EXTFN two-byte function dispatch, mirrors
; EXECUTE_STATEMENT1's @ext (flow1.s) but for functions and reached from
; eval.s's primary-expression dispatch instead of the statement dispatcher.
; Entered with A = TOKEN_EXTFN (just fetched, TXTPTR past it). Reads the
; subtoken, evaluates the mandatory "(expr)" via PARCHK exactly like every
; primary function (UNARY, eval.s) does, then jsr's the looked-up body and
; falls into the same CHKNUM tail UNARY uses, so the function's result (left
; in FAC1, e.g. by SNGFLT) is validated like any other numeric factor.
; ----------------------------------------------------------------------------
EXTFN_DISPATCH:
        jsr     CHRGET                  ; A = subtoken ($80|index)
        sec
        sbc     #$80
        cmp     #NUM_EXTFN_TOKENS
        bcs     @synerr                 ; unknown subtoken -> SYNTAX ERROR
        pha
        jsr     CHRGET                  ; step past the subtoken -> A = the char after it
        jsr     PARCHK                  ; consume "(expr)": CHKOPN+FRMEVL+CHKCLS
        pla
        asl     a
        tay
        lda     EXTFN_ADDRESS_TABLE+1,y
        sta     JMPADRS+2
        lda     EXTFN_ADDRESS_TABLE,y
        sta     JMPADRS+1
        jsr     JMPADRS
        jmp     CHKNUM
@synerr:
        jmp     SYNERR

; ----------------------------------------------------------------------------
; PLAYING(0) - background PLAY status, 0 or 1. Dummy argument required: it is
; registered in the EXTFN_NAME_TABLE / EXTFN_ADDRESS_TABLE (token.s) and
; dispatched via TOKEN_EXTFN + EXTFN_DISPATCH above, which - like UNARY does
; for every primary function - has already evaluated (and discarded) "(expr)"
; by the time this body runs. Same idiom as classic MS BASIC's FRE(0); there
; is no bare/niladic function form in this interpreter.
; ----------------------------------------------------------------------------
BASIC_PLAYING:
        ldy     #$00
        lda     BGP_FLAGS
        and     #BGP_FLAG_PLAYING
        beq     @done
        iny
@done:
        jmp     SNGFLT

; ----------------------------------------------------------------------------
; bg_play_start: PLAY s$,n (n<>0) tail-jumps here with INDEX -> string bytes
; and PLAY_LEN = length (both set by FRESTR in BASIC_PLAY). Silences whatever
; was playing (foreground or background - a stuck orphaned note from a
; replaced background song must not survive), copies the string into
; BGP_BUF (truncating to BGP_BUF_SIZE), resets the parser state to the PLAY
; defaults, and starts the sequencer. BGP_FLAGS is cleared first and set last
; so bg_play_tick (not yet wired - lands in a later step) never sees a
; half-written buffer.
; ----------------------------------------------------------------------------
bg_play_start:
        lda     #$00
        sta     BGP_FLAGS
        jsr     play_all_off
        lda     PLAY_LEN
        cmp     #BGP_BUF_SIZE+1
        bcc     @lenok
        lda     #BGP_BUF_SIZE           ; truncate an over-long string
@lenok:
        sta     BGP_TMP                 ; byte count to copy (temp use before playback starts)
        ldy     #$00
@copy:
        cpy     BGP_TMP
        beq     @copied
        lda     (INDEX),y
        sta     BGP_BUF,y
        iny
        bne     @copy
@copied:
        sty     BGP_LEN                 ; Y = count copied
        lda     #$00
        sta     BGP_IDX
        lda     #PLAY_OCT_DEF
        sta     BGP_OCTAVE
        lda     #PLAY_TEMPO_DEF
        sta     BGP_TEMPO
        lda     #PLAY_LDEF_DEF
        sta     BGP_LDEF
        lda     #$10
        sta     BGP_VOICE               ; voice 0
        lda     #$00
        sta     BGP_TICKS
        sta     BGP_TICKS+1             ; 0 ticks left -> the first IRQ tick advances at once
        lda     #BGP_FLAG_PLAYING
        sta     BGP_FLAGS
        rts

; ----------------------------------------------------------------------------
; bg_play_stop: stop the background player and release its voices. Callable
; from foreground (bare PLAY) or from a teardown hook (STOP/END/Ctrl-C, ERROR,
; NEW - added in a later step).
; ----------------------------------------------------------------------------
bg_play_stop:
        lda     #$00
        sta     BGP_FLAGS
        jmp     play_all_off            ; tail: silence all 4 voices, then rts

; ============================================================================
; Background PLAY sequencer - called from the Timer-1 IRQ (interrupts.s), once
; per tick, after KJIFFY is bumped. Mirrors BASIC_PLAY's parser/emitter
; (@loop, play_do_note, play_do_rest, play_note_on, play_len_to_dur,
; play_maybe_dot, play_num/peek/adv/getc, play_len_ok, note_freq) but as
; standalone bg_* routines over BGP_PTR/BGP_END/BGP_BUF instead of
; INDEX/PLAY_LEN/STYLE_SIDE_BUF, because this runs with interrupts masked and
; can be "between" arbitrary interrupted foreground code:
;   - STYLE_SIDE_BUF-based PLAY_* state is safe only because blocking PLAY
;     monopolizes execution; this needs its own dedicated RAM (BGP_*).
;   - note_freq writes LINNUM/LINNUM+1, which interrupted foreground code
;     (a POKE argument, an expression) may be mid-use of - bg_note_freq
;     writes BGP_FREQ instead.
;   - snd_seek/snd_wr1 ARE reused unchanged: every foreground burst that
;     touches MIA index window B is already php/sei/plp-fenced, so it can
;     never be mid-burst when this IRQ runs.
;   - play_iq/play_syn (SYNTAX ERROR/ILLEGAL QUANTITY) must never run here -
;     they call STKINI, which resets the 6502 stack and jumps back into the
;     interpreter, abandoning this IRQ's own return address (never RTI's).
;     A bad token or number here just stops the player instead of erroring.
; ============================================================================

; bg_play_tick: advance the background player by one kernel tick. If a
; note/rest is still counting down, decrement BGP_TICKS (16-bit) and return;
; at zero, parse the next event via bg_next_event. No-op if not playing.
bg_play_tick:
        lda     BGP_FLAGS
        beq     @out
        lda     BGP_TICKS
        ora     BGP_TICKS+1
        beq     @advance
        lda     BGP_TICKS
        bne     @decok
        dec     BGP_TICKS+1
@decok:
        dec     BGP_TICKS
        rts
@advance:
        jsr     bg_next_event
@out:
        rts

; bg_next_event: parse and act on MML tokens starting at BGP_PTR until a
; note/rest is emitted (sets BGP_TICKS; the caller above then lets the IRQ
; count it down over later ticks) or the string ends. O/</>/L/T/V/W apply
; immediately and the loop continues within this same call - they consume no
; time.
;
; Sub-parsers (bg_num_req, bg_len_ok, ...) are called with jsr and abort a bad
; token/number by jumping to bg_next_event_bad rather than returning - on
; purpose, so a single bad token stops everything instead of unwinding one
; jsr at a time. But that jmp does not pop the return address its own jsr
; pushed, and callers can be nested several deep (e.g. bg_do_note -> bg_num ->
; bg_len_ok), so left alone each abort leaks one stack slot per jsr level -
; corrupting the very next rts (observed: it returned into the middle of the
; aborted command instead of back to bg_play_tick, replaying the rest of the
; string). Fix: snapshot S once here, on entry - constant across the O/L/T/V/W
; loop-back below, since that only ever jmps - and reload it in
; bg_next_event_bad/_done before the final rts, discarding whatever the
; abort left on the stack no matter how deep it happened.
bg_next_event:
        tsx
        stx     BGP_SP
        jsr     bg_getc
        jcc     bg_next_event_done      ; end of string
        jsr     TOKEN_UPPER             ; keywords are case-insensitive
        cmp     #' '
        beq     bg_next_event
        cmp     #','
        beq     bg_next_event
        cmp     #'A'
        bcc     @sym
        cmp     #'G'+1
        bcs     @sym
        jmp     bg_do_note              ; A = 'A'..'G'; sets BGP_TICKS and returns
@sym:
        cmp     #'R'
        beq     @rest
        cmp     #'P'
        beq     @rest
        cmp     #'<'
        beq     @octdn
        cmp     #'>'
        beq     @octup
        cmp     #'O'
        beq     @oct
        cmp     #'L'
        beq     @ldef
        cmp     #'T'
        beq     @tempo
        cmp     #'V'
        beq     @voice
        cmp     #'W'
        beq     @wave
        jmp     bg_next_event_bad       ; unknown token
@rest:
        jmp     bg_do_rest              ; sets BGP_TICKS and returns
@octdn:
        lda     BGP_OCTAVE
        beq     bg_next_event
        dec     BGP_OCTAVE
        jmp     bg_next_event
@octup:
        lda     BGP_OCTAVE
        cmp     #7
        bcs     bg_next_event
        inc     BGP_OCTAVE
        jmp     bg_next_event
@oct:
        jsr     bg_num_req              ; X = value
        cpx     #8
        bcs     bg_next_event_bad
        stx     BGP_OCTAVE
        jmp     bg_next_event
@tempo:
        jsr     bg_num_req
        cpx     #$00
        bne     :+
        ldx     #$01                    ; T0 -> 1
:       stx     BGP_TEMPO
        jmp     bg_next_event
@voice:
        jsr     bg_num_req
        cpx     #4
        bcs     bg_next_event_bad
        txa
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #$10                    ; -> $10/$20/$30/$40
        sta     BGP_VOICE
        jmp     bg_next_event
@wave:
        jsr     bg_num_req
        cpx     #5
        bcs     bg_next_event_bad
        lda     BGP_VOICE
        clc
        adc     #AUDV_WAVEFORM
        jsr     snd_wr1                 ; A = offset, X = value
        jmp     bg_next_event
@ldef:
        jsr     bg_num_req
        jsr     bg_len_ok
        stx     BGP_LDEF
        jmp     bg_next_event

; End of string, or a malformed token/number: unlike blocking PLAY neither
; case can raise an error here (see the header note above) - both just stop
; the player and silence every voice. Reload S from the bg_next_event-entry
; snapshot first - discards any stack slots left by a jsr'd sub-parser that
; aborted here mid-nesting (see the comment on bg_next_event above), so the
; jmp below returns cleanly to bg_play_tick regardless of how deep this was
; reached from.
bg_next_event_done:
bg_next_event_bad:
        ldx     BGP_SP
        txs
        jmp     bg_play_stop

; --- bg PLAY note / rest -----------------------------------------------------
; bg_do_note: A = 'A'..'G'. Emits FREQ + gate-on for one note and sets
; BGP_TICKS to its duration. Mirrors play_do_note (clementina_extra.s).
bg_do_note:
        sec
        sbc     #'A'
        tax
        lda     play_note_semi,x
        sta     BGP_SEMI
        jsr     bg_peek
        bcc     @len
        cmp     #'#'
        beq     @sharp
        cmp     #'+'
        beq     @sharp
        cmp     #'-'
        beq     @flat
        jmp     @len
@sharp:
        jsr     bg_adv
        inc     BGP_SEMI
        jmp     @len
@flat:
        jsr     bg_adv
        dec     BGP_SEMI
@len:
        jsr     bg_num                  ; C=1 & X=code if length digits present
        bcs     @havelen
        ldx     BGP_LDEF
@havelen:
        jsr     bg_len_ok
        jsr     bg_len_to_dur
        jsr     bg_maybe_dot
        ldx     BGP_OCTAVE
        lda     play_oct12,x
        clc
        adc     BGP_SEMI                ; octave base + semitone (signed)
        cmp     #96
        bcc     @emit
        cmp     #$80
        bcs     @zero                   ; wrapped negative -> clamp low
        lda     #95
        bne     @emit
@zero:
        lda     #$00
@emit:
        jmp     bg_note_on              ; tail: sets FREQ/gate, rts's to bg_play_tick

; bg_do_rest: gate the current voice off; BGP_TICKS already holds one length.
bg_do_rest:
        jsr     bg_num
        bcs     @havelen
        ldx     BGP_LDEF
@havelen:
        jsr     bg_len_ok
        jsr     bg_len_to_dur
        jsr     bg_maybe_dot
        lda     BGP_VOICE
        clc
        adc     #AUDV_CONTROL
        ldx     #$00
        jmp     snd_wr1                 ; tail: CONTROL = 0 -> release, rts

; bg_note_on: A = absolute semitone 0-95 -> release the current voice, set
; FREQ_L/H, then gate on with RESET_PHASE. Mirrors play_note_on, minus the
; php/sei/plp fence: this already runs with interrupts masked (it IS the
; IRQ), so nothing else can interleave a partial MIA index-window B burst.
bg_note_on:
        jsr     bg_note_freq            ; BGP_FREQ = Hz * 16
        lda     BGP_VOICE
        tax
        txa
        clc
        adc     #AUDV_CONTROL
        jsr     snd_seek                ; base + AUDV_CONTROL
        lda     #$00
        sta     IDXB_PORT               ; CONTROL = 0: release any sounding note
        txa
        jsr     snd_seek                ; base + AUDV_FREQ_L ($00)
        lda     BGP_FREQ
        sta     IDXB_PORT
        lda     BGP_FREQ+1
        sta     IDXB_PORT
        txa
        clc
        adc     #AUDV_CONTROL
        jsr     snd_seek
        lda     #AUD_GATE_RETRIG
        sta     IDXB_PORT               ; CONTROL = GATE|RESET_PHASE: re-attack
        rts

; bg_note_freq: A = semitone 0-95 -> BGP_FREQ/BGP_FREQ+1 = Hz*16. Private
; twin of note_freq (clementina_extra.s), which must not run here - it uses
; LINNUM, shared with interrupted foreground expression evaluation. Shares
; note_freq_tbl (pure RODATA, no mutable state).
bg_note_freq:
        sec
        ldx     #$FF
@div:
        inx
        sbc     #12
        bcs     @div
        adc     #12
        asl     a
        tay
        lda     note_freq_tbl,y
        sta     BGP_FREQ
        lda     note_freq_tbl+1,y
        sta     BGP_FREQ+1
@shift:
        cpx     #$00
        beq     @done
        asl     BGP_FREQ
        rol     BGP_FREQ+1
        dex
        bne     @shift
@done:
        rts

; --- bg PLAY length -> duration ----------------------------------------------
; bg_len_ok: X in {1,2,4,8,16,32} -> return; else stop the player (no error -
; see the header note above).
bg_len_ok:
        cpx     #1
        beq     @ok
        cpx     #2
        beq     @ok
        cpx     #4
        beq     @ok
        cpx     #8
        beq     @ok
        cpx     #16
        beq     @ok
        cpx     #32
        beq     @ok
        jmp     bg_next_event_bad
@ok:
        rts

; bg_len_to_dur: X = valid length code -> BGP_TICKS (16-bit), from BGP_TEMPO.
; Mirrors play_len_to_dur.
bg_len_to_dur:
        lda     BGP_TEMPO
        sta     BGP_TICKS
        lda     #$00
        sta     BGP_TICKS+1
        cpx     #4
        beq     @min
        bcs     @right
        cpx     #1
        bne     @one
        jsr     @shl                    ; k=1: two left shifts
@one:
        jsr     @shl                    ; k=1 or k=2: one more
        jmp     @min
@right:
        jsr     @shr
        cpx     #8
        beq     @min
        jsr     @shr
        cpx     #16
        beq     @min
        jsr     @shr
@min:
        lda     BGP_TICKS
        ora     BGP_TICKS+1
        bne     @ret
        lda     #$01
        sta     BGP_TICKS
@ret:
        rts
@shl:
        asl     BGP_TICKS
        rol     BGP_TICKS+1
        rts
@shr:
        lsr     BGP_TICKS+1
        ror     BGP_TICKS
        rts

; bg_maybe_dot: if the next char is '.', consume it and BGP_TICKS += BGP_TICKS/2.
bg_maybe_dot:
        jsr     bg_peek
        bcc     @no
        cmp     #'.'
        bne     @no
        jsr     bg_adv
        lda     BGP_TICKS+1
        lsr     a
        sta     BGP_TMP+1
        lda     BGP_TICKS
        ror     a
        sta     BGP_TMP
        lda     BGP_TICKS
        clc
        adc     BGP_TMP
        sta     BGP_TICKS
        lda     BGP_TICKS+1
        adc     BGP_TMP+1
        sta     BGP_TICKS+1
@no:
        rts

; --- bg PLAY string cursor ---------------------------------------------------
; bg_peek: C=0 at end (BGP_IDX = BGP_LEN); else C=1 and A = next char. BGP_BUF
; is a fixed address, so this is plain absolute,X addressing - no zero-page
; pointer needed (see the BGP_IDX/BGP_LEN comment above the control block).
bg_peek:
        ldx     BGP_IDX
        cpx     BGP_LEN
        bcs     @end
        lda     BGP_BUF,x
        sec
        rts
@end:
        clc
        rts

; bg_adv: consume one char (after a kept peek).
bg_adv:
        inc     BGP_IDX
        rts

; bg_getc: C=0 at end; else C=1 and A = char (consumed).
bg_getc:
        jsr     bg_peek
        bcc     @e
        pha
        jsr     bg_adv
        pla
        sec
        rts
@e:
        clc
        rts

; --- bg PLAY number scan -----------------------------------------------------
; bg_num: read a run of decimal digits. Returns X = value (mod 256), C=1 if
; >= 1 digit was read, else C=0. Uses BGP_TMP.
bg_num:
        lda     #$00
        sta     BGP_TMP
        sta     BGP_TMP+1
@l:
        jsr     bg_peek
        bcc     @end
        cmp     #'0'
        bcc     @end
        cmp     #'9'+1
        bcs     @end
        jsr     bg_adv
        and     #$0F
        pha
        lda     BGP_TMP
        asl     a
        pha
        asl     a
        asl     a
        sta     BGP_TMP
        pla
        clc
        adc     BGP_TMP
        sta     BGP_TMP
        pla
        clc
        adc     BGP_TMP
        sta     BGP_TMP
        lda     #$01
        sta     BGP_TMP+1
        jmp     @l
@end:
        ldx     BGP_TMP
        lda     BGP_TMP+1
        beq     @none
        sec
        rts
@none:
        clc
        rts

; bg_num_req: bg_num, but stop the player (no error) if no digits were read.
bg_num_req:
        jsr     bg_num
        jcc     bg_next_event_bad
        rts

; ============================================================================
; File I/O (see docs/basic-file.md): OPEN/CLOSE/BGET#/BPUT# against MIA's
; SD/FAT layer. BASIC-visible file numbers 1-16 map directly onto MIA's 16
; file-handle slots (SD_HANDLE_SELECT), one-to-one, with no allocator - the
; programmer picks the number, same as every historical BASIC's OPEN. See
; clementina-mia docs/sd.md and sd-programmer-guide.md for the protocol this
; wraps.
; ============================================================================

; MIA SD/FS register subset. BASIC does not include kernel.inc; full map in
; src/kernel/kernel.inc and the clementina-mia repo.
STATUS_H              = $FFEB

MIA_SD_INDEX_CONTROL  = $E0
MIA_FS_INDEX_PATH     = $E2
MIA_FS_INDEX_TRANSFER = $E4
MIA_FS_INDEX_PATH2    = $E5    ; FS_RENAME's destination path; overlays the transfer buffer

MIA_CMD_FS_OPEN       = $7B
MIA_CMD_FS_READ       = $7C
MIA_CMD_FS_CLOSE      = $7D
MIA_CMD_FS_WRITE      = $7F
MIA_CMD_FS_LOAD_MIA   = $7E    ; FS_LOAD_TO_MIA_RAM: file -> MIA RAM, no CPU byte-touching
MIA_CMD_FS_SAVE_MIA   = $87    ; FS_SAVE_FROM_MIA_RAM: MIA RAM -> file
MIA_CMD_FS_SEEK       = $81
MIA_CMD_FS_MKDIR      = $83
MIA_CMD_FS_DELETE     = $84
MIA_CMD_FS_RENAME     = $85
MIA_CMD_FS_OPENDIR    = $79
MIA_CMD_FS_READDIR    = $7A
MIA_CMD_FS_CHDIR      = $88

; SD/FS control block field offsets (relative to selecting MIA_SD_INDEX_CONTROL).
SD_LAST_ERROR         = $02
SD_REQUEST_LEN_L      = $08
SD_DEST_ADDR_L        = $0C    ; 24-bit MIA RAM address for the LOAD_MIA/SAVE_MIA jobs
SD_OPEN_MODE          = $10
SD_EOF                = $11
SD_FILE_POS0          = $1C    ; 32-bit file position; input to FS_SEEK
SD_HANDLE_SELECT      = $2E

; Directory entry buffer field offsets (relative to selecting
; MIA_FS_INDEX_DIR_ENTRY) - filled by FS_READDIR/FS_STAT.
MIA_FS_INDEX_DIR_ENTRY = $E3
DIR_ATTR               = $00
DIR_NAME_LEN           = $01
DIR_NAME               = $0C
DIR_ATTR_DIRECTORY     = $10
SD_TRANSFER_LEN0      = $2A    ; 32-bit byte count for FS_SAVE_FROM_MIA_RAM

FS_OPEN_READ          = $00
FS_OPEN_WRITE_CREATE  = $01
FS_OPEN_WRITE_APPEND  = $02

STATUS_H_SD_BUSY      = %00000100      ; bit 2 of STATUS_H (MIA_STAT_SD_BUSY, bit 10 overall)

mia_fileerr:
        ldx     #ERR_FILEIO
        jmp     ERROR

mia_typerr:
        ldx     #ERR_BADTYPE
        jmp     ERROR

; mia_sd_seek: A = SD/FS control block field offset. Selects the control
; block index and steps IDXA_PORT forward to that offset, ready for the next
; read/write. Clobbers A,X.
; Absolute address of the SD/FS control block (see MIA_SD_STATE_OFFSET in
; clementina-mia sd.h), as CFG_IDXA_ADDR_M/_H bytes - the low byte varies per
; field and is written last, from the caller-supplied offset.
SD_CONTROL_ADDR_M     = $30
SD_CONTROL_ADDR_H     = $01

mia_sd_seek:
        ; Reposition window A's current address directly via CFG, rather than
        ; reselecting the index and reading/skipping N bytes: writing
        ; IDXA_SELECT does NOT rewind the index's current address (it only
        ; reflects whatever position a *previous* access left it at), so the
        ; skip-N-reads approach silently drifts across repeated calls instead
        ; of ever landing on a fixed field. This mirrors vid_seek's own
        ; absolute-addressing approach in this same file.
        pha
        lda     #MIA_SD_INDEX_CONTROL
        sta     IDXA_SELECT
        lda     #CFG_IDXA_ADDR_H
        sta     CFG_SELECT
        lda     #SD_CONTROL_ADDR_H
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_M
        sta     CFG_SELECT
        lda     #SD_CONTROL_ADDR_M
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_L
        sta     CFG_SELECT
        pla                             ; field offset -> current address low byte
        sta     CFG_PORT
        rts

; mia_sd_wait: poll until MIA_STAT_SD_BUSY clears. Clobbers A.
mia_sd_wait:
        lda     STATUS_H
        and     #STATUS_H_SD_BUSY
        bne     mia_sd_wait
        rts

; mia_sd_cmd: A = command id. Clears CMD_PARAM1-3, triggers the command,
; waits for completion, and leaves SD_LAST_ERROR in A (Z set if zero, i.e.
; success). Clobbers A,X.
mia_sd_cmd:
        pha
        lda     #$00
        sta     CMD_PARAM1
        sta     CMD_PARAM2
        sta     CMD_PARAM3
        pla
        sta     CMD_TRIGGER
        jsr     mia_sd_wait
        lda     #SD_LAST_ERROR
        jsr     mia_sd_seek
        lda     IDXA_PORT
        rts

; mia_sd_select_handle: X = slot (0-15). Writes SD_HANDLE_SELECT. Clobbers
; A,X.
mia_sd_select_handle:
        txa
        pha
        lda     #SD_HANDLE_SELECT
        jsr     mia_sd_seek
        pla
        sta     IDXA_PORT
        rts

; mia_sd_write_path: writes the string at (INDEX), length A (as left by
; FREFAC), into the SD/FS path buffer, null-terminated. Clobbers A,X,Y.
mia_sd_write_path:
        ; Reposition to the path buffer's start via CFG before writing - same
        ; reasoning as mia_sd_seek: selecting the index does not rewind it,
        ; so without this a second OPEN in the same session would start
        ; writing wherever the previous path write left off.
        pha
        lda     #MIA_FS_INDEX_PATH
        sta     IDXA_SELECT
        lda     #CFG_IDXA_ADDR_H
        sta     CFG_SELECT
        lda     #$01
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_M
        sta     CFG_SELECT
        lda     #$32
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_L
        sta     CFG_SELECT
        lda     #$40
        sta     CFG_PORT
        pla
        tax
        ldy     #$00
        cpx     #$00
        beq     @term
@loop:  lda     (INDEX),y
        sta     IDXA_PORT
        iny
        dex
        bne     @loop
@term:  lda     #$00
        sta     IDXA_PORT
        rts

; mia_sd_write_path2: like mia_sd_write_path, but targets the second path
; buffer ($E5, MIA_FS_INDEX_PATH2) - FS_RENAME's destination path. Overlays
; the first 256 bytes of the transfer buffer, so do not rely on transfer data
; surviving a rename. A = length (as left by FREFAC), INDEX = pointer.
; Clobbers A,X,Y.
mia_sd_write_path2:
        pha
        lda     #MIA_FS_INDEX_PATH2
        sta     IDXA_SELECT
        lda     #CFG_IDXA_ADDR_H
        sta     CFG_SELECT
        lda     #$01
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_M
        sta     CFG_SELECT
        lda     #$34
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_L
        sta     CFG_SELECT
        lda     #$40
        sta     CFG_PORT
        pla
        tax
        ldy     #$00
        cpx     #$00
        beq     @term
@loop:  lda     (INDEX),y
        sta     IDXA_PORT
        iny
        dex
        bne     @loop
@term:  lda     #$00
        sta     IDXA_PORT
        rts

; mia_parse_path_expr: evaluates the string expression starting right here
; (no leading comma) and writes it as the SD/FS path. Shared by the plain
; single-path commands (KILL/MKDIR/RMDIR) that take "path" as their only
; argument, with nothing before it to consume. Clobbers A,X,Y.
mia_parse_path_expr:
        jsr     FRMEVL
        bit     VALTYP
        jpl     mia_typerr
        jsr     FREFAC
        jmp     mia_sd_write_path

; mia_getadr24: like GETADR, but accepts values up to 2^24-1 instead of 16
; bits - comfortably covers MIA's 256KB (2^18) address space with headroom.
; Call right after FRMNUM, same as GETADR. Result goes directly into VID_ADDR
; (low byte) through VID_ADDR+2 (high byte), mirroring how the video bulk
; commands already use VID_ADDR as "the destination address about to be
; used", rather than through LINNUM (GETADR's own 16-bit-only output). The
; exponent ceiling is $99: GETADR's own $91 ceiling accepts exponents up to
; $90 (values < 2^16 = 8 more bits than $80's zero point); the same relation
; scaled to 24 bits is $98 accepted / $99 rejected. Clobbers A,X,Y.
mia_getadr24:
        lda     FACSIGN
        jmi     snd_iqerr
        lda     FAC
        cmp     #$99
        jcs     snd_iqerr
        jsr     QINT
        lda     FAC_LAST-2
        sta     VID_ADDR+2
        lda     FAC_LAST-1
        sta     VID_ADDR+1
        lda     FAC_LAST
        sta     VID_ADDR
        rts

; mia_parse_path_arg: expects ",\"file\"" next in the source text - consumes
; the comma, evaluates the string expression, and writes it as the SD/FS
; path. Used by every asset command whose filename is its LAST argument
; (CHRLOAD/PALLOAD/OAMLOAD/NTLOAD/ATRLOAD and their *SAVE siblings; MIALOAD/
; MIASAVE take their filename first instead, so they call FRMEVL/FREFAC/
; mia_sd_write_path directly). Tail-calls mia_sd_write_path.
mia_parse_path_arg:
        jsr     CHKCOM
        jsr     FRMEVL
        bit     VALTYP
        jpl     mia_typerr
        jsr     FREFAC
        jmp     mia_sd_write_path

; mia_sd_load_trigger: VID_ADDR (24-bit destination) and VID_COUNT (16-bit
; max length, 0 = load until EOF or the end of MIA RAM) must already be set,
; and the path already written. Triggers FS_LOAD_TO_MIA_RAM - a whole-file
; job the firmware runs internally in 512-byte chunks, with no CPU byte-
; touching at all. Clobbers A,X.
mia_sd_load_trigger:
        lda     #SD_DEST_ADDR_L
        jsr     mia_sd_seek
        lda     VID_ADDR
        sta     IDXA_PORT
        lda     VID_ADDR+1
        sta     IDXA_PORT
        lda     VID_ADDR+2
        sta     IDXA_PORT
        lda     #SD_REQUEST_LEN_L
        jsr     mia_sd_seek
        lda     VID_COUNT
        sta     IDXA_PORT
        lda     VID_COUNT+1
        sta     IDXA_PORT
        lda     #MIA_CMD_FS_LOAD_MIA
        jsr     mia_sd_cmd
        jne     mia_fileerr
        rts

; mia_sd_save_trigger: same preconditions as mia_sd_load_trigger, in reverse -
; triggers FS_SAVE_FROM_MIA_RAM (create/truncate; use OPEN+BPUT# instead if
; appending is ever needed). VID_COUNT is zero-extended into the 32-bit
; SD_TRANSFER_LEN field. Clobbers A,X.
mia_sd_save_trigger:
        lda     #SD_DEST_ADDR_L
        jsr     mia_sd_seek
        lda     VID_ADDR
        sta     IDXA_PORT
        lda     VID_ADDR+1
        sta     IDXA_PORT
        lda     VID_ADDR+2
        sta     IDXA_PORT
        lda     #SD_OPEN_MODE
        jsr     mia_sd_seek
        lda     #FS_OPEN_WRITE_CREATE
        sta     IDXA_PORT
        lda     #SD_TRANSFER_LEN0
        jsr     mia_sd_seek
        lda     VID_COUNT
        sta     IDXA_PORT
        lda     VID_COUNT+1
        sta     IDXA_PORT
        lda     #$00
        sta     IDXA_PORT
        sta     IDXA_PORT
        lda     #MIA_CMD_FS_SAVE_MIA
        jsr     mia_sd_cmd
        jne     mia_fileerr
        rts

; mia_sd_select_transfer: binds window A to the FS transfer buffer and resets
; its position to offset 0 - same reasoning as mia_sd_seek/mia_sd_write_path
; (selecting an index does not rewind it). Clobbers A.
mia_sd_select_transfer:
        lda     #MIA_FS_INDEX_TRANSFER
        sta     IDXA_SELECT
        lda     #CFG_IDXA_ADDR_H
        sta     CFG_SELECT
        lda     #$01
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_M
        sta     CFG_SELECT
        lda     #$34
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_L
        sta     CFG_SELECT
        lda     #$40
        sta     CFG_PORT
        rts

; mia_sd_select_dir_entry: binds window A to the directory-entry buffer
; (MIA_FS_INDEX_DIR_ENTRY, $013340) and resets its position to offset 0 -
; same reasoning as mia_sd_select_transfer. Used by DIR to read back each
; FS_READDIR result. Clobbers A.
mia_sd_select_dir_entry:
        lda     #MIA_FS_INDEX_DIR_ENTRY
        sta     IDXA_SELECT
        lda     #CFG_IDXA_ADDR_H
        sta     CFG_SELECT
        lda     #$01
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_M
        sta     CFG_SELECT
        lda     #$33
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_L
        sta     CFG_SELECT
        lda     #$40
        sta     CFG_PORT
        rts

; mia_match_word: A/Y = pointer to a null-terminated literal word (uppercase
; ASCII). Matches it against upcoming source text one character at a time via
; CHRGET, consuming each matched character; SYNTAX ERROR on any mismatch (our
; fixed OPEN grammar never needs to backtrack a partial match). Clobbers
; A,FORPNT (a genuine adjacent 2-byte zero-page pointer pair - unlike
; TEMP1/TEMP2, which are NOT adjacent in this codebase's zero-page layout and
; so cannot back (TEMP1),y indirection).
mia_match_word:
        sta     FORPNT
        sty     FORPNT+1
@loop:  ldy     #$00
        lda     (FORPNT),y
        beq     @done
        cmp     (TXTPTR),y
        jne     SYNERR
        jsr     CHRGET
        inc     FORPNT
        bne     @loop
        inc     FORPNT+1
        jmp     @loop
@done:  rts

lit_OUTPUT: .byte "OUTPUT", 0
lit_APPEND: .byte "APPEND", 0
lit_AS:     .byte "AS", 0

; mia_store_byte: A = byte value (0-255) to store into the numeric variable
; named next in the source text. Mirrors LET's own numeric-assignment tail:
; PTRGET locates the variable (VALTYP+1 records its int/float-ness), GIVAYF
; floats our byte into FAC, then FAC is stored into the variable either as a
; 2-byte integer or copied whole as a float. Errors with TYPE MISMATCH if the
; named variable is a string. Clobbers A,X,Y.
mia_store_byte:
        pha
        jsr     PTRGET                  ; A,Y -> variable's value slot
        bit     VALTYP
        jmi     mia_typerr              ; can't BGET# into a string variable
        sta     FORPNT
        sty     FORPNT+1
        pla
        tay                             ; Y = byte value (low)
        lda     #$00                    ; A = 0 (high byte)
        jsr     GIVAYF                  ; float A:Y into FAC
        lda     VALTYP+1
        bpl     @float
        jsr     ROUND_FAC
        jsr     AYINT
        ldy     #$00
        lda     FAC+3
        sta     (FORPNT),y
        iny
        lda     FAC+4
        sta     (FORPNT),y
        rts
@float:
        ; A verbatim byte-for-byte copy of FAC is wrong here: FAC+1's top bit
        ; is the implicit, always-1 leading mantissa bit while "live" (pre-
        ; normalization already guarantees it), not the real sign - the real
        ; sign lives separately in FACSIGN until packed into that same bit for
        ; storage. SETFOR (float.s, LET's own float-target path) already does
        ; that FACSIGN/FAC+1 merge correctly - jump there, not straight to its
        ; STORE_FAC_AT_YX_ROUNDED tail, which expects X/Y already loaded from
        ; FORPNT (SETFOR's own first two instructions); skipping that left
        ; X/Y holding whatever they last held, storing through a stale
        ; pointer instead of ours.
        jmp     SETFOR

; ----------------------------------------------------------------------------
; OPEN "file" FOR mode AS #n
; ----------------------------------------------------------------------------
BASIC_OPEN:
        jsr     FRMEVL                  ; evaluate the filename expression
        bit     VALTYP
        jpl     mia_typerr              ; must be a string
        jsr     FREFAC                  ; A = length, INDEX = pointer
        jsr     mia_sd_write_path
        lda     #TOKEN_FOR
        jsr     SYNCHR
        ldy     #$00
        lda     (TXTPTR),y
        cmp     #TOKEN_INPUT
        bne     @notinput
        jsr     CHRGET
        lda     #FS_OPEN_READ
        jmp     @gotmode
@notinput:
        cmp     #'O'
        bne     @notoutput
        lda     #<lit_OUTPUT
        ldy     #>lit_OUTPUT
        jsr     mia_match_word
        lda     #FS_OPEN_WRITE_CREATE
        jmp     @gotmode
@notoutput:
        cmp     #'A'
        beq     @isappend
        jmp     SYNERR
@isappend:
        lda     #<lit_APPEND
        ldy     #>lit_APPEND
        jsr     mia_match_word
        lda     #FS_OPEN_WRITE_APPEND
@gotmode:
        ; Stash the mode byte in TEMP1, not the hardware stack: GETBYT's
        ; expression evaluation (FRMNUM/FRMEVL) uses the processor stack
        ; internally, so a value pushed here would not reliably survive a
        ; later GETBYT call - the same reason every existing bulk-load
        ; handler (BGCHAR, PALLOAD, ...) stashes cross-call values in
        ; TEMP1-3/LINNUM rather than with pha/pla.
        sta     TEMP1
        lda     #<lit_AS
        ldy     #>lit_AS
        jsr     mia_match_word
        lda     #'#'
        jsr     SYNCHR
        jsr     GETBYT                  ; X = file number
        dex
        cpx     #16
        jcs     snd_iqerr
        jsr     mia_sd_select_handle    ; X still holds the slot
        lda     #SD_OPEN_MODE
        jsr     mia_sd_seek
        lda     TEMP1                   ; A = mode byte
        sta     IDXA_PORT
        lda     #MIA_CMD_FS_OPEN
        jsr     mia_sd_cmd
        jne     mia_fileerr
        rts

; ----------------------------------------------------------------------------
; CLOSE #n
; ----------------------------------------------------------------------------
BASIC_CLOSE:
        lda     #'#'
        jsr     SYNCHR
        jsr     GETBYT                  ; X = file number
        dex
        cpx     #16
        jcs     snd_iqerr
        jsr     mia_sd_select_handle
        lda     #MIA_CMD_FS_CLOSE
        jsr     mia_sd_cmd
        jne     mia_fileerr
        rts

; ----------------------------------------------------------------------------
; BGET#n, B : read one byte from file n into numeric variable B.
; ----------------------------------------------------------------------------
BASIC_BGET:
        jsr     GETBYT                  ; X = file number
        dex
        cpx     #16
        jcs     snd_iqerr
        jsr     mia_sd_select_handle
        jsr     CHKCOM
        lda     #SD_REQUEST_LEN_L
        jsr     mia_sd_seek
        lda     #1
        sta     IDXA_PORT
        lda     #$00
        sta     IDXA_PORT
        lda     #MIA_CMD_FS_READ
        jsr     mia_sd_cmd
        jne     mia_fileerr
        jsr     mia_sd_select_transfer
        lda     IDXA_PORT               ; the byte read
        jmp     mia_store_byte          ; stores into the variable named next

; ----------------------------------------------------------------------------
; BPUT#n, B : write the low byte of numeric expression B to file n.
; ----------------------------------------------------------------------------
BASIC_BPUT:
        jsr     GETBYT                  ; X = file number
        dex
        cpx     #16
        jcs     snd_iqerr
        jsr     mia_sd_select_handle
        jsr     COMBYTE                 ; X = value 0-255
        stx     TEMP1
        jsr     mia_sd_select_transfer
        lda     TEMP1
        sta     IDXA_PORT
        lda     #SD_REQUEST_LEN_L
        jsr     mia_sd_seek
        lda     #1
        sta     IDXA_PORT
        lda     #$00
        sta     IDXA_PORT
        lda     #MIA_CMD_FS_WRITE
        jsr     mia_sd_cmd
        jne     mia_fileerr
        rts

; ----------------------------------------------------------------------------
; MIALOAD "path", addr[, maxlen] : load a file straight into MIA RAM at a raw
; address (0-16777215, well past MIA's 256KB) - zero CPU byte-touching. This
; is the generic counterpart to CHRLOAD/PALLOAD/etc.: those wrap the same
; underlying job with a safe, bank/offset-checked address; MIALOAD exposes
; the raw address directly, for anything without its own convenience
; wrapper (audio registers, or any other MIA RAM region). maxlen omitted or
; 0 means load until EOF or the end of MIA RAM.
; ----------------------------------------------------------------------------
BASIC_MIALOAD:
        jsr     FRMEVL                  ; evaluate the path expression
        bit     VALTYP
        jpl     mia_typerr              ; must be a string
        jsr     FREFAC                  ; A = length, INDEX = pointer
        jsr     mia_sd_write_path
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     mia_getadr24            ; VID_ADDR = 24-bit address
        jsr     CHRGOT                  ; peek: is a trailing ",maxlen" present?
        cmp     #','
        bne     @nolen
        jsr     CHRGET
        jsr     FRMNUM
        jsr     GETADR                  ; LINNUM = maxlen (16-bit)
        lda     LINNUM
        sta     VID_COUNT
        lda     LINNUM+1
        sta     VID_COUNT+1
        jmp     mia_sd_load_trigger
@nolen:
        lda     #$00
        sta     VID_COUNT
        sta     VID_COUNT+1
        jmp     mia_sd_load_trigger

; ----------------------------------------------------------------------------
; MIASAVE "path", addr, len : save `len` bytes of MIA RAM starting at `addr`
; to a file. len is mandatory here (unlike MIALOAD's optional maxlen): MIA
; RAM has no "file size" of its own until told how much to write, the same
; asymmetry GW-BASIC's own BLOAD/BSAVE have.
; ----------------------------------------------------------------------------
BASIC_MIASAVE:
        jsr     FRMEVL
        bit     VALTYP
        jpl     mia_typerr
        jsr     FREFAC
        jsr     mia_sd_write_path
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     mia_getadr24            ; VID_ADDR = 24-bit address
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     GETADR                  ; LINNUM = len (16-bit)
        lda     LINNUM
        sta     VID_COUNT
        lda     LINNUM+1
        sta     VID_COUNT+1
        jmp     mia_sd_save_trigger

; ----------------------------------------------------------------------------
; SEEK#n,pos : jump file n to byte offset pos (0-16777215) - wraps FS_SEEK.
; ----------------------------------------------------------------------------
BASIC_SEEK:
        jsr     GETBYT                  ; X = file number
        dex
        cpx     #16
        jcs     snd_iqerr
        jsr     mia_sd_select_handle
        jsr     CHKCOM
        jsr     FRMNUM
        jsr     mia_getadr24            ; VID_ADDR = 24-bit offset
        lda     #SD_FILE_POS0
        jsr     mia_sd_seek
        lda     VID_ADDR
        sta     IDXA_PORT
        lda     VID_ADDR+1
        sta     IDXA_PORT
        lda     VID_ADDR+2
        sta     IDXA_PORT
        lda     #$00
        sta     IDXA_PORT
        lda     #MIA_CMD_FS_SEEK
        jsr     mia_sd_cmd
        jne     mia_fileerr
        rts

; ----------------------------------------------------------------------------
; KILL "path" : delete a file (GW-BASIC's real name for this) - wraps
; FS_DELETE. RMDIR shares this exact body: FatFs's f_unlink (what FS_DELETE
; calls) already deletes either a file or an empty directory, so there is
; nothing RMDIR needs to do differently - see token.s.
; ----------------------------------------------------------------------------
BASIC_KILL:
        jsr     mia_parse_path_expr
        lda     #MIA_CMD_FS_DELETE
        jsr     mia_sd_cmd
        jne     mia_fileerr
        rts

; ----------------------------------------------------------------------------
; MKDIR "path" : create one directory (parent directories must already
; exist) - wraps FS_MKDIR.
; ----------------------------------------------------------------------------
BASIC_MKDIR:
        jsr     mia_parse_path_expr
        lda     #MIA_CMD_FS_MKDIR
        jsr     mia_sd_cmd
        jne     mia_fileerr
        rts

; ----------------------------------------------------------------------------
; NAME "old" AS "new" : rename/move (GW-BASIC's real syntax) - wraps
; FS_RENAME.
; ----------------------------------------------------------------------------
BASIC_NAME:
        jsr     FRMEVL                  ; evaluate "old"
        bit     VALTYP
        jpl     mia_typerr
        jsr     FREFAC
        jsr     mia_sd_write_path
        lda     #<lit_AS
        ldy     #>lit_AS
        jsr     mia_match_word
        jsr     FRMEVL                  ; evaluate "new"
        bit     VALTYP
        jpl     mia_typerr
        jsr     FREFAC
        jsr     mia_sd_write_path2
        lda     #MIA_CMD_FS_RENAME
        jsr     mia_sd_cmd
        jne     mia_fileerr
        rts

; ----------------------------------------------------------------------------
; CD "path" : change the current directory - wraps FS_CHDIR. This is what
; makes relative paths in every other command (OPEN/KILL/MKDIR/MIALOAD/...)
; resolve inside "path" from here on: FatFs itself tracks the current
; directory per mounted volume (FF_FS_RPATH in clementina-mia's ffconf.h) and
; every existing path-writing routine already passes relative paths through
; unmodified, so nothing else needed to change. See clementina-mia sd.c's
; sd_request_chdir and sd_prepare_fatfs_path_from.
; ----------------------------------------------------------------------------
BASIC_CD:
        jsr     mia_parse_path_expr
        lda     #MIA_CMD_FS_CHDIR
        jsr     mia_sd_cmd
        jne     mia_fileerr
        rts

; ----------------------------------------------------------------------------
; DIR [path$] : list a directory - wraps FS_OPENDIR/FS_READDIR. With no
; argument, lists the current directory (CD's target, or the SD root if CD
; has never been used); an explicit path$ lists that directory instead,
; without changing the current directory. One name per line, directories
; marked with a trailing "/" (sizes/dates are not printed - see
; docs/basic-file.md for the rationale).
;
; Each FS_READDIR result's own DIR_NAME_LEN field (not the transient SD_EOF
; control-block flag EOF(n) reads) is what signals "no more entries": SD_EOF
; is shared with per-handle file I/O and reads back whatever handle
; SD_HANDLE_SELECT last pointed at (see clementina-mia sd.c's sd_publish_state)
; - wrong here if a file happens to be open on that same slot while DIR runs.
; DIR_NAME_LEN has no such ambiguity: sd_clear_dir_entry zeroes it, and a
; real entry's name is never zero length.
; ----------------------------------------------------------------------------
BASIC_DIR:
        jsr     CHRGOT                  ; peek: any argument at all?
        cmp     #$3A                    ; ':' (next statement)
        beq     @noarg
        cmp     #$00                    ; end of line
        beq     @noarg
        jsr     FRMEVL
        bit     VALTYP
        jpl     mia_typerr
        jsr     FREFAC
        jsr     mia_sd_write_path
        jmp     @open
@noarg:
        lda     #$00                    ; empty path -> current directory
        jsr     mia_sd_write_path
@open:
        lda     #MIA_CMD_FS_OPENDIR
        jsr     mia_sd_cmd
        jne     mia_fileerr
@loop:
        lda     #MIA_CMD_FS_READDIR
        jsr     mia_sd_cmd
        jne     mia_fileerr
        jsr     mia_sd_select_dir_entry
        lda     IDXA_PORT               ; DIR_ATTR (offset 0)
        sta     TEMP1
        lda     IDXA_PORT               ; DIR_NAME_LEN (offset 1)
        beq     @done                   ; 0 -> no more entries
        cmp     #DIR_NAME_BUF_SIZE      ; clamp to the scratch buffer - the
        bcc     @fits                   ; next FS_READDIR/mia_sd_select_dir_entry
        lda     #DIR_NAME_BUF_SIZE      ; resets position from offset 0 again
        ; regardless, so an over-length name's untouched tail is simply
        ; never read, not left dangling for anything later to trip over.
@fits:  sta     TEMP2                   ; TEMP2 = bytes to read/print this entry
        ldy     #DIR_NAME-2             ; skip offsets 2..(DIR_NAME-1)
@skip:  lda     IDXA_PORT
        dey
        bne     @skip
        ldy     #$00                    ; copy the name out before printing
@read:  cpy     TEMP2                   ; any of it - see DIR_NAME_BUF's comment
        beq     @print
        lda     IDXA_PORT
        sta     DIR_NAME_BUF,y
        iny
        bne     @read                   ; always taken (TEMP2 <= 40)
@print: ldy     #$00
@pname: cpy     TEMP2
        beq     @nomarkcheck
        lda     DIR_NAME_BUF,y
        jsr     MONCOUT
        iny
        bne     @pname                  ; always taken (TEMP2 <= 40)
@nomarkcheck:
        lda     TEMP1
        and     #DIR_ATTR_DIRECTORY
        beq     @nomark
        lda     #'/'
        jsr     MONCOUT
@nomark:
        lda     #CR
        jsr     MONCOUT
        jmp     @loop
@done:
        rts

; ----------------------------------------------------------------------------
; EOF(n) : true (1) when file n is at end, false (0) otherwise. Dispatched via
; TOKEN_EXTFN/EXTFN_DISPATCH (see that routine's own comment) - PARCHK has
; already evaluated "(n)" into FAC by the time this body runs, so CONINT
; converts that already-evaluated FAC to a byte in X directly, without
; re-parsing anything from the source text (no FRMNUM/FRMEVL call here).
; Matches PLAYING's 0/1 convention (see BASIC_PLAYING), not classic BASIC's
; 0/-1 - either reads as "true" to IF, which is all a status check needs.
; ----------------------------------------------------------------------------
BASIC_EOF:
        jsr     CONINT                  ; X = file number, from PARCHK's FAC
        dex
        cpx     #16
        jcs     snd_iqerr
        jsr     mia_sd_select_handle
        lda     #SD_EOF
        jsr     mia_sd_seek
        ldy     #$00
        lda     IDXA_PORT
        beq     @done
        iny
@done:
        jmp     SNGFLT
