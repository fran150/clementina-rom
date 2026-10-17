; ============================================================================
; load.s - KERN_LOAD: stream a file straight into CPU RAM, optionally
; transferring control to it afterward. Implements the jump table's
; KERN_LOAD slot (kernel.s/kernel.inc) - previously a stub.
; ----------------------------------------------------------------------------
; Entirely self-contained kernel-resident code for the whole copy: it never
; calls out to clementina_extra.s's mia_sd_cmd/mia_sd_seek/etc, because a
; load whose destination reaches into BASIC's own resident region may
; have already overwritten those routines by the time a later chunk needs
; them. The handful of MIA SD/FS primitives below are a deliberate
; duplication of that BASIC-side plumbing, required for correctness, not an
; oversight - see docs/memory-map.md and the BLOAD design notes.
;
; The file path is staged by the caller (BASIC_BLOAD, clementina_extra.s)
; directly into MIA's own FS path buffer via the existing mia_parse_path_expr
; - that's MIA hardware state, not CPU RAM, so it is untouched by anything
; this routine goes on to overwrite. mia_fileerr (clementina_extra.s) is
; reached for errors detected before any destination byte is written - safe,
; since BASIC's own code (mia_fileerr included) is still guaranteed intact
; at that point; once the copy has overwritten BASIC, errors are not
; gracefully recoverable (documented limitation - see below).
;
; The destination is the caller's choice (2026-10-13): any CPU RAM below
; $C000, including the kernel, BASIC, its heap and bank 0. Nothing checks
; whether BASIC or the kernel survive the load; docs/basic-file.md says
; where loading is safe.
;
; Entry (set by the caller before JMP load):
;   A             = the bank to use at $8000-$BFFF (BASIC passes DATA_BANK).
;   C             = 0 to return when done, 1 to jump.
;   KPTR ($F0-F1) = destination override address, or $0000 to use the file's
;                   own header address (the header is always consumed).
;   KTMP ($F2-F3) = with C=1, the run address, or $0000 for the first byte
;                   loaded. Ignored with C=0.
; Exit:
;   C=0: RTS with the bank mapped at entry selected again.
;   C=1: JMP to the run address with IRQs enabled and bank A selected.
;
; PRG format (see docs/basic-file.md): [addr_lo][addr_hi] then the data. The
; header address and an override must both be below $C000 (I/O and the MIA
; region are not RAM). Bytes from $8000 up go to bank A; data that reaches
; $C000 continues at $8000 in the next bank.
; ============================================================================

; .macpack longbranch already active by this point in kernel.s's include
; chain (memory.s brings it in) - the jeq/jne/etc pseudo-ops used below just
; work.
.segment "KERNCODE"
.import mia_fileerr

KLOAD_HANDLE = 14              ; distinct from BASIC's own LOAD/SAVE handle (15)
KLOAD_CHUNK  = 128

; MIA's SD/FS names (MIA_SD_*, MIA_FS_*, MIA_CMD_FS_*) come from mia.inc,
; which kernel.inc includes.

; Zero-page scratch, all within the kernel's own reserved block ($F0-$FB) -
; see kernel.inc. KPTR/KTMP carry the caller's inputs in; once the header is
; parsed, KPTR is repurposed as the live write cursor (its "override or not"
; question has already been answered by then).
KLOAD_BANK    = $F9    ; bank selected while copying
KLOAD_CHUNKLEN = $FA   ; bytes actually read this round (also header scratch
                        ; for the addr_lo byte while deciding the destination)
KLOAD_SCRATCH = $FB    ; header addr_hi scratch while deciding the destination

; ----------------------------------------------------------------------------
; Kernel-local MIA SD/FS primitives - mirror clementina_extra.s's
; mia_sd_seek/mia_sd_wait/mia_sd_cmd/mia_sd_select_handle, kept private to
; this file (kld_ prefix) so nothing here ever depends on BASIC-resident code
; staying intact mid-copy.
; ----------------------------------------------------------------------------
kld_seek:
        pha
        lda     #MIA_SD_INDEX_CONTROL
        sta     IDXA_SELECT
        lda     #CFG_IDXA_ADDR_H
        sta     CFG_SELECT
        lda     #^MIA_SD_CONTROL_OFFSET
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_M
        sta     CFG_SELECT
        lda     #>MIA_SD_CONTROL_OFFSET
        sta     CFG_PORT
        lda     #CFG_IDXA_ADDR_L
        sta     CFG_SELECT
        pla
        sta     CFG_PORT
        rts

