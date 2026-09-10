; ============================================================================
; clementina_extra.s - Clementina BASIC console glue (EXTRA segment)
; ----------------------------------------------------------------------------
; Thin thunks from BASIC's console contract into the Clementina kernel jump
; table. In the combined image the kernel lives at $0400 and owns the console.
; Keep these addresses in sync with src/kernel/kernel.inc / docs/memory-map.md.
; ============================================================================

.segment "EXTRA"
.export BASIC_COLD_START, BASIC_WARM_START, MONRDKEY, MONRDKEY_NB, MONCOUT, MONRDLINE

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

BASIC_PLAY:
        jsr     FRMEVL                  ; evaluate the argument expression
        jsr     FRESTR                  ; A = length, INDEX -> string character bytes
        sta     PLAY_LEN
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
