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
; Background PLAY - fixed RAM control block, below RAMSTART2 ($4500). Plain
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
BGP_BASE        = $4400
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