kld_wait:
        lda     STATUS_L
        and     #$04                    ; MIA_STAT_CMD_RUNNING
        bne     kld_wait
        lda     STATUS_H
        and     #>MIA_STAT_SD_BUSY
        bne     kld_wait
        rts

; A = command id. Clears CMD_PARAM1-3, triggers, waits, leaves MIA_SD_CONTROL_LAST_ERROR
; in A (Z set = success). Clobbers A,X.
kld_cmd:
        pha
        stz     CMD_PARAM1
        stz     CMD_PARAM2
        stz     CMD_PARAM3
        pla
        sta     CMD_TRIGGER
        jsr     kld_wait
        lda     #MIA_SD_CONTROL_LAST_ERROR
        jsr     kld_seek
        lda     IDXA_PORT
        rts

; X = slot. Clobbers A,X.
kld_select_handle:
        txa
        pha
        lda     #MIA_SD_CONTROL_HANDLE_SELECT
        jsr     kld_seek
        pla
        sta     IDXA_PORT
        rts

; Bind window A to the transfer buffer and reset its position to offset 0 -
; selecting the index alone does not rewind it (same reasoning as kld_seek),
; so without this explicit reposition, a second read in the same call would
; silently continue from wherever the previous one left off. Mirrors
; mia_sd_select_transfer's own fixed absolute address ($013440).
; Clobbers A.
kld_select_transfer:
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

; Read one byte from the open file into A. Uses a 1-byte FS_READ, same idiom
; BGET# uses. Only used for the 2-byte PRG header, where the simplicity
; of one-byte-at-a-time outweighs the chunking BASIC_LOAD needs for whole
; programs. Clobbers A,X.
kld_read_byte:
        ldx     #KLOAD_HANDLE
        jsr     kld_select_handle
        lda     #MIA_SD_CONTROL_REQUEST_LEN_L
        jsr     kld_seek
        lda     #$01
        sta     IDXA_PORT
        stz     IDXA_PORT
        lda     #MIA_CMD_FS_READ
        jsr     kld_cmd
        jne     kload_err_safe
        jsr     kld_select_transfer
        lda     IDXA_PORT
        rts

; A = min(KLOAD_CHUNK, $C000-KPTR). Never returns 0 - the copy loop only
; calls this starting below $C000 or freshly auto-advanced back to $8000,
; never sitting exactly on it. Clobbers A,X.
kld_chunk_request_len:
        sec
        lda     #$00
        sbc     KPTR
        tax                             ; X = low byte of ($C000 - KPTR)
        lda     #$C0
        sbc     KPTR+1
        bne     @full                   ; high byte nonzero -> room for 128+
        cpx     #KLOAD_CHUNK+1
        bcs     @full                   ; room in [129,255] -> full chunk fits
        txa                             ; room in [1,128] -> that's the request
        rts
@full:
        lda     #KLOAD_CHUNK
        rts

; ----------------------------------------------------------------------------
load:
        and     #VIA_DDRA_BANK_BITS
        sta     KLOAD_BANK              ; bank for $8000-$BFFF
        sta     KLOAD_RUN_BANK          ; mapped again for a jump
        ror     KLOAD_MODE              ; bit 7 = C: jump when done
        lda     VIA_ORA
        and     #VIA_DDRA_BANK_BITS
        sta     KLOAD_SAVED_BANK        ; put back on return or error

        ldx     #KLOAD_HANDLE
        jsr     kld_select_handle
        lda     #MIA_SD_CONTROL_OPEN_MODE
        jsr     kld_seek
        lda     #MIA_FS_OPEN_READ
        sta     IDXA_PORT
        lda     #MIA_CMD_FS_OPEN
        jsr     kld_cmd
        jne     kload_err_safe          ; nothing written yet - safe to error

        ; Header is always consumed, even when overriding the destination.
        jsr     kld_read_byte
        sta     KLOAD_CHUNKLEN          ; addr_lo, temp home until decided
        jsr     kld_read_byte
        sta     KLOAD_SCRATCH           ; addr_hi, temp home until decided

        ; Destination = override (KPTR) if given, else the header's own.
        lda     KPTR
        ora     KPTR+1
        bne     @have_dest
        lda     KLOAD_CHUNKLEN
        sta     KPTR
        lda     KLOAD_SCRATCH
        sta     KPTR+1

@have_dest:
        lda     KPTR+1
        cmp     #$C0
        jcs     kload_err_close_safe    ; $C000 and up is I/O/MIA, not RAM

        ; A run load may overwrite whatever IRQ_VEC points at, so mask IRQs
        ; while copying; the final JMP re-enables them. Without a run
        ; address it jumps to the first byte loaded.
        bit     KLOAD_MODE
        bpl     @dest_decided
        sei
        lda     KTMP
        ora     KTMP+1
        bne     @dest_decided
        lda     KPTR
        sta     KTMP
        lda     KPTR+1
        sta     KTMP+1

@dest_decided:
        ; Chunked copy, mirroring BASIC_LOAD's own 128-byte pattern
        ; (clementina_extra.s) but writing straight to KPTR instead of
        ; BASIC's TXTTAB, and bank-aware. Each request is capped to never
        ; cross $C000, so a chunk lands exactly on the auto-advance point
        ; instead of writing into I/O.
@chunk:
        lda     KLOAD_BANK
        sta     VIA_ORA
        jsr     kld_chunk_request_len   ; A = capped request length, 1-128
        sta     KLOAD_CHUNKLEN

        ldx     #KLOAD_HANDLE
        jsr     kld_select_handle
        lda     #MIA_SD_CONTROL_REQUEST_LEN_L
        jsr     kld_seek
        lda     KLOAD_CHUNKLEN
        sta     IDXA_PORT
        stz     IDXA_PORT
        lda     #MIA_CMD_FS_READ
        jsr     kld_cmd
        jne     kload_err_unsafe

        lda     KLOAD_CHUNKLEN          ; stash the requested length across the
        pha                             ; result-length read below
        lda     #MIA_SD_CONTROL_RESULT_LEN_L
        jsr     kld_seek
        lda     IDXA_PORT
        sta     KLOAD_CHUNKLEN          ; now the actual result length
        bne     @have_data
        pla                             ; discard the stashed requested length
        jmp     @eof                    ; 0 -> nothing left to read

@have_data:
        jsr     kld_select_transfer
        ldy     #$00
@copyin:
        lda     IDXA_PORT
        sta     (KPTR),y
        iny
        cpy     KLOAD_CHUNKLEN
        bne     @copyin

        clc
        lda     KPTR
        adc     KLOAD_CHUNKLEN
        sta     KPTR
        lda     KPTR+1
        adc     #$00
        sta     KPTR+1

        pla                             ; requested length
        cmp     KLOAD_CHUNKLEN          ; == actual result?
        bne     @eof                    ; short vs. what we asked for -> done,
                                         ; regardless of where the cursor landed

        ; More data follows. The request cap above guarantees the cursor
        ; never overshoots the boundary, only ever lands exactly on it or
        ; short of it.
        lda     KPTR+1
        cmp     #$C0
        bne     @chunk                  ; short of the boundary - keep going
        lda     #$80
        sta     KPTR+1
        inc     KLOAD_BANK
        lda     KLOAD_BANK
        cmp     #32
        jcs     kload_err_unsafe        ; destination ran past the last bank
        jmp     @chunk

@eof:
        ldx     #KLOAD_HANDLE
        jsr     kld_select_handle
        lda     #MIA_CMD_FS_CLOSE
        jsr     kld_cmd
        ; ignore a close failure here - we already have everything we came for

        bit     KLOAD_MODE
        bmi     @go_run

        ; Returning: put back the bank mapped at entry (bank 0 for BASIC).
        lda     KLOAD_SAVED_BANK
        sta     VIA_ORA
        rts

@go_run:
        ; Handing off for good - re-enable interrupts (matches a freshly
        ; reset machine's state) and jump with the bank the caller asked for
        ; mapped, whichever bank the last byte landed in.
        lda     KLOAD_RUN_BANK
        sta     VIA_ORA
        cli
        jmp     (KTMP)

; ----------------------------------------------------------------------------
; Error exits.
;
; kload_err_safe / kload_err_close_safe: reached before any destination byte
; has been written (the file may be open - close_safe closes it first,
; best-effort) - BASIC's own code is guaranteed untouched, so handing off to
; its ordinary file-I/O error path is always coherent.
;
; kload_err_unsafe: reached mid-copy. If the copy never overwrote BASIC,
; this is exactly as safe as the two above. If it did, this is a documented,
; accepted limitation: there is no working interpreter left to necessarily
; report the error to. Best effort only.
;
; All three put back the bank mapped at entry, and a run load's masked IRQs.
; ----------------------------------------------------------------------------
kload_err_close_safe:
        ldx     #KLOAD_HANDLE
        jsr     kld_select_handle
        lda     #MIA_CMD_FS_CLOSE
        jsr     kld_cmd                 ; best-effort close, ignore its result
kload_err_safe:
kload_err_unsafe:
        lda     KLOAD_SAVED_BANK
        sta     VIA_ORA
        bit     KLOAD_MODE
        bpl     @fileerr
        cli                             ; undo a run load's SEI
@fileerr:
        jmp     mia_fileerr
